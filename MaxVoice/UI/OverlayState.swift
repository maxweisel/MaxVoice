import SwiftUI
import os.log

/// State for the transcription overlay
final class OverlayState: ObservableObject {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "OverlayState")

    enum State {
        case listening
        case transcribing
        case processing
        case error
    }

    @Published var currentState: State = .listening
    @Published var transcriptText: String = ""
    @Published var errorMessage: String = ""

    /// Braille spinner characters for processing state
    private let spinnerChars = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
    private var spinnerIndex = 0
    private var spinnerTimer: Timer?

    init() {
        logger.info("OverlayState initialized")
    }

    deinit {
        stopSpinner()
    }

    /// Text to display based on current state
    var displayText: String {
        switch currentState {
        case .listening:
            return transcriptText.isEmpty ? "Listening…" : transcriptText
        case .transcribing:
            return transcriptText.isEmpty ? "Listening…" : transcriptText
        case .processing:
            return transcriptText + " " + spinnerChars[spinnerIndex]
        case .error:
            return "⚠ " + errorMessage
        }
    }

    /// Text color based on current state
    var textColor: Color {
        switch currentState {
        case .listening, .transcribing:
            return .white
        case .processing:
            return Color.white.opacity(0.8)
        case .error:
            return Color(red: 1.0, green: 0.42, blue: 0.42)  // #FF6B6B
        }
    }

    /// Update transcript text
    func updateTranscript(_ text: String) {
        logger.debug("Updating transcript: \(text.prefix(50))...")
        DispatchQueue.main.async {
            self.transcriptText = text
        }
    }

    /// Set state to listening
    func setListening() {
        logger.info("State -> listening")
        DispatchQueue.main.async {
            self.currentState = .listening
            self.transcriptText = ""
            self.errorMessage = ""
            self.stopSpinner()
        }
    }

    /// Set state to transcribing
    func setTranscribing() {
        logger.info("State -> transcribing")
        DispatchQueue.main.async {
            self.currentState = .transcribing
        }
    }

    /// Set state to processing
    func setProcessing() {
        logger.info("State -> processing")
        DispatchQueue.main.async {
            self.currentState = .processing
            self.startSpinner()
        }
    }

    /// Set state to error
    func setError(_ message: String) {
        logger.error("State -> error: \(message)")
        DispatchQueue.main.async {
            self.currentState = .error
            self.errorMessage = message
            self.stopSpinner()
        }
    }

    /// Start the spinner animation
    private func startSpinner() {
        stopSpinner()
        spinnerIndex = 0

        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.spinnerIndex = (self.spinnerIndex + 1) % self.spinnerChars.count
            self.objectWillChange.send()
        }
    }

    /// Stop the spinner animation
    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
    }
}
