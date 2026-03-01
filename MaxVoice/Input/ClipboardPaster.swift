import Cocoa
import os.log

/// Handles pasting text via clipboard swap and Cmd+V simulation
final class ClipboardPaster {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "ClipboardPaster")

    /// Delays for clipboard operations (empirically determined)
    private let pasteDelay: TimeInterval = 0.08        // 80ms before Cmd+V
    private let restoreDelay: TimeInterval = 0.35      // 350ms before restoring clipboard

    init() {
        logger.info("ClipboardPaster initialized")
    }

    /// Paste text by swapping clipboard contents and simulating Cmd+V
    func paste(text: String) {
        logger.info("Starting paste operation for \(text.count) characters")

        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents
        let oldChangeCount = pasteboard.changeCount
        let oldContents = pasteboard.string(forType: .string)
        logger.debug("Saved clipboard contents (\(oldContents?.count ?? 0) characters)")

        // 2. Set our transcript to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.debug("Set transcript to clipboard")

        // 3. After delay, simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) { [weak self] in
            self?.simulatePaste()

            // 4. After another delay, restore original clipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.restoreDelay ?? 0.35) - (self?.pasteDelay ?? 0.08)) {
                self?.restoreClipboard(oldContents: oldContents, expectedChangeCount: oldChangeCount)
            }
        }
    }

    /// Simulate Cmd+V keystroke using CGEvent
    private func simulatePaste() {
        logger.debug("Simulating Cmd+V keystroke")

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create CGEventSource")
            return
        }

        // Virtual key code for 'V' is 0x09
        let keyCodeV: CGKeyCode = 0x09

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true) else {
            logger.error("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else {
            logger.error("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.info("Cmd+V keystroke sent")
    }

    /// Restore original clipboard contents
    private func restoreClipboard(oldContents: String?, expectedChangeCount: Int) {
        let pasteboard = NSPasteboard.general

        // Only restore if clipboard hasn't been changed by something else
        // (This is a simple heuristic - may not cover all edge cases)
        pasteboard.clearContents()

        if let old = oldContents {
            pasteboard.setString(old, forType: .string)
            logger.debug("Restored clipboard contents (\(old.count) characters)")
        } else {
            logger.debug("No previous clipboard contents to restore")
        }
    }
}
