import Foundation
import os.log

/// Protocol for receiving transcription events
protocol SpeechTranscriberDelegate: AnyObject, Sendable {
    nonisolated func onInterimResult(_ text: String)
    nonisolated func onFinalResult(_ text: String)
    nonisolated func onError(_ error: Error)
}

/// Handles streaming transcription using Google Cloud Speech-to-Text gRPC API
final class SpeechTranscriber {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "SpeechTranscriber")

    weak var delegate: SpeechTranscriberDelegate?

    private let apiKey: String
    private let language: String

    private var isStreaming = false
    private var streamTask: Task<Void, Never>?
    private var accumulatedTranscript = ""

    /// Google Speech-to-Text V2 API endpoint
    private let apiEndpoint = "https://speech.googleapis.com/v2/projects/-/locations/global/recognizers/_:recognize"

    init(apiKey: String, language: String = "en-US") {
        self.apiKey = apiKey
        self.language = language
        logger.info("SpeechTranscriber initialized with language: \(language)")
    }

    /// Start streaming transcription
    func startStreaming(audioRecorder: AudioRecorder) {
        guard !isStreaming else {
            debugLog("SpeechTranscriber: Already streaming, ignoring start request")
            return
        }

        debugLog("SpeechTranscriber: Starting streaming transcription")
        isStreaming = true
        accumulatedTranscript = ""

        streamTask = Task { [weak self] in
            debugLog("SpeechTranscriber: Stream task started")
            await self?.runStreamingSession(audioRecorder: audioRecorder)
            debugLog("SpeechTranscriber: Stream task ended")
        }
    }

    /// Stop streaming transcription
    func stopStreaming() {
        guard isStreaming else { return }

        logger.info("Stopping streaming transcription")
        isStreaming = false
        streamTask?.cancel()
        streamTask = nil
    }

    /// Run the streaming session using chunked HTTP (simulating gRPC behavior)
    /// Note: True gRPC requires additional setup. This uses the REST API with chunked audio.
    private func runStreamingSession(audioRecorder: AudioRecorder) async {
        debugLog("SpeechTranscriber: Streaming session started, waiting for audio chunks...")

        var audioChunks: [Data] = []
        var chunkCount = 0

        // Collect audio chunks until end of stream
        while let chunk = audioRecorder.getNextChunk() {
            audioChunks.append(chunk)
            chunkCount += 1

            if chunkCount == 1 {
                debugLog("SpeechTranscriber: Received first audio chunk (\(chunk.count) bytes)")
            }

            // For interim results, send to Google periodically
            if chunkCount % 15 == 0 {  // Every ~1 second of audio
                debugLog("SpeechTranscriber: Sending interim transcription request (chunk \(chunkCount))")
                let currentAudio = audioChunks.reduce(Data()) { $0 + $1 }
                if let interimText = await transcribeAudio(currentAudio, isFinal: false) {
                    debugLog("SpeechTranscriber: Interim result: \(interimText)")
                    await MainActor.run { [weak self] in
                        self?.delegate?.onInterimResult(interimText)
                    }
                } else {
                    debugLog("SpeechTranscriber: Interim transcription returned nil")
                }
            }
        }

        debugLog("SpeechTranscriber: Audio stream ended, received \(chunkCount) chunks")

        // Combine all audio and send final transcription request
        let allAudio = audioChunks.reduce(Data()) { $0 + $1 }
        debugLog("SpeechTranscriber: Total audio size: \(allAudio.count) bytes")

        if allAudio.isEmpty {
            debugLog("SpeechTranscriber: ERROR - No audio data received")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(TranscriberError.noAudioData)
            }
            isStreaming = false
            return
        }

        // Final transcription
        debugLog("SpeechTranscriber: Sending final transcription request...")
        if let finalText = await transcribeAudio(allAudio, isFinal: true) {
            debugLog("SpeechTranscriber: Final transcription: \(finalText)")
            await MainActor.run { [weak self] in
                self?.delegate?.onFinalResult(finalText)
            }
        } else {
            debugLog("SpeechTranscriber: ERROR - Failed to get final transcription")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(TranscriberError.transcriptionFailed)
            }
        }

        isStreaming = false
        debugLog("SpeechTranscriber: Streaming session ended")
    }

    /// Transcribe audio using Google Cloud Speech-to-Text REST API
    private func transcribeAudio(_ audioData: Data, isFinal: Bool) async -> String? {
        guard !apiKey.isEmpty else {
            debugLog("SpeechTranscriber: ERROR - API key is empty")
            return nil
        }

        let base64Audio = audioData.base64EncodedString()

        // V2 API request format
        let requestBody: [String: Any] = [
            "config": [
                "explicitDecodingConfig": [
                    "encoding": "LINEAR16",
                    "sampleRateHertz": 16000,
                    "audioChannelCount": 1
                ],
                "languageCodes": [language],
                "model": "short",
                "features": [
                    "enableAutomaticPunctuation": true,
                    "enableSpokenPunctuation": true,
                    "enableSpokenEmojis": true
                ]
            ],
            "content": base64Audio
        ]

        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            debugLog("SpeechTranscriber: ERROR - Failed to create API URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            debugLog("SpeechTranscriber: ERROR - Failed to serialize request: \(error.localizedDescription)")
            return nil
        }

        debugLog("SpeechTranscriber: Sending \(isFinal ? "final" : "interim") request (\(audioData.count) bytes)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                debugLog("SpeechTranscriber: ERROR - Invalid response type")
                return nil
            }

            debugLog("SpeechTranscriber: Response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    debugLog("SpeechTranscriber: API error (\(httpResponse.statusCode)): \(errorBody.prefix(500))")
                }
                return nil
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                debugLog("SpeechTranscriber: ERROR - Failed to parse response JSON")
                return nil
            }

            // Extract transcript from results
            guard let results = json["results"] as? [[String: Any]] else {
                debugLog("SpeechTranscriber: No results in response (empty audio?)")
                return ""
            }

            var fullTranscript = ""
            for result in results {
                if let alternatives = result["alternatives"] as? [[String: Any]],
                   let firstAlt = alternatives.first,
                   let transcript = firstAlt["transcript"] as? String {
                    fullTranscript += transcript
                }
            }

            debugLog("SpeechTranscriber: Got transcript: \(fullTranscript.prefix(100))")
            return fullTranscript.isEmpty ? nil : fullTranscript

        } catch {
            debugLog("SpeechTranscriber: ERROR - Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    var streaming: Bool {
        return isStreaming
    }
}

/// Transcription errors
enum TranscriberError: Error, LocalizedError {
    case noAudioData
    case transcriptionFailed
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .noAudioData:
            return "No audio data received"
        case .transcriptionFailed:
            return "Transcription failed"
        case .apiKeyMissing:
            return "API key is missing"
        }
    }
}
