import Cocoa
import os.log

/// Plays system sounds for audio feedback
final class SoundPlayer {
    private static let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "SoundPlayer")

    /// Sound played when recording starts
    static let startSound: NSSound? = {
        let path = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/Text-Message-Acknowledgement-ThumbsUp.caf"
        let sound = NSSound(contentsOfFile: path, byReference: true)
        if sound == nil {
            logger.warning("Failed to load start sound from: \(path)")
        } else {
            logger.debug("Start sound loaded")
        }
        return sound
    }()

    /// Sound played when recording stops
    static let stopSound: NSSound? = {
        let path = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones/Text-Message-Acknowledgement-ThumbsDown.caf"
        let sound = NSSound(contentsOfFile: path, byReference: true)
        if sound == nil {
            logger.warning("Failed to load stop sound from: \(path)")
        } else {
            logger.debug("Stop sound loaded")
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
