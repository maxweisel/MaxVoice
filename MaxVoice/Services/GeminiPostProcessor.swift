import Foundation
import os.log

/// Post-processes transcripts using Gemini AI
final class GeminiPostProcessor {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "GeminiPostProcessor")

    private let apiKey: String
    private let model = "gemini-2.0-flash"

    init(apiKey: String) {
        self.apiKey = apiKey
        logger.info("GeminiPostProcessor initialized with model: \(self.model)")
    }

    /// Process transcript with custom prompt
    /// - Parameters:
    ///   - transcript: The raw transcript
    ///   - prompt: User-defined processing prompt
    /// - Returns: Processed text, or original transcript if processing fails
    func process(transcript: String, prompt: String) async -> String {
        logger.info("Processing transcript (\(transcript.count) chars) with prompt (\(prompt.count) chars)")

        guard !apiKey.isEmpty else {
            logger.error("API key is empty, returning original transcript")
            return transcript
        }

        let fullPrompt = """
        \(prompt)

        Transcript:
        \(transcript)

        Respond ONLY with the processed text, nothing else.
        """

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            logger.error("Failed to create API URL")
            return transcript
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to serialize request body: \(error.localizedDescription)")
            return transcript
        }

        logger.debug("Sending request to Gemini API")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                return transcript
            }

            logger.debug("Gemini API response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                if let errorBody = String(data: data, encoding: .utf8) {
                    logger.error("Gemini API error (\(httpResponse.statusCode)): \(errorBody)")
                }
                return transcript
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                logger.error("Failed to parse Gemini response")
                if let responseString = String(data: data, encoding: .utf8) {
                    logger.debug("Raw response: \(responseString)")
                }
                return transcript
            }

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Gemini processing complete, result: \(trimmedText.count) chars")

            return trimmedText

        } catch {
            logger.error("Gemini API request failed: \(error.localizedDescription)")
            return transcript
        }
    }
}
