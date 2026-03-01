import Foundation

/// Debug logging to file and NSLog
func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logLine = "[\(timestamp)] \(message)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".maxvoice/debug.log")

    if let data = logLine.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath.path) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logPath)
        }
    }
    NSLog("MaxVoice: %@", message)
}
