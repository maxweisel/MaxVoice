import Cocoa
import os.log

/// Main application state coordinator
final class AppState: HotkeyMonitorDelegate, SpeechTranscriberDelegate {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AppState")

    // Components
    private let configManager = ConfigManager.shared
    private var config: Config?
    private var audioRecorder: AudioRecorder?
    private var transcriber: SpeechTranscriber?
    private var postProcessor: GeminiPostProcessor?
    private let replacer = TextReplacer()
    private let hotkeyMonitor = HotkeyMonitor()
    private let overlay = TranscriptionOverlay()
    private let paster = ClipboardPaster()

    // State
    private var isRecording = false
    private var recordingStartPoint: NSPoint?

    init() {
        logger.info("AppState initializing")
        hotkeyMonitor.delegate = self
    }

    /// Start the application
    func start() {
        logger.info("Starting application")

        // Load config
        guard let config = configManager.load() else {
            logger.error("Failed to load config - check ~/.maxvoice/config.json")
            showConfigError()
            return
        }

        self.config = config
        logger.info("Config loaded successfully")

        // Validate API key
        guard !config.googleApiKey.isEmpty else {
            logger.error("Google API key is empty")
            showApiKeyError()
            return
        }

        // Initialize services
        audioRecorder = AudioRecorder()
        transcriber = SpeechTranscriber(apiKey: config.googleApiKey, language: config.language)
        transcriber?.delegate = self

        if !config.googleApiKey.isEmpty {
            postProcessor = GeminiPostProcessor(apiKey: config.googleApiKey)
        }

        // Start hotkey monitoring
        hotkeyMonitor.start()
        logger.info("Application started - listening for CMD key")
    }

    /// Stop the application
    func stop() {
        logger.info("Stopping application")
        hotkeyMonitor.stop()
        if isRecording {
            audioRecorder?.stopRecording()
        }
        overlay.hide()
    }

    // MARK: - HotkeyMonitorDelegate

    func onHotkeyPressed() {
        logger.info("Hotkey pressed - starting recording")

        guard !isRecording else {
            logger.warning("Already recording, ignoring")
            return
        }

        guard let audioRecorder = audioRecorder else {
            logger.error("AudioRecorder not initialized")
            return
        }

        // Play start sound
        SoundPlayer.playStart()

        // Get mouse position
        let mouseLocation = NSEvent.mouseLocation
        recordingStartPoint = mouseLocation

        // Show overlay
        overlay.show(near: mouseLocation)
        overlay.setListening()

        // Start recording
        do {
            try audioRecorder.startRecording()
            isRecording = true

            // Start transcription streaming
            transcriber?.startStreaming(audioRecorder: audioRecorder)

            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            SoundPlayer.playError()
            overlay.showError("Failed to start recording")
            isRecording = false
        }
    }

    func onHotkeyReleased() {
        logger.info("Hotkey released - stopping recording")

        guard isRecording else {
            logger.warning("Not recording, ignoring")
            return
        }

        isRecording = false

        // Stop recording (this sends end-of-stream to transcriber)
        audioRecorder?.stopRecording()

        // Show processing state
        overlay.setProcessing()

        logger.info("Recording stopped, waiting for final transcription")
    }

    // MARK: - SpeechTranscriberDelegate

    func onInterimResult(_ text: String) {
        logger.debug("Interim result: \(text)")
        DispatchQueue.main.async { [weak self] in
            self?.overlay.updateTranscript(text)
            self?.overlay.setTranscribing()
        }
    }

    func onFinalResult(_ text: String) {
        logger.info("Final transcription received: \(text)")

        Task { [weak self] in
            await self?.processAndPaste(text)
        }
    }

    func onError(_ error: Error) {
        logger.error("Transcription error: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            SoundPlayer.playError()
            self?.overlay.showError(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// Process transcript and paste result
    private func processAndPaste(_ transcript: String) async {
        logger.info("Processing transcript: \(transcript.count) characters")

        var result = transcript

        // Optional Gemini post-processing
        if let prompt = config?.postProcessingPrompt, !prompt.isEmpty, let processor = postProcessor {
            logger.info("Applying Gemini post-processing")
            result = await processor.process(transcript: result, prompt: prompt)
            logger.info("Post-processing complete")
        }

        // Apply word replacements
        if let replacements = config?.replacements, !replacements.isEmpty {
            logger.info("Applying word replacements")
            result = replacer.apply(replacements: replacements, to: result)
        }

        // Capture final result for use in MainActor block
        let finalResult = result

        // Play stop sound and paste
        await MainActor.run { [weak self] in
            SoundPlayer.playStop()
            self?.overlay.hide()

            if !finalResult.isEmpty {
                self?.paster.paste(text: finalResult)
                self?.logger.info("Pasted \(finalResult.count) characters")
            } else {
                self?.logger.warning("No text to paste")
            }
        }
    }

    /// Show config file error
    private func showConfigError() {
        overlay.show(near: NSEvent.mouseLocation)
        overlay.showError("Config not found — create ~/.maxvoice/config.json")
        SoundPlayer.playError()
    }

    /// Show API key error
    private func showApiKeyError() {
        overlay.show(near: NSEvent.mouseLocation)
        overlay.showError("API key missing — check ~/.maxvoice/config.json")
        SoundPlayer.playError()
    }
}
