import Cocoa
import os.log

/// Protocol for hotkey events
@MainActor
protocol HotkeyMonitorDelegate: AnyObject {
    func onHotkeyToggle()
}

/// Monitors for CMD key press using NSEvent global monitor (toggle mode)
@MainActor
final class HotkeyMonitor {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "HotkeyMonitor")

    weak var delegate: HotkeyMonitorDelegate?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCommandPressed = false
    private var isMonitoring = false

    init() {
        logger.info("HotkeyMonitor initialized")
    }

    deinit {
        // Note: stop() must be called explicitly before deinit since we're @MainActor
    }

    /// Start monitoring for hotkey events
    func start() {
        guard !isMonitoring else {
            logger.warning("Already monitoring, ignoring start request")
            return
        }

        logger.info("Starting hotkey monitoring for CMD key (toggle mode)")

        // Global monitor for events when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        // Local monitor for events when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }

        // Verify monitors were created
        if globalMonitor != nil {
            isMonitoring = true
            debugLog("Hotkey monitoring active - globalMonitor created")
        } else {
            debugLog("ERROR: Failed to create event monitor - check Accessibility permissions")
        }
    }

    /// Stop monitoring for hotkey events
    func stop() {
        guard isMonitoring else { return }

        logger.info("Stopping hotkey monitoring")

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        isMonitoring = false
        isCommandPressed = false
        logger.info("Hotkey monitoring stopped")
    }

    /// Handle modifier key changes
    private func handleFlagsChanged(_ event: NSEvent) {
        let cmdPressed = event.modifierFlags.contains(.command)
        debugLog("handleFlagsChanged: cmdPressed=\(cmdPressed) isCommandPressed=\(isCommandPressed)")

        // Only fire on press transition (toggle mode - ignore release)
        if cmdPressed && !isCommandPressed {
            // CMD key pressed - fire toggle
            debugLog("CMD key pressed - toggling")
            isCommandPressed = true
            delegate?.onHotkeyToggle()
        } else if !cmdPressed && isCommandPressed {
            // CMD key released - just update state, don't fire callback
            debugLog("CMD key released")
            isCommandPressed = false
        }
    }

    /// Check if currently monitoring
    var monitoring: Bool {
        return isMonitoring
    }
}
