import AVFoundation
import os.log

/// Records audio from the microphone and converts to 16kHz mono LINEAR16 format for Google Speech-to-Text
final class AudioRecorder {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AudioRecorder")

    private let audioEngine = AVAudioEngine()
    private let audioQueue = AudioQueue()

    private var isRecording = false
    private var recordingStartTime: Date?

    /// Target format for Google Speech-to-Text: 16kHz mono
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    init() {
        logger.info("AudioRecorder initialized")
    }

    /// Request microphone permission
    func requestPermission() async -> Bool {
        debugLog("AudioRecorder.requestPermission called")

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        debugLog("Current microphone authorization status: \(status.rawValue)")

        switch status {
        case .authorized:
            debugLog("Microphone already authorized")
            return true
        case .notDetermined:
            debugLog("Microphone permission not determined, requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            debugLog("Microphone permission \(granted ? "granted" : "denied")")
            return granted
        case .denied, .restricted:
            debugLog("Microphone permission denied or restricted")
            return false
        @unknown default:
            debugLog("Unknown microphone authorization status")
            return false
        }
    }

    /// Set up the audio pipeline - tap input directly and convert
    private func setupAudioPipeline() throws {
        debugLog("Setting up audio pipeline")

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        debugLog("Input device format - sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")

        // Store input format for conversion
        self.inputSampleRate = inputFormat.sampleRate
        self.inputChannels = Int(inputFormat.channelCount)

        // Install tap directly on input node with native format
        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }

        debugLog("Audio tap installed on input node with buffer size: \(bufferSize)")
    }

    private var inputSampleRate: Double = 48000
    private var inputChannels: Int = 2

    /// Process input buffer - convert from native format to 16kHz mono LINEAR16
    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            debugLog("AudioRecorder: No channel data in audio buffer")
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Calculate decimation factor (e.g., 48000 / 16000 = 3)
        let decimationFactor = Int(inputSampleRate / targetSampleRate)
        let outputFrameCount = frameCount / decimationFactor

        // Log audio level periodically
        var maxSample: Float = 0
        for i in 0..<min(frameCount, 100) {
            maxSample = max(maxSample, abs(channelData[0][i]))
        }

        bufferCount += 1
        if bufferCount == 1 || bufferCount % 50 == 0 {
            debugLog("AudioRecorder: Buffer \(bufferCount), frames=\(frameCount), outputFrames=\(outputFrameCount), maxSample=\(maxSample)")
        }

        // Convert to mono and downsample
        var int16Data = [Int16](repeating: 0, count: outputFrameCount)

        for i in 0..<outputFrameCount {
            let srcIndex = i * decimationFactor

            // Mix channels to mono
            var sample: Float = 0
            for ch in 0..<inputChannels {
                sample += channelData[ch][srcIndex]
            }
            sample /= Float(inputChannels)

            // Clamp and convert to Int16
            sample = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(sample * 32767.0)
        }

        // Convert to Data
        let data = int16Data.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }

        audioQueue.push(data)
    }

    private var bufferCount = 0

    /// Start recording audio
    func startRecording() throws {
        guard !isRecording else {
            debugLog("AudioRecorder: Already recording, ignoring start request")
            return
        }

        debugLog("AudioRecorder: Starting audio recording")
        recordingStartTime = Date()
        bufferCount = 0

        // Clear any leftover data
        audioQueue.clear()

        // Set up pipeline
        try setupAudioPipeline()

        // Start the audio engine
        do {
            try audioEngine.start()
            isRecording = true
            logger.info("Audio engine started successfully")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Stop recording and signal end of stream
    func stopRecording() {
        guard isRecording else {
            debugLog("AudioRecorder: Not recording, ignoring stop request")
            return
        }

        debugLog("AudioRecorder: Stopping audio recording")

        // Calculate recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            debugLog("AudioRecorder: Recording duration: \(String(format: "%.2f", duration)) seconds")
        }

        // Stop the engine and remove tap
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRecording = false

        // Push end-of-stream sentinel
        audioQueue.push(nil)

        debugLog("AudioRecorder: Audio recording stopped")
    }

    /// Get next audio chunk (blocking)
    func getNextChunk() -> Data? {
        return audioQueue.pop()
    }

    /// Check if currently recording
    var recording: Bool {
        return isRecording
    }
}

/// Errors that can occur during audio recording
enum AudioRecorderError: Error, LocalizedError {
    case formatCreationFailed
    case engineStartFailed(Error)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
