import Foundation
import GRPC
import NIOCore
import NIOPosix
import Security

/// Handles true bidirectional gRPC streaming transcription using Google Cloud Speech-to-Text V2 API with Chirp
final class GRPCStreamingTranscriber: @unchecked Sendable {

    weak var delegate: SpeechTranscriberDelegate?

    private let language: String
    private let projectId = "claude-code-voice-assistant"
    private let serviceAccountPath: String

    private var group: EventLoopGroup?
    private var channel: GRPCChannel?
    private var client: Google_Cloud_Speech_V2_SpeechAsyncClient?
    private var stream: GRPCAsyncBidirectionalStreamingCall<
        Google_Cloud_Speech_V2_StreamingRecognizeRequest,
        Google_Cloud_Speech_V2_StreamingRecognizeResponse
    >?

    private var isStreaming = false
    private var streamTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?

    private var cachedAccessToken: String?
    private var tokenExpiry: Date?

    init(apiKey: String, language: String = "en-US") {
        self.language = language
        // Look for service account JSON in project directory
        self.serviceAccountPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MaxVoice/max-voice-service-account.json").path
        debugLog("GRPCStreamingTranscriber: Initialized with language: \(language), project: \(projectId)")
        debugLog("GRPCStreamingTranscriber: Using service account: \(serviceAccountPath)")
    }

    deinit {
        try? channel?.close().wait()
        try? group?.syncShutdownGracefully()
    }

    /// Start streaming transcription
    func startStreaming(audioRecorder: AudioRecorder) {
        guard !isStreaming else {
            debugLog("GRPCStreamingTranscriber: Already streaming")
            return
        }

        isStreaming = true
        debugLog("GRPCStreamingTranscriber: Starting streaming session")

        streamTask = Task { [weak self] in
            await self?.runStreamingSession(audioRecorder: audioRecorder)
        }
    }

    /// Stop streaming
    func stopStreaming() {
        guard isStreaming else { return }
        debugLog("GRPCStreamingTranscriber: Stopping streaming")
        isStreaming = false
        streamTask?.cancel()
        responseTask?.cancel()
    }

    /// Run the streaming session
    private func runStreamingSession(audioRecorder: AudioRecorder) async {
        do {
            // Set up gRPC channel
            try await setupChannel()

            guard let client = client else {
                debugLog("GRPCStreamingTranscriber: ERROR - Client not initialized")
                return
            }

            // Get access token from service account
            let accessToken = try await getAccessToken()
            debugLog("GRPCStreamingTranscriber: Got access token")

            // Create call options with Bearer token
            var callOptions = CallOptions()
            callOptions.customMetadata.add(name: "authorization", value: "Bearer \(accessToken)")

            // Create bidirectional stream
            let stream = client.makeStreamingRecognizeCall(callOptions: callOptions)
            self.stream = stream

            debugLog("GRPCStreamingTranscriber: Stream created")

            // Start response handler task
            responseTask = Task { [weak self] in
                await self?.handleResponses(stream: stream)
            }

            // Send initial config request
            var configRequest = Google_Cloud_Speech_V2_StreamingRecognizeRequest()
            // Chirp 3 - northamerica-northeast1 (Montreal) is closest to NYC
            configRequest.recognizer = "projects/\(projectId)/locations/northamerica-northeast1/recognizers/_"
            debugLog("GRPCStreamingTranscriber: Using recognizer: \(configRequest.recognizer)")

            var streamingConfig = Google_Cloud_Speech_V2_StreamingRecognitionConfig()

            var recognitionConfig = Google_Cloud_Speech_V2_RecognitionConfig()
            recognitionConfig.languageCodes = [language]
            recognitionConfig.model = "chirp_3"

            var features = Google_Cloud_Speech_V2_RecognitionFeatures()
            features.enableAutomaticPunctuation = true
            recognitionConfig.features = features

            var explicitConfig = Google_Cloud_Speech_V2_ExplicitDecodingConfig()
            explicitConfig.encoding = .linear16
            explicitConfig.sampleRateHertz = 16000
            explicitConfig.audioChannelCount = 1
            recognitionConfig.explicitDecodingConfig = explicitConfig

            streamingConfig.config = recognitionConfig
            streamingConfig.streamingFeatures.interimResults = true

            configRequest.streamingConfig = streamingConfig

            try await stream.requestStream.send(configRequest)
            debugLog("GRPCStreamingTranscriber: Sent config - model: \(recognitionConfig.model), language: \(recognitionConfig.languageCodes)")

            // Stream audio chunks
            var chunkCount = 0
            while let chunk = audioRecorder.getNextChunk() {
                guard isStreaming else { break }

                var audioRequest = Google_Cloud_Speech_V2_StreamingRecognizeRequest()
                audioRequest.audio = chunk

                try await stream.requestStream.send(audioRequest)
                chunkCount += 1

                if chunkCount == 1 {
                    debugLog("GRPCStreamingTranscriber: Sent first audio chunk (\(chunk.count) bytes)")
                }
            }

            debugLog("GRPCStreamingTranscriber: Finished sending \(chunkCount) audio chunks")

            // Close the request stream
            stream.requestStream.finish()

            // Wait for responses to complete
            await responseTask?.value

        } catch {
            debugLog("GRPCStreamingTranscriber: ERROR - \(error)")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(error)
            }
        }

        isStreaming = false
        debugLog("GRPCStreamingTranscriber: Session ended")
    }

    /// Handle streaming responses
    private func handleResponses(stream: GRPCAsyncBidirectionalStreamingCall<
        Google_Cloud_Speech_V2_StreamingRecognizeRequest,
        Google_Cloud_Speech_V2_StreamingRecognizeResponse
    >) async {
        var finalTranscript = ""

        do {
            for try await response in stream.responseStream {
                for result in response.results {
                    guard let alternative = result.alternatives.first else { continue }

                    let transcript = alternative.transcript

                    if result.isFinal {
                        finalTranscript += transcript
                        debugLog("GRPCStreamingTranscriber: Final result: \(transcript)")
                    } else {
                        debugLog("GRPCStreamingTranscriber: Interim result: \(transcript)")
                        await MainActor.run { [weak self] in
                            self?.delegate?.onInterimResult(transcript)
                        }
                    }
                }
            }

            // Send final result
            if !finalTranscript.isEmpty {
                let result = finalTranscript
                debugLog("GRPCStreamingTranscriber: Complete transcript: \(result)")
                await MainActor.run { [weak self] in
                    self?.delegate?.onFinalResult(result)
                }
            }

        } catch {
            debugLog("GRPCStreamingTranscriber: Response error - \(error)")
            await MainActor.run { [weak self] in
                self?.delegate?.onError(error)
            }
        }
    }

    /// Set up the gRPC channel
    private func setupChannel() async throws {
        if channel != nil { return }

        debugLog("GRPCStreamingTranscriber: Setting up gRPC channel")

        group = PlatformSupport.makeEventLoopGroup(loopCount: 1)

        guard let group = group else {
            throw GRPCError.setupFailed
        }

        // Chirp 3 - northamerica-northeast1 (Montreal) endpoint
        channel = try GRPCChannelPool.with(
            target: .host("northamerica-northeast1-speech.googleapis.com", port: 443),
            transportSecurity: .tls(GRPCTLSConfiguration.makeClientDefault(compatibleWith: group)),
            eventLoopGroup: group
        )

        guard let channel = channel else {
            throw GRPCError.setupFailed
        }

        client = Google_Cloud_Speech_V2_SpeechAsyncClient(channel: channel)

        debugLog("GRPCStreamingTranscriber: Channel established")
    }

    // MARK: - Service Account Authentication

    /// Get access token from service account
    private func getAccessToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = cachedAccessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        // Load service account JSON
        let serviceAccountData = try Data(contentsOf: URL(fileURLWithPath: serviceAccountPath))
        guard let serviceAccount = try JSONSerialization.jsonObject(with: serviceAccountData) as? [String: Any],
              let clientEmail = serviceAccount["client_email"] as? String,
              let privateKeyPEM = serviceAccount["private_key"] as? String,
              let tokenUri = serviceAccount["token_uri"] as? String else {
            throw GRPCError.authFailed("Invalid service account JSON")
        }

        debugLog("GRPCStreamingTranscriber: Authenticating as \(clientEmail)")

        // Create JWT
        let now = Date()
        let expiry = now.addingTimeInterval(3600) // 1 hour

        let header = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": clientEmail,
            "sub": clientEmail,
            "aud": tokenUri,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970),
            "scope": "https://www.googleapis.com/auth/cloud-platform"
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let claimsData = try JSONSerialization.data(withJSONObject: claims)

        let headerB64 = headerData.base64URLEncoded()
        let claimsB64 = claimsData.base64URLEncoded()
        let signatureInput = "\(headerB64).\(claimsB64)"

        // Sign JWT with private key
        let signature = try signWithRSA(data: signatureInput.data(using: .utf8)!, privateKeyPEM: privateKeyPEM)
        let signatureB64 = signature.base64URLEncoded()

        let jwt = "\(signatureInput).\(signatureB64)"

        // Exchange JWT for access token
        let token = try await exchangeJWTForToken(jwt: jwt, tokenUri: tokenUri)

        // Cache the token
        cachedAccessToken = token
        tokenExpiry = expiry.addingTimeInterval(-60) // Expire 1 minute early

        return token
    }

    /// Sign data with RSA private key (handles PKCS#8 format from Google service accounts)
    private func signWithRSA(data: Data, privateKeyPEM: String) throws -> Data {
        // Extract the base64 key from PEM format
        let pemLines = privateKeyPEM.components(separatedBy: "\n")
        let base64Key = pemLines
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()

        guard let keyData = Data(base64Encoded: base64Key) else {
            throw GRPCError.authFailed("Invalid private key format")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        var error: Unmanaged<CFError>?

        // Try direct PKCS#8 first
        if let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            guard let signature = SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                data as CFData,
                &error
            ) else {
                throw GRPCError.authFailed("Signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            }
            return signature as Data
        }

        // PKCS#8 format: extract the inner RSA key
        // Look for OCTET STRING (0x04 0x82) containing the actual RSA key
        var rsaKeyData: Data?
        for i in 0..<min(50, keyData.count - 4) {
            if keyData[i] == 0x04 && keyData[i+1] == 0x82 {
                let length = Int(keyData[i+2]) << 8 | Int(keyData[i+3])
                if i + 4 + length <= keyData.count {
                    rsaKeyData = keyData.subdata(in: (i+4)..<(i+4+length))
                    break
                }
            }
        }

        guard let rsaData = rsaKeyData,
              let privateKey = SecKeyCreateWithData(rsaData as CFData, attributes as CFDictionary, &error) else {
            throw GRPCError.authFailed("Failed to create private key from PKCS#8")
        }

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw GRPCError.authFailed("Signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        return signature as Data
    }

    /// Exchange JWT for access token
    private func exchangeJWTForToken(jwt: String, tokenUri: String) async throws -> String {
        guard let url = URL(string: tokenUri) else {
            throw GRPCError.authFailed("Invalid token URI")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GRPCError.authFailed("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw GRPCError.authFailed("Token exchange failed (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw GRPCError.authFailed("No access_token in response")
        }

        return accessToken
    }

    var streaming: Bool {
        return isStreaming
    }
}

enum GRPCError: Error, LocalizedError {
    case setupFailed
    case streamFailed
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .setupFailed: return "Failed to setup gRPC channel"
        case .streamFailed: return "Streaming failed"
        case .authFailed(let msg): return "Authentication failed: \(msg)"
        }
    }
}

// MARK: - Base64 URL Encoding

extension Data {
    func base64URLEncoded() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
