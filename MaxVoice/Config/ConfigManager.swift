import Foundation
import os.log

/// Manages reading and writing configuration from ~/.maxvoice/config.json
final class ConfigManager {
    static let shared = ConfigManager()

    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "ConfigManager")

    private let configDirectory: URL
    private let configPath: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appendingPathComponent(".maxvoice")
        configPath = configDirectory.appendingPathComponent("config.json")
    }

    /// Load configuration from disk
    func load() -> Config? {
        logger.info("Loading config from \(self.configPath.path)")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            logger.warning("Config file does not exist at \(self.configPath.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(Config.self, from: data)
            logger.info("Config loaded successfully - language: \(config.language), has API key: \(!config.googleApiKey.isEmpty), replacements count: \(config.replacements.count)")
            return config
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save configuration to disk
    func save(_ config: Config) -> Bool {
        logger.info("Saving config to \(self.configPath.path)")

        do {
            // Ensure directory exists
            if !FileManager.default.fileExists(atPath: configDirectory.path) {
                logger.info("Creating config directory at \(self.configDirectory.path)")
                try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)

            logger.info("Config saved successfully")
            return true
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
            return false
        }
    }

    /// Path to the accessibility failure marker file
    var accessibilityFailedMarkerPath: URL {
        configDirectory.appendingPathComponent(".accessibility_failed")
    }

    /// Check if accessibility failure marker exists
    func hasAccessibilityFailedMarker() -> Bool {
        FileManager.default.fileExists(atPath: accessibilityFailedMarkerPath.path)
    }

    /// Create accessibility failure marker
    func createAccessibilityFailedMarker() {
        logger.warning("Creating accessibility failed marker")
        do {
            try "".write(to: accessibilityFailedMarkerPath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to create accessibility marker: \(error.localizedDescription)")
        }
    }

    /// Remove accessibility failure marker
    func removeAccessibilityFailedMarker() {
        if FileManager.default.fileExists(atPath: accessibilityFailedMarkerPath.path) {
            logger.info("Removing accessibility failed marker")
            try? FileManager.default.removeItem(at: accessibilityFailedMarkerPath)
        }
    }
}
