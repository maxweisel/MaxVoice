import Cocoa
import os.log

/// Plays system sounds for audio feedback
final class SoundPlayer {
    private static let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "SoundPlayer")

    /// Sound played when recording starts
    static let startSound: NSSound? = {
        guard let url = Bundle.module.url(forResource: "start", withExtension: "caf") else {
            logger.warning("Failed to find start.caf in bundle")
            return nil
        }
        let sound = NSSound(contentsOf: url, byReference: false)
        if sound == nil {
            logger.warning("Failed to load start sound from bundle")
        } else {
            logger.debug("Start sound loaded from bundle")
        }
        return sound
    }()

    /// Sound played when recording stops
    static let stopSound: NSSound? = {
        guard let url = Bundle.module.url(forResource: "stop", withExtension: "caf") else {
            logger.warning("Failed to find stop.caf in bundle")
            return nil
        }
        let sound = NSSound(contentsOf: url, byReference: false)
        if sound == nil {
            logger.warning("Failed to load stop sound from bundle")
        } else {
            logger.debug("Stop sound loaded from bundle")
        }
        return sound
    }()

    /// Sound played on error
    static let errorSound: NSSound? = {
        let sound = NSSound(named: "Basso")
        if sound == nil {
            logger.warning("Failed to load error sound 'Basso'")
        } else {
            logger.debug("Error sound loaded")
        }
        return sound
    }()

    /// Play the start recording sound
    static func playStart() {
        logger.debug("Playing start sound")
        startSound?.play()
    }

    /// Play the stop recording sound
    static func playStop() {
        logger.debug("Playing stop sound")
        stopSound?.play()
    }

    /// Play the error sound
    static func playError() {
        logger.debug("Playing error sound")
        errorSound?.play()
    }
}
