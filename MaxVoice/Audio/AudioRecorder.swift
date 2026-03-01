import AVFoundation
import os.log

/// Records audio from the microphone and converts to 16kHz mono LINEAR16 format for Google Speech-to-Text
final class AudioRecorder {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AudioRecorder")

    private let audioEngine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
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
        logger.info("Requesting microphone permission")

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Current microphone authorization status: \(String(describing: status.rawValue))")

        switch status {
        case .authorized:
            logger.info("Microphone already authorized")
            return true
        case .notDetermined:
            logger.info("Microphone permission not determined, requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission \(granted ? "granted" : "denied")")
            return granted
        case .denied, .restricted:
            logger.warning("Microphone permission denied or restricted")
            return false
        @unknown default:
            logger.error("Unknown microphone authorization status")
            return false
        }
    }

    /// Set up the audio pipeline with stereo-to-mono conversion
    private func setupAudioPipeline() throws {
        logger.info("Setting up audio pipeline")

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        logger.info("Input device format - sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")

        // Create target format: 16kHz mono Float32
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            logger.error("Failed to create target audio format")
            throw AudioRecorderError.formatCreationFailed
        }

        logger.info("Target format - sample rate: \(monoFormat.sampleRate), channels: \(monoFormat.channelCount)")

        // Attach mixer node for stereo→mono conversion with proper gain
        audioEngine.attach(mixerNode)
        logger.debug("Mixer node attached")

        // Connect input → mixer (handles channel conversion and sample rate)
        audioEngine.connect(inputNode, to: mixerNode, format: inputFormat)
        logger.debug("Input node connected to mixer")

        // Install tap on mixer output to capture audio
        let bufferSize: AVAudioFrameCount = 1024  // ~64ms at 16kHz

        mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: monoFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }

        logger.info("Audio tap installed with buffer size: \(bufferSize)")
    }

    /// Process incoming audio buffer and convert to LINEAR16
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else {
            logger.warning("No channel data in audio buffer")
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Convert Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
        var int16Data = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))  // Clamp to prevent overflow
            int16Data[i] = Int16(sample * 32767.0)
        }

        // Convert to Data
        let data = int16Data.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }

        audioQueue.push(data)
    }

    /// Start recording audio
    func startRecording() throws {
        guard !isRecording else {
            logger.warning("Already recording, ignoring start request")
            return
        }

        logger.info("Starting audio recording")
        recordingStartTime = Date()

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
            logger.warning("Not recording, ignoring stop request")
            return
        }

        logger.info("Stopping audio recording")

        // Calculate recording duration
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Recording duration: \(String(format: "%.2f", duration)) seconds")
        }

        // Stop the engine
        audioEngine.stop()
        mixerNode.removeTap(onBus: 0)
        audioEngine.detach(mixerNode)

        isRecording = false

        // Push end-of-stream sentinel
        audioQueue.push(nil)

        logger.info("Audio recording stopped")
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
