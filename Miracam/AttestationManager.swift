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
        if let existingKeyId = getStoredKeyId() {
            return existingKeyId
        }
        
        let keyId = try await generateKey()
        let nonce = try await getNonce(keyId: keyId)
        let attestation = try await attestKey(keyId: keyId, nonce: nonce)
        try await validateAttestation(keyId: keyId, attestation: attestation)
        keychain.save(keyId, key: keychainKey)
        
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
        guard let publicKey = SecureEnclaveManager.shared.getStoredPublicKey() else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        
        let baseUrlString = "\(AppConstants.Server.baseURL)/nonce"
        guard var urlComponents = URLComponents(string: baseUrlString) else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: keyId),
            URLQueryItem(name: "publicKey", value: publicKey)
        ]
        
        guard let url = urlComponents.url else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let nonceHex = json["nonce"],
                  let nonceData = Data(hex: nonceHex) else {
                throw AttestationError.nonceRetrievalFailed(nil)
            }
            
            return nonceData
            
        } catch {
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