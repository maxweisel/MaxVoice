import Foundation
import os.log

/// Applies regex-based word replacements to text
final class TextReplacer {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "TextReplacer")

    init() {
        logger.info("TextReplacer initialized")
    }

    /// Apply word replacements to text
    /// - Parameters:
    ///   - replacements: Array of [find, replace] pairs
    ///   - text: The text to transform
    /// - Returns: Text with replacements applied
    func apply(replacements: [[String]], to text: String) -> String {
        guard !replacements.isEmpty else {
            logger.debug("No replacements to apply")
            return text
        }

        logger.info("Applying \(replacements.count) replacement rules")

        var result = text
        var appliedCount = 0

        for pair in replacements {
            guard pair.count == 2 else {
                logger.warning("Invalid replacement pair (expected 2 elements, got \(pair.count)): \(pair)")
                continue
            }

            let find = pair[0]
            let replace = pair[1]

            // Create word boundary regex for case-insensitive matching
            let escapedPattern = NSRegularExpression.escapedPattern(for: find)
            let pattern = "\\b" + escapedPattern + "\\b"

            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(result.startIndex..., in: result)

                let matchCount = regex.numberOfMatches(in: result, range: range)
                if matchCount > 0 {
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replace)
                    appliedCount += matchCount
                    logger.debug("Replaced '\(find)' with '\(replace)' (\(matchCount) occurrences)")
                }
            } catch {
                logger.error("Invalid regex pattern for '\(find)': \(error.localizedDescription)")
            }
        }

        if appliedCount > 0 {
            logger.info("Applied \(appliedCount) total replacements")
        }

        return result
    }
}
