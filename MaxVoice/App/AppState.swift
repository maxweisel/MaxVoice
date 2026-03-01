import Cocoa
import os.log

/// Main application state coordinator
@MainActor
final class AppState: HotkeyMonitorDelegate, SpeechTranscriberDelegate {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AppState")

    // Components
    private let configManager = ConfigManager.shared
    private var config: Config?
    private var audioRecorder: AudioRecorder?
    private var transcriber: GRPCStreamingTranscriber?
    private var postProcessor: GeminiPostProcessor?
    private let replacer = TextReplacer()
    private let hotkeyMonitor = HotkeyMonitor()
    private let overlay = TranscriptionOverlay()
    private let paster = ClipboardPaster()

    // State
    private var isRecording = false

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
            return
        }

        self.config = config
        logger.info("Config loaded successfully")

        // Initialize services
        audioRecorder = AudioRecorder()
        transcriber = GRPCStreamingTranscriber(apiKey: config.googleApiKey, language: config.language)
        transcriber?.delegate = self

        if !config.googleApiKey.isEmpty {
            postProcessor = GeminiPostProcessor(apiKey: config.googleApiKey)
        }

        // Start hotkey monitoring
        hotkeyMonitor.start()
        logger.info("Application started - press CMD to toggle recording")
    }

    /// Stop the application
    func stop() {
        logger.info("Stopping application")
        hotkeyMonitor.stop()
        if isRecording {
            audioRecorder?.stopRecording()
        }
        overlay.dismiss()
    }

    // MARK: - HotkeyMonitorDelegate

    func onHotkeyToggle() {
        debugLog("onHotkeyToggle called, isRecording=\(isRecording)")
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        debugLog("startRecording called")

        guard let audioRecorder = audioRecorder else {
            debugLog("ERROR: AudioRecorder not initialized")
            return
        }

        // Play start sound
        SoundPlayer.playStart()
        debugLog("Start sound played")

        // Show overlay at cursor immediately
        debugLog("Showing overlay...")
        overlay.showAtCursor()

        // Request microphone permission first (async)
        Task {
            debugLog("Requesting microphone permission...")
            let hasPermission = await audioRecorder.requestPermission()
            debugLog("Microphone permission: \(hasPermission)")

            guard hasPermission else {
                debugLog("ERROR: Microphone permission denied")
                await MainActor.run {
                    SoundPlayer.playError()
                    self.overlay.showError("Microphone permission denied")
                }
                return
            }

            await MainActor.run {
                self.doStartRecording(audioRecorder: audioRecorder)
            }
        }
    }

    private func doStartRecording(audioRecorder: AudioRecorder) {
        // Start recording
        do {
            debugLog("Calling audioRecorder.startRecording()...")
            try audioRecorder.startRecording()
            isRecording = true
            debugLog("Audio recording started successfully")

            // Start transcription streaming
            debugLog("Starting transcription streaming...")
            transcriber?.startStreaming(audioRecorder: audioRecorder)

            logger.info("Recording started")
            debugLog("Recording started - streaming to transcriber")
            print("🎤 Recording...")
        } catch {
            let errorMsg = "Failed to start recording: \(error.localizedDescription)"
            debugLog("ERROR: \(errorMsg)")
            logger.error("Failed to start recording: \(error.localizedDescription)")
            SoundPlayer.playError()
            overlay.showError(errorMsg)
            isRecording = false
        }
    }

    private func stopRecording() {
        debugLog("stopRecording called")

        guard isRecording else {
            debugLog("Not recording, ignoring stop")
            return
        }

        isRecording = false

        // Play stop sound immediately
        SoundPlayer.playStop()

        // Stop recording (this sends end-of-stream to transcriber)
        audioRecorder?.stopRecording()

        // Show processing state
        overlay.updateText("Processing...")
        debugLog("Recording stopped, waiting for final transcription")

        // Safety timeout - dismiss overlay after 30 seconds if transcription hangs
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.overlay != nil {
                debugLog("Safety timeout - dismissing overlay")
                self?.overlay.dismiss()
            }
        }
    }

    // MARK: - SpeechTranscriberDelegate

    nonisolated func onInterimResult(_ text: String) {
        Task { @MainActor in
            debugLog("AppState: Interim result received: \(text)")
            overlay.updateText(text)
        }
    }

    nonisolated func onFinalResult(_ text: String) {
        Task { @MainActor in
            debugLog("AppState: Final result received: \(text)")
            print("✓ Transcript: \(text)")
            await processAndPaste(text)
        }
    }

    nonisolated func onError(_ error: Error) {
        Task { @MainActor in
            debugLog("AppState: Transcription error: \(error.localizedDescription)")
            print("❌ Error: \(error.localizedDescription)")
            SoundPlayer.playError()
            overlay.showError(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// Process transcript and paste result
    private func processAndPaste(_ transcript: String) async {
        debugLog("AppState: Processing transcript: \(transcript.count) characters")

        var result = transcript

        // Optional Gemini post-processing
        if let prompt = config?.postProcessingPrompt, !prompt.isEmpty, let processor = postProcessor {
            debugLog("AppState: Applying Gemini post-processing")
            result = await processor.process(transcript: result, prompt: prompt)
            debugLog("AppState: Post-processing complete")
        }

        // Apply word replacements
        if let replacements = config?.replacements, !replacements.isEmpty {
            debugLog("AppState: Applying word replacements")
            result = replacer.apply(replacements: replacements, to: result)
        }

        // Dismiss overlay and paste
        debugLog("AppState: Dismissing overlay")
        overlay.dismiss()

        if !result.isEmpty {
            debugLog("AppState: Pasting \(result.count) characters: \(result)")
            paster.paste(text: result)
            print("📋 Pasted: \(result)")
        } else {
            debugLog("AppState: No text to paste")
            print("⚠️ No text to paste")
        }
    }
}
