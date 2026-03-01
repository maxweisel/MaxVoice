import Cocoa
import os.log

/// Main application entry point
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AppDelegate")

    private var appState: AppState?
    private var permissionCheckTimer: Timer?
    private var permissionCheckAttempts = 0
    private let maxPermissionAttempts = 3

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("MaxVoice starting up")
        logger.info("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        logger.info("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")

        // Hide from dock (should also be in Info.plist)
        NSApp.setActivationPolicy(.accessory)

        // Start permission checks
        Task {
            await checkPermissionsAndStart()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("MaxVoice terminating")
        appState?.stop()
    }

    // MARK: - Permission Checking

    private func checkPermissionsAndStart() async {
        logger.info("Checking permissions")

        // Check microphone permission
        let audioRecorder = AudioRecorder()
        let micPermission = await audioRecorder.requestPermission()

        if !micPermission {
            logger.error("Microphone permission denied")
            showPermissionError("Microphone access required. Please grant permission in System Settings > Privacy & Security > Microphone.")
            return
        }

        logger.info("Microphone permission granted")

        // Check accessibility permission
        if AccessibilityChecker.hasPermission() {
            logger.info("Accessibility permission already granted")
            ConfigManager.shared.removeAccessibilityFailedMarker()
            startApp()
        } else {
            logger.warning("Accessibility permission not granted, prompting")
            AccessibilityChecker.promptForPermission()
            startPermissionPolling()
        }
    }

    /// Start polling for accessibility permission
    private func startPermissionPolling() {
        logger.info("Starting accessibility permission polling (max \(self.maxPermissionAttempts) attempts)")

        permissionCheckAttempts = 0

        // Poll every 3.3 seconds (will check 3 times over ~10 seconds)
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.3, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermission()
        }
    }

    /// Check if accessibility permission has been granted
    private func checkAccessibilityPermission() {
        permissionCheckAttempts += 1
        logger.info("Accessibility permission check attempt \(self.permissionCheckAttempts)/\(self.maxPermissionAttempts)")

        if AccessibilityChecker.hasPermission() {
            logger.info("Accessibility permission granted!")
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            ConfigManager.shared.removeAccessibilityFailedMarker()
            startApp()
        } else if permissionCheckAttempts >= maxPermissionAttempts {
            logger.error("Accessibility permission not granted after \(self.maxPermissionAttempts) attempts")
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            exitWithAccessibilityFailure()
        } else {
            logger.debug("Accessibility permission still not granted, will check again")
        }
    }

    /// Exit app due to accessibility permission failure
    private func exitWithAccessibilityFailure() {
        logger.warning("Exiting due to accessibility permission failure")

        // Create marker file so launch agent doesn't restart us
        ConfigManager.shared.createAccessibilityFailedMarker()

        // Show notification to user
        showPermissionError("Accessibility permission required. Please grant permission in System Settings > Privacy & Security > Accessibility, then restart MaxVoice.")

        // Give user time to see the notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - App Startup

    /// Start the main application
    private func startApp() {
        logger.info("Starting main application")

        appState = AppState()
        appState?.start()

        logger.info("MaxVoice is ready - hold CMD to record")
    }

    /// Show permission error to user
    private func showPermissionError(_ message: String) {
        logger.error("Permission error: \(message)")

        // Show overlay with error
        let overlay = TranscriptionOverlay()
        overlay.show(near: NSEvent.mouseLocation)
        overlay.showError(message, autoDismissAfter: 10)
        SoundPlayer.playError()
    }
}
