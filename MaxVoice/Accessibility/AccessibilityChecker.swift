import Cocoa
import ApplicationServices
import os.log

/// Handles checking and requesting accessibility permissions
final class AccessibilityChecker {
    private static let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AccessibilityChecker")

    /// Check if app has accessibility permission (without prompting)
    static func hasPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility permission check: \(trusted ? "granted" : "denied")")
        return trusted
    }

    /// Prompt user for accessibility permission
    static func promptForPermission() {
        logger.info("Prompting for accessibility permission")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Check permission and prompt if needed
    /// Returns true if permission is already granted
    static func checkAndPrompt() -> Bool {
        if hasPermission() {
            logger.info("Accessibility permission already granted")
            return true
        }

        logger.info("Accessibility permission not granted, prompting user")
        promptForPermission()
        return false
    }
}
