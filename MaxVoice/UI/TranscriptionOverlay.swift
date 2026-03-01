import AppKit

/// Non-activating panel that never steals focus from the current app
private class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Floating overlay that displays live transcription near the cursor
@MainActor
final class TranscriptionOverlay {
    private var panel: OverlayPanel?
    private var textField: NSTextField?
    private var cursorTimer: Timer?

    /// Show the overlay at the current cursor position
    func showAtCursor() {
        debugLog("TranscriptionOverlay.showAtCursor called")

        // Dismiss any existing overlay first
        dismiss()

        // Create text field
        let textField = NSTextField(labelWithString: "Listening...")
        textField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.maximumNumberOfLines = 0
        textField.preferredMaxLayoutWidth = 396
        textField.lineBreakMode = .byWordWrapping
        self.textField = textField

        // Create container with dark background
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 25/255, green: 25/255, blue: 25/255, alpha: 0.9).cgColor
        container.layer?.cornerRadius = 10

        container.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        // Create panel
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = container
        self.panel = panel

        // Position at cursor BEFORE showing
        let mouseLocation = NSEvent.mouseLocation
        debugLog("TranscriptionOverlay: Mouse at \(mouseLocation)")
        positionAtCursor()

        // Show the panel
        panel.orderFrontRegardless()
        debugLog("Overlay panel shown at \(panel.frame)")

        // Start cursor-following timer
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.positionAtCursor()
            }
        }
        RunLoop.main.add(cursorTimer!, forMode: .common)
    }

    /// Update the displayed text
    func updateText(_ text: String) {
        textField?.stringValue = text.isEmpty ? "Listening..." : text
        resizeToFit()
    }

    /// Show an error message
    func showError(_ message: String) {
        textField?.stringValue = "⚠️ \(message)"
        textField?.textColor = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        resizeToFit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.dismiss()
        }
    }

    /// Dismiss the overlay
    func dismiss() {
        debugLog("TranscriptionOverlay.dismiss called")

        cursorTimer?.invalidate()
        cursorTimer = nil

        panel?.orderOut(nil)
        panel = nil
        textField = nil

        debugLog("Overlay dismissed")
    }

    /// Position the panel near the cursor
    private func positionAtCursor() {
        guard let panel = panel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        let windowSize = panel.frame.size

        var x = mouseLocation.x + 24
        var y = mouseLocation.y - windowSize.height - 24

        if x + windowSize.width > screenFrame.maxX {
            x = mouseLocation.x - windowSize.width - 24
        }
        if y < screenFrame.minY {
            y = mouseLocation.y + 24
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Resize panel to fit text content
    private func resizeToFit() {
        guard let textField = textField, let panel = panel else { return }

        textField.sizeToFit()
        let textSize = textField.fittingSize
        let newWidth = min(max(textSize.width + 24, 100), 420)
        let newHeight = max(textSize.height + 24, 44)

        var frame = panel.frame
        frame.size = NSSize(width: newWidth, height: newHeight)
        panel.setFrame(frame, display: true)
    }
}
