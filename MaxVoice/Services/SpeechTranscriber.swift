import Foundation
import os.log

/// Protocol for receiving transcription events
protocol SpeechTranscriberDelegate: AnyObject {
    func onInterimResult(_ text: String)
    func onFinalResult(_ text: String)
    func onError(_ error: Error)
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

    /// Google Speech-to-Text streaming endpoint
    private let apiEndpoint = "https://speech.googleapis.com/v1/speech:recognize"
    private let streamingEndpoint = "https://speech.googleapis.com/v1/speech:streamingRecognize"

    init(apiKey: String, language: String = "en-US") {
        self.apiKey = apiKey
        self.language = language
        logger.info("SpeechTranscriber initialized with language: \(language)")
    }

    /// Start streaming transcription
    func startStreaming(audioRecorder: AudioRecorder) {
        guard !isStreaming else {
            logger.warning("Already streaming, ignoring start request")
            return
        }

        logger.info("Starting streaming transcription")
        isStreaming = true
        accumulatedTranscript = ""

        streamTask = Task { [weak self] in
            await self?.runStreamingSession(audioRecorder: audioRecorder)
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
        logger.info("Streaming session started")

        var audioChunks: [Data] = []
        var chunkCount = 0

        // Collect audio chunks until end of stream
        while let chunk = audioRecorder.getNextChunk() {
            audioChunks.append(chunk)
            chunkCount += 1

            // For interim results, we'd need true gRPC bidirectional streaming
            // With REST API, we send updates periodically
            if chunkCount % 15 == 0 {  // Every ~1 second of audio
                let currentAudio = audioChunks.reduce(Data()) { $0 + $1 }
                if let interimText = await transcribeAudio(currentAudio, isFinal: false) {
                    logger.debug("Interim result: \(interimText)")
                    await MainActor.run { [weak self] in
                        self?.delegate?.onInterimResult(interimText)
                    }
                }
            }
        }

        logger.info("Audio stream ended, received \(chunkCount) chunks")

        // Combine all audio and send final transcription request
        let allAudio = audioChunks.reduce(Data()) { $0 + $1 }
        logger.info("Total audio size: \(allAudio.count) bytes")

        if allAudio.isEmpty {
            logger.warning("No audio data received")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(TranscriberError.noAudioData)
            }
            isStreaming = false
            return
        }

        // Final transcription
        if let finalText = await transcribeAudio(allAudio, isFinal: true) {
            logger.info("Final transcription: \(finalText)")
            await MainActor.run { [weak self] in
                self?.delegate?.onFinalResult(finalText)
            }
        } else {
            logger.error("Failed to get final transcription")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(TranscriberError.transcriptionFailed)
            }
        }

        isStreaming = false
        logger.info("Streaming session ended")
    }

    /// Transcribe audio using Google Cloud Speech-to-Text REST API
    private func transcribeAudio(_ audioData: Data, isFinal: Bool) async -> String? {
        guard !apiKey.isEmpty else {
            logger.error("API key is empty")
            return nil
        }

        let base64Audio = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 16000,
                "languageCode": language,
                "model": "latest_long",
                "useEnhanced": true,
                "enableAutomaticPunctuation": true
            ],
            "audio": [
                "content": base64Audio
            ]
        ]

        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            logger.error("Failed to create API URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to serialize request: \(error.localizedDescription)")
            return nil
        }

        logger.debug("Sending \(isFinal ? "final" : "interim") transcription request (\(audioData.count) bytes audio)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                return nil
            }

            if httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    logger.error("Speech API error (\(httpResponse.statusCode)): \(errorBody)")
                }
                return nil
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Failed to parse response JSON")
                return nil
            }

            // Extract transcript from results
            guard let results = json["results"] as? [[String: Any]] else {
                logger.debug("No results in response")
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

            return fullTranscript.isEmpty ? nil : fullTranscript

        } catch {
            logger.error("Transcription request failed: \(error.localizedDescription)")
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
