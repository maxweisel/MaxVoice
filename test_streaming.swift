#!/usr/bin/env swift

// Test Google Cloud Speech V2 StreamingRecognize with service account auth
// This generates a simple tone and sends it to verify the full pipeline

import Foundation
import Security

let serviceAccountPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/MaxVoice/max-voice-service-account.json").path

print("Testing Google Cloud Speech V2 StreamingRecognize")
print("==================================================")

// Load service account JSON
guard let serviceAccountData = FileManager.default.contents(atPath: serviceAccountPath),
      let serviceAccount = try? JSONSerialization.jsonObject(with: serviceAccountData) as? [String: Any],
      let clientEmail = serviceAccount["client_email"] as? String,
      let privateKeyPEM = serviceAccount["private_key"] as? String,
      let tokenUri = serviceAccount["token_uri"] as? String,
      let projectId = serviceAccount["project_id"] as? String else {
    print("ERROR: Failed to load service account JSON")
    exit(1)
}

print("Project: \(projectId)")
print("Client: \(clientEmail)")

// Base64 URL encoding
extension Data {
    func base64URLEncoded() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// Sign with RSA
func signWithRSA(data: Data, privateKeyPEM: String) throws -> Data {
    let pemLines = privateKeyPEM.components(separatedBy: "\n")
    let base64Key = pemLines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }.joined()
    guard let keyData = Data(base64Encoded: base64Key) else {
        throw NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64"])
    }

    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecAttrKeySizeInBits as String: 2048,
    ]
    var error: Unmanaged<CFError>?

    // Extract RSA key from PKCS#8
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
        throw NSError(domain: "Auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create key"])
    }

    guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
        throw NSError(domain: "Auth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Signing failed"])
    }
    return signature as Data
}

// Get access token
func getAccessToken() throws -> String {
    let now = Date()
    let expiry = now.addingTimeInterval(3600)

    let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
    let claims: [String: Any] = [
        "iss": clientEmail, "sub": clientEmail, "aud": tokenUri,
        "iat": Int(now.timeIntervalSince1970), "exp": Int(expiry.timeIntervalSince1970),
        "scope": "https://www.googleapis.com/auth/cloud-platform"
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let claimsData = try JSONSerialization.data(withJSONObject: claims)
    let signatureInput = "\(headerData.base64URLEncoded()).\(claimsData.base64URLEncoded())"
    let signature = try signWithRSA(data: signatureInput.data(using: .utf8)!, privateKeyPEM: privateKeyPEM)
    let jwt = "\(signatureInput).\(signature.base64URLEncoded())"

    let semaphore = DispatchSemaphore(value: 0)
    var result: String?
    var tokenError: Error?

    var request = URLRequest(url: URL(string: tokenUri)!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)".data(using: .utf8)

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let e = error { tokenError = e; return }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            tokenError = NSError(domain: "Auth", code: 4, userInfo: [NSLocalizedDescriptionKey: "No token"])
            return
        }
        result = token
    }.resume()
    semaphore.wait()

    if let e = tokenError { throw e }
    return result!
}

// Generate silent audio (LINEAR16, 16kHz, mono) - 1 second
func generateSilentAudio() -> Data {
    var data = Data()
    // 16000 samples/sec * 2 bytes/sample = 32000 bytes for 1 second
    for _ in 0..<16000 {
        // Near-silent audio (small values to avoid "no audio" detection)
        let sample: Int16 = Int16.random(in: -10...10)
        withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
    }
    return data
}

// Test StreamingRecognize via REST (simpler than gRPC for testing)
func testRecognize(token: String) throws {
    print("\nTesting Recognize API (batch, not streaming)...")

    let audio = generateSilentAudio()
    print("Generated \(audio.count) bytes of test audio")

    let requestBody: [String: Any] = [
        "config": [
            "explicitDecodingConfig": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 16000,
                "audioChannelCount": 1
            ],
            "languageCodes": ["en-US"],
            "model": "chirp_2",
            "features": [
                "enableAutomaticPunctuation": true
            ]
        ],
        "content": audio.base64EncodedString()
    ]

    // Test us-central1 (Iowa)
    let location = "us-central1"
    let url = URL(string: "https://\(location)-speech.googleapis.com/v2/projects/\(projectId)/locations/\(location)/recognizers/_:recognize")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let semaphore = DispatchSemaphore(value: 0)
    var success = false
    var responseBody = ""

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }

        if let e = error {
            print("Request error: \(e.localizedDescription)")
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response")
            return
        }

        responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
        print("Status: \(httpResponse.statusCode)")
        print("Response: \(responseBody.prefix(500))")

        // 200 = success, empty results is fine for silent audio
        success = httpResponse.statusCode == 200
    }.resume()

    semaphore.wait()

    if success {
        print("\n✅ SUCCESS: Speech V2 API with Chirp model is working!")
        print("The API accepted the request and processed it correctly.")
        print("(Empty results are expected for silent/random audio)")
    } else {
        print("\n❌ FAILED: API call failed")
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: responseBody])
    }
}

// Main
do {
    print("\nGetting access token...")
    let token = try getAccessToken()
    print("Got token: \(token.prefix(50))...")

    try testRecognize(token: token)

} catch {
    print("\nERROR: \(error.localizedDescription)")
    exit(1)
}
