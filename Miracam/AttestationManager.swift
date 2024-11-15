import Foundation
import DeviceCheck
import CryptoKit

enum AttestationError: Error {
    case keyGenerationFailed(Error?)
    case attestationFailed(Error?)
    case nonceRetrievalFailed(Error?)
    case validationFailed(Error?)
    case serverError(Error?)
    case noKeyId
    case onboardingFailed(Error?)
}

private struct OnboardingPayload: Encodable {
    let secpPublicKey: String
    let ethereumAddress: String
    let litCiphertext: String
    let litHash: String
    let challengeData: String       // hashed challenge data
    let challengeDataPlain: String  // plain text challenge data before hashing
    let attestationReceipt: String
    let keyId: String
    
    enum CodingKeys: String, CodingKey {
        case secpPublicKey = "secp256r1_pubkey"
        case ethereumAddress = "ethereum_address"
        case litCiphertext = "lit_ciphertext"
        case litHash = "lit_hash"
        case challengeData = "challenge_data"
        case challengeDataPlain = "challenge_data_plain"
        case attestationReceipt = "attestation_receipt"
        case keyId = "key_id"
    }
}

// Add a struct to hold both plain and hashed challenge data
private struct ChallengeDataResult {
    let plain: String
    let hashed: Data
}

// Change from private to internal
struct NFTResponse: Codable {
    let irys: IrysData
    let nft: NFTData
}

struct IrysData: Codable {
    let id: String
    let url: String
}

struct NFTData: Codable {
    let hash: String
    let tokenId: Int
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
        let challengeData = try generateChallengeData()
        let attestation = try await attestKey(keyId: keyId, challengeData: challengeData.hashed)
        
        try await sendOnboardingData(
            keyId: keyId,
            challengeData: challengeData,
            attestation: attestation
        )
        
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
    
    private func generateChallengeData() throws -> ChallengeDataResult {
        var components: [(String, String)] = []
        
        // Get SECP256R1 public key
        guard let secpPublicKey = SecureEnclaveManager.shared.getStoredPublicKey() else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        components.append(("secp256r1_pubkey", secpPublicKey))
        
        // Get Ethereum address
        guard let ethAddress = EthereumManager.shared.getWalletAddress() else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        components.append(("ethereum_address", ethAddress))
        
        // Get Lit-encrypted content key
        guard let litEncryption = ContentKeyManager.shared.getStoredLitEncryption() else {
            throw AttestationError.nonceRetrievalFailed(nil)
        }
        components.append(("lit_ciphertext", litEncryption.ciphertext))
        components.append(("lit_hash", litEncryption.dataToEncryptHash))
        
        // Sort components alphabetically by key
        components.sort { $0.0 < $1.0 }
        
        // Create query string
        let queryString = components
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
        
        // Generate SHA256 hash
        let challengeData = queryString.data(using: .utf8)!
        let hash = SHA256.hash(data: challengeData)
        
        return ChallengeDataResult(
            plain: queryString,
            hashed: Data(hash)
        )
    }
    
    private func attestKey(keyId: String, challengeData: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.attestKey(keyId, clientDataHash: challengeData) { attestation, error in
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
    
    private func sendOnboardingData(keyId: String, challengeData: ChallengeDataResult, attestation: Data) async throws {
        // Get required data
        guard let secpPublicKey = SecureEnclaveManager.shared.getStoredPublicKey(),
              let ethAddress = EthereumManager.shared.getWalletAddress(),
              let litEncryption = ContentKeyManager.shared.getStoredLitEncryption() else {
            throw AttestationError.onboardingFailed(nil)
        }
        
        // Create payload
        let payload = OnboardingPayload(
            secpPublicKey: secpPublicKey,
            ethereumAddress: ethAddress,
            litCiphertext: litEncryption.ciphertext,
            litHash: litEncryption.dataToEncryptHash,
            challengeData: challengeData.hashed.base64EncodedString(),
            challengeDataPlain: challengeData.plain,
            attestationReceipt: attestation.base64EncodedString(),
            keyId: keyId
        )
        
        // Create request
        let url = URL(string: "\(AppConstants.Server.baseURL)/access_nft")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encodedPayload = try JSONEncoder().encode(payload)
            request.httpBody = encodedPayload
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AttestationError.onboardingFailed(nil)
            }
            
            if let jsonResponse = try? JSONSerialization.jsonObject(with: data),
               let prettyPrinted = try? JSONSerialization.data(withJSONObject: jsonResponse, options: .prettyPrinted) {
                #if DEBUG
                if let jsonString = String(data: prettyPrinted, encoding: .utf8) {
                    print("📥 Server response from /access_nft")
                    print(jsonString)
                }
                #endif
            }
            
            guard httpResponse.statusCode == 200 else {
                // If there's an error response, try to print it
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Server error response:")
                    print(errorString)
                }
                
                throw AttestationError.onboardingFailed(
                    NSError(domain: "Attestation",
                           code: httpResponse.statusCode,
                           userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
                )
            }
            
            // Decode and store the NFT response
            let nftResponse = try JSONDecoder().decode(NFTResponse.self, from: data)
            try storeAccessNFT(nftResponse)
            
        } catch {
            print("❌ Access NFT request failed: \(error)")
            throw AttestationError.onboardingFailed(error)
        }
    }

    private func storeAccessNFT(_ nftResponse: NFTResponse) throws {
        let data = try JSONEncoder().encode(nftResponse)
        keychain.save(data.base64EncodedString(), key: "access_nft")
    }

    // Add method to check for stored NFT
    func hasStoredAccessNFT() -> Bool {
        return keychain.read(key: "access_nft") != nil
    }

    // Add method to get stored NFT data
    func getStoredAccessNFT() -> NFTResponse? {
        guard let base64String = keychain.read(key: "access_nft"),
              let data = Data(base64Encoded: base64String),
              let nftResponse = try? JSONDecoder().decode(NFTResponse.self, from: data) else {
            return nil
        }
        return nftResponse
    }

    func removeKeyId() -> Bool {
        let keyIdRemoved = keychain.delete(key: keychainKey)
        let nftRemoved = keychain.delete(key: "access_nft")
        return keyIdRemoved && nftRemoved
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
    
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
} 