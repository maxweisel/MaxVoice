import Cocoa
import SwiftUI
import os.log

/// Floating overlay window that displays live transcription near the cursor
final class TranscriptionOverlay {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "TranscriptionOverlay")

    private var window: NSWindow?
    private let state = OverlayState()

    /// Offset from cursor position
    private let cursorOffset: CGFloat = 24

    /// Auto-hide timer for error messages
    private var hideTimer: Timer?

    init() {
        logger.info("TranscriptionOverlay initialized")
    }

    /// Show the overlay near the given point
    func show(near point: NSPoint) {
        logger.info("Showing overlay near point: \(point.x), \(point.y)")

        hideTimer?.invalidate()
        hideTimer = nil

        // Create window if needed
        if window == nil {
            createWindow()
        }

        // Position window near cursor
        updatePosition(near: point)

        // Show window
        window?.orderFrontRegardless()
        window?.setIsVisible(true)

        logger.info("Overlay window shown")
    }

    /// Hide the overlay
    func hide() {
        logger.info("Hiding overlay")
        hideTimer?.invalidate()
        hideTimer = nil

        window?.setIsVisible(false)
    }

    /// Update overlay position to follow cursor
    func updatePosition(near point: NSPoint) {
        guard let window = window else { return }

        // Calculate position (offset below and to the right of cursor)
        let windowSize = window.frame.size
        var newOrigin = point

        // Offset from cursor
        newOrigin.x += cursorOffset
        newOrigin.y -= windowSize.height + cursorOffset

        // Keep on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Don't go off right edge
            if newOrigin.x + windowSize.width > screenFrame.maxX {
                newOrigin.x = point.x - windowSize.width - cursorOffset
            }

            // Don't go off bottom
            if newOrigin.y < screenFrame.minY {
                newOrigin.y = point.y + cursorOffset
            }

            // Don't go off left edge
            if newOrigin.x < screenFrame.minX {
                newOrigin.x = screenFrame.minX
            }

            // Don't go off top
            if newOrigin.y + windowSize.height > screenFrame.maxY {
                newOrigin.y = screenFrame.maxY - windowSize.height
            }
        }

        window.setFrameOrigin(newOrigin)
    }

    /// Create the overlay window
    private func createWindow() {
        logger.debug("Creating overlay window")

        let contentView = NSHostingView(rootView: OverlayContent(state: state))
        contentView.setFrameSize(contentView.fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = contentView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Don't show in mission control or app switcher
        window.collectionBehavior.insert(.transient)

        self.window = window
        logger.debug("Overlay window created")
    }

    /// Update the window size based on content
    private func updateWindowSize() {
        guard let window = window,
              let contentView = window.contentView as? NSHostingView<OverlayContent> else { return }

        let newSize = contentView.fittingSize
        var frame = window.frame
        frame.size = newSize
        window.setFrame(frame, display: true)
    }

    // MARK: - State Management

    /// Set state to listening
    func setListening() {
        state.setListening()
        updateWindowSize()
    }

    /// Set state to transcribing
    func setTranscribing() {
        state.setTranscribing()
    }

    /// Update the displayed transcript
    func updateTranscript(_ text: String) {
        state.updateTranscript(text)
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowSize()
        }
    }

    /// Set state to processing
    func setProcessing() {
        state.setProcessing()
        updateWindowSize()
    }

    /// Show error message
    func showError(_ message: String, autoDismissAfter seconds: TimeInterval = 4.0) {
        state.setError(message)
        updateWindowSize()

        // Auto-dismiss after delay
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}
