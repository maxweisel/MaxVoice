import Cocoa
import os.log

/// Protocol for hotkey events
protocol HotkeyMonitorDelegate: AnyObject {
    func onHotkeyPressed()
    func onHotkeyReleased()
}

/// Monitors for CMD key press/release using NSEvent global monitor
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
        stop()
    }

    /// Start monitoring for hotkey events
    func start() {
        guard !isMonitoring else {
            logger.warning("Already monitoring, ignoring start request")
            return
        }

        logger.info("Starting hotkey monitoring for CMD key")

        // Global monitor for events when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor for events when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        isMonitoring = true
        logger.info("Hotkey monitoring started")
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

        // Detect transitions
        if cmdPressed && !isCommandPressed {
            // CMD key pressed
            logger.info("CMD key pressed")
            isCommandPressed = true
            delegate?.onHotkeyPressed()
        } else if !cmdPressed && isCommandPressed {
            // CMD key released
            logger.info("CMD key released")
            isCommandPressed = false
            delegate?.onHotkeyReleased()
        }
    }

    /// Check if currently monitoring
    var monitoring: Bool {
        return isMonitoring
    }
}
