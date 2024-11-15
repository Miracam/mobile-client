import Foundation
import DeviceCheck

enum AttestationError: Error {
    case keyGenerationFailed(Error?)
    case attestationFailed(Error?)
    case nonceRetrievalFailed(Error?)
    case validationFailed(Error?)
    case serverError(Error?)
    case noKeyId
}

@MainActor
class AttestationManager {
    static let shared = AttestationManager()
    private let keychain = KeychainHelper.standard
    private let keychainKey = "com.miracam.attestation.keyid"
    
    private init() {}
    
    func getStoredKeyId() -> String? {
        return keychain.read(key: keychainKey)
    }
    
    func attestDeviceIfNeeded() async throws -> String {
        print("🔐 Starting attestation process...")
        
        // Check for existing attestation
        if let existingKeyId = getStoredKeyId() {
            print("✅ Found existing attestation key ID: \(existingKeyId)")
            return existingKeyId
        }
        print("ℹ️ No existing attestation found, starting new attestation...")
        
        // Generate new key
        print("🔑 Generating new attestation key...")
        let keyId = try await generateKey()
        print("✅ Generated key ID: \(keyId)")
        
        // Get nonce from server
        print("🌐 Requesting nonce from server...")
        let nonce = try await getNonce(keyId: keyId)
        print("✅ Received nonce of length: \(nonce.count) bytes")
        
        // Attest the key
        print("🔐 Attesting key with Device Check...")
        let attestation = try await attestKey(keyId: keyId, nonce: nonce)
        print("✅ Attestation received, length: \(attestation.count) bytes")
        
        // Validate with server
        print("🌐 Validating attestation with server...")
        try await validateAttestation(keyId: keyId, attestation: attestation)
        print("✅ Server validated attestation")
        
        // Store the validated key ID
        print("💾 Storing attestation key ID...")
        keychain.save(keyId, key: keychainKey)
        print("✅ Attestation process complete")
        
        return keyId
    }
    
    private func generateKey() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateKey { keyId, error in
                if let error = error {
                    continuation.resume(throwing: AttestationError.keyGenerationFailed(error))
                    return
                }
                
                guard let keyId = keyId else {
                    continuation.resume(throwing: AttestationError.keyGenerationFailed(nil))
                    return
                }
                
                continuation.resume(returning: keyId)
            }
        }
    }
    
    private func getNonce(keyId: String) async throws -> Data {
        print("🔑 Getting Secure Enclave public key...")
        guard let publicKey = SecureEnclaveManager.shared.getStoredPublicKey() else {
            print("❌ Failed to get Secure Enclave public key")
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        print("✅ Got public key: \(String(describing: publicKey.prefix(32)))...")
        
        // Create URL with query parameters
        let baseUrlString = "\(AppConstants.Server.baseURL)/nonce"
        guard var urlComponents = URLComponents(string: baseUrlString) else {
            print("❌ Invalid base URL: \(baseUrlString)")
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        
        // Add query parameters
        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: keyId),
            URLQueryItem(name: "publicKey", value: publicKey)
        ]
        
        guard let url = urlComponents.url else {
            print("❌ Failed to construct URL with parameters")
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        
        print("🌐 Sending GET request to: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Received response with status code: \(httpResponse.statusCode)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let nonceHex = json["nonce"] else {
                print("❌ Failed to parse server response")
                print("📦 Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw AttestationError.nonceRetrievalFailed(nil)
            }
            
            guard let nonceData = Data(hex: nonceHex) else {
                print("❌ Failed to convert nonce hex to Data: \(nonceHex)")
                throw AttestationError.nonceRetrievalFailed(nil)
            }
            
            print("✅ Successfully received and parsed nonce")
            return nonceData
            
        } catch {
            print("❌ Network request failed: \(error)")
            throw AttestationError.nonceRetrievalFailed(error)
        }
    }
    
    private func attestKey(keyId: String, nonce: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.attestKey(keyId, clientDataHash: nonce) { attestation, error in
                if let error = error {
                    continuation.resume(throwing: AttestationError.attestationFailed(error))
                    return
                }
                
                guard let attestation = attestation else {
                    continuation.resume(throwing: AttestationError.attestationFailed(nil))
                    return
                }
                
                continuation.resume(returning: attestation)
            }
        }
    }
    
    private func validateAttestation(keyId: String, attestation: Data) async throws {
        let url = URL(string: AppConstants.Server.attestKeyEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString()
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AttestationError.validationFailed(nil)
        }
    }
}

// Helper for hex conversion
private extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i*2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}

// Simple Keychain helper
private class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}
    
    func save(_ data: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data.data(using: .utf8)!
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
} 