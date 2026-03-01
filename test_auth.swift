#!/usr/bin/env swift

import Foundation
import Security

// Simple test script to verify Google Cloud Speech V2 authentication

let serviceAccountPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/MaxVoice/max-voice-service-account.json").path

print("Testing Google Cloud Speech V2 Authentication")
print("==============================================")
print("Service account: \(serviceAccountPath)")

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

print("Client email: \(clientEmail)")
print("Project ID: \(projectId)")
print("Token URI: \(tokenUri)")

// Base64 URL encoding
extension Data {
    func base64URLEncoded() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// Sign with RSA - need to handle PKCS#8 format
func signWithRSA(data: Data, privateKeyPEM: String) throws -> Data {
    // Extract the base64 key from PEM format
    let pemLines = privateKeyPEM.components(separatedBy: "\n")
    let base64Key = pemLines
        .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        .joined()

    guard let keyData = Data(base64Encoded: base64Key) else {
        throw NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 in private key"])
    }

    print("Key data size: \(keyData.count) bytes")

    // The key is in PKCS#8 format, we need to convert it
    // PKCS#8 has a header we need to skip to get the raw RSA key
    // Try creating the key directly first

    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecAttrKeySizeInBits as String: 2048,
    ]

    var error: Unmanaged<CFError>?

    // First try: direct PKCS#8
    if let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
        print("Created key directly from PKCS#8")
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw NSError(domain: "Auth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")"])
        }
        return signature as Data
    }

    print("Direct PKCS#8 failed, trying to extract RSA key...")

    // PKCS#8 format: SEQUENCE { SEQUENCE { OID, NULL }, OCTET STRING { RSA key } }
    // The RSA private key starts after the PKCS#8 header (typically 26 bytes for RSA)
    // Look for the inner OCTET STRING containing the actual RSA key

    // Skip PKCS#8 header - find 0x04 0x82 pattern (OCTET STRING with 2-byte length)
    var rsaKeyData: Data?
    for i in 0..<min(50, keyData.count - 4) {
        if keyData[i] == 0x04 && keyData[i+1] == 0x82 {
            let length = Int(keyData[i+2]) << 8 | Int(keyData[i+3])
            if i + 4 + length <= keyData.count {
                rsaKeyData = keyData.subdata(in: (i+4)..<(i+4+length))
                print("Found RSA key at offset \(i), length \(length)")
                break
            }
        }
    }

    if let rsaData = rsaKeyData {
        if let privateKey = SecKeyCreateWithData(rsaData as CFData, attributes as CFDictionary, &error) {
            print("Created key from extracted RSA data")
            guard let signature = SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                data as CFData,
                &error
            ) else {
                throw NSError(domain: "Auth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Signing failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")"])
            }
            return signature as Data
        }
    }

    // Try using SecItemAdd to import the key
    print("Trying keychain import method...")

    let importAttributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecReturnRef as String: true,
    ]

    var item: CFTypeRef?
    let importStatus = SecItemAdd([
        kSecClass as String: kSecClassKey,
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecValueData as String: keyData,
        kSecReturnRef as String: true,
    ] as CFDictionary, &item)

    if importStatus == errSecSuccess || importStatus == errSecDuplicateItem {
        print("Keychain import succeeded")
    }

    throw NSError(domain: "Auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create private key from any format"])
}

// Create JWT
print("\nCreating JWT...")
let now = Date()
let expiry = now.addingTimeInterval(3600)

let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
let claims: [String: Any] = [
    "iss": clientEmail,
    "sub": clientEmail,
    "aud": tokenUri,
    "iat": Int(now.timeIntervalSince1970),
    "exp": Int(expiry.timeIntervalSince1970),
    "scope": "https://www.googleapis.com/auth/cloud-platform"
]

do {
    let headerData = try JSONSerialization.data(withJSONObject: header)
    let claimsData = try JSONSerialization.data(withJSONObject: claims)

    let headerB64 = headerData.base64URLEncoded()
    let claimsB64 = claimsData.base64URLEncoded()
    let signatureInput = "\(headerB64).\(claimsB64)"

    print("Signing JWT...")
    let signature = try signWithRSA(data: signatureInput.data(using: .utf8)!, privateKeyPEM: privateKeyPEM)
    let signatureB64 = signature.base64URLEncoded()

    let jwt = "\(signatureInput).\(signatureB64)"
    print("JWT created successfully (length: \(jwt.count))")

    // Exchange JWT for access token
    print("\nExchanging JWT for access token...")

    let semaphore = DispatchSemaphore(value: 0)
    var accessToken: String?
    var tokenError: Error?

    var request = URLRequest(url: URL(string: tokenUri)!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)".data(using: .utf8)

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }

        if let error = error {
            tokenError = error
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            tokenError = NSError(domain: "Auth", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            return
        }

        guard let data = data else {
            tokenError = NSError(domain: "Auth", code: 5, userInfo: [NSLocalizedDescriptionKey: "No data"])
            return
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            tokenError = NSError(domain: "Auth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(body)"])
            return
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["access_token"] as? String {
            accessToken = token
        } else {
            tokenError = NSError(domain: "Auth", code: 6, userInfo: [NSLocalizedDescriptionKey: "No access_token in response"])
        }
    }.resume()

    semaphore.wait()

    if let error = tokenError {
        print("ERROR: \(error.localizedDescription)")
        exit(1)
    }

    guard let token = accessToken else {
        print("ERROR: No token received")
        exit(1)
    }

    print("Got access token: \(token.prefix(50))...")

    // Test the token by listing recognizers
    print("\nTesting token with Speech V2 API...")

    let testSemaphore = DispatchSemaphore(value: 0)
    var testSuccess = false

    let testUrl = URL(string: "https://us-speech.googleapis.com/v2/projects/\(projectId)/locations/us/recognizers")!
    var testRequest = URLRequest(url: testUrl)
    testRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: testRequest) { data, response, error in
        defer { testSemaphore.signal() }

        if let error = error {
            print("API test error: \(error.localizedDescription)")
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            return
        }

        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
        print("API response status: \(httpResponse.statusCode)")
        print("API response body: \(body.prefix(500))")

        testSuccess = httpResponse.statusCode == 200
    }.resume()

    testSemaphore.wait()

    if testSuccess {
        print("\n✅ SUCCESS: Authentication working!")
    } else {
        print("\n❌ FAILED: API call failed")
        exit(1)
    }

} catch {
    print("ERROR: \(error.localizedDescription)")
    exit(1)
}
