import Foundation

/// Configuration structure matching ~/.maxvoice/config.json
struct Config: Codable {
    var googleApiKey: String
    var language: String
    var postProcessingPrompt: String?
    var replacements: [[String]]

    init(googleApiKey: String = "", language: String = "en-US", postProcessingPrompt: String? = nil, replacements: [[String]] = []) {
        self.googleApiKey = googleApiKey
        self.language = language
        self.postProcessingPrompt = postProcessingPrompt
        self.replacements = replacements
    }
}
