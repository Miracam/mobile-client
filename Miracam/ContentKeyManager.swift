import Foundation
import CryptoKit

enum ContentKeyError: Error {
    case keyGenerationFailed
    case keyStorageFailed
    case keyRetrievalFailed
    case noKeyFound
    case invalidKeyData
}

struct ContentKeyData {
    let key: SymmetricKey
    let nonce: AES.GCM.Nonce
    
    var combined: Data {
        // Combine key and nonce for storage
        let keyData = key.withUnsafeBytes { Data($0) }
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        return keyData + nonceData
    }
    
    static func fromCombinedData(_ data: Data) throws -> ContentKeyData {
        // AES-256 key is 32 bytes, GCM nonce is 12 bytes
        guard data.count == 44 else {
            throw ContentKeyError.invalidKeyData
        }
        
        let keyData = data.prefix(32)
        let nonceData = data.suffix(12)
        
        let key = SymmetricKey(data: keyData)
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw ContentKeyError.invalidKeyData
        }
        
        return ContentKeyData(key: key, nonce: nonce)
    }
}

class ContentKeyManager {
    static let shared = ContentKeyManager()
    
    private let keychainService = "com.miracam.contentkey"
    
    private enum KeychainKey {
        static let contentKey = "content_key"
    }
    
    private init() {}
    
    /// Checks if a content key exists for the current Ethereum wallet
    /// - Returns: The existing content key if found
    func checkExistingContentKey() -> ContentKeyData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.contentKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let keyData = result as? Data,
              let contentKeyData = try? ContentKeyData.fromCombinedData(keyData) else {
            return nil
        }
        
        return contentKeyData
    }
    
    /// Generates a new AES-GCM key and nonce
    /// - Returns: The newly generated key data
    private func generateContentKey() throws -> ContentKeyData {
        // Generate a random AES-256 key
        let key = SymmetricKey(size: .bits256)
        
        // Generate a random nonce
        let nonce = AES.GCM.Nonce()
        
        return ContentKeyData(key: key, nonce: nonce)
    }
    
    /// Stores the content key in the keychain
    /// - Parameter keyData: The key data to store
    func storeContentKey(_ keyData: ContentKeyData) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.contentKey,
            kSecValueData as String: keyData.combined
        ]
        
        // First, try to delete any existing key
        SecItemDelete(query as CFDictionary)
        
        // Then add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw ContentKeyError.keyStorageFailed
        }
    }
    
    /// Gets or creates a content key for the current Ethereum wallet
    /// - Returns: The content key, either existing or newly generated
    func getOrCreateContentKey() throws -> ContentKeyData {
        if let existingKey = checkExistingContentKey() {
            return existingKey
        }
        
        let newKey = try generateContentKey()
        try storeContentKey(newKey)
        return newKey
    }
    
    /// Encrypts data using the content key
    /// - Parameter data: The data to encrypt
    /// - Returns: The encrypted data
    func encrypt(_ data: Data) throws -> Data {
        let keyData = try getOrCreateContentKey()
        let sealedBox = try AES.GCM.seal(data,
                                        using: keyData.key,
                                        nonce: keyData.nonce)
        return sealedBox.combined!
    }
    
    /// Decrypts data using the content key
    /// - Parameter encryptedData: The data to decrypt
    /// - Returns: The decrypted data
    func decrypt(_ encryptedData: Data) throws -> Data {
        let keyData = try getOrCreateContentKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: keyData.key)
    }
} 