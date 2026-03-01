import SwiftUI
import AppKit
import ApplicationServices

@main
struct MaxVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching called")

        // Request accessibility permission - shows system prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        debugLog("Accessibility enabled = \(accessibilityEnabled)")

        if !accessibilityEnabled {
            debugLog("Waiting for accessibility permission...")
            let appPath = Bundle.main.bundleURL.path
            schedulePermissionCheck(appPath: appPath)
            return
        }

        debugLog("Accessibility OK, starting app")
        ConfigManager.shared.removeAccessibilityFailedMarker()
        startApp()
    }

    private func schedulePermissionCheck(appPath: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if AXIsProcessTrusted() {
                debugLog("Permission granted, restarting...")
                Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", appPath])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            } else {
                debugLog("Still waiting...")
                self?.schedulePermissionCheck(appPath: appPath)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("Terminating")
        appState?.stop()
    }

    private func startApp() {
        debugLog("startApp called")

        guard let config = ConfigManager.shared.load() else {
            debugLog("Failed to load config")
            showError("Config Error", "Could not load ~/.maxvoice/config.json")
            return
        }

        guard !config.googleApiKey.isEmpty else {
            debugLog("API key is empty")
            showError("API Key Missing", "Add googleApiKey to ~/.maxvoice/config.json")
            return
        }

        debugLog("Config loaded, initializing AppState")
        appState = AppState()
        appState?.start()
        debugLog("Ready - press CMD to toggle recording")
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
