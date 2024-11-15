import Foundation
import Security

class SecureEnclaveManager {
    static let shared = SecureEnclaveManager()
    
    private let tag = "com.miracam.secureenclave.keypair".data(using: .utf8)!
    private var privateKey: SecKey?
    private var publicKey: SecKey?
    
    private init() {}
    
    // MARK: - Key Generation and Storage
    
    func generateAndStoreKey(completion: @escaping (Bool, String?) -> Void) {
        let access = SecAccessControlCreateWithFlags(nil,
                                                   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                   [.privateKeyUsage],
                                                   nil)!
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("❌ Error generating key")
            completion(false, nil)
            return
        }
        
        self.privateKey = privateKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            print("❌ Error getting public key")
            completion(false, nil)
            return
        }
        
        self.publicKey = publicKey
        
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            print("❌ Error getting public key data")
            completion(false, nil)
            return
        }
        
        let publicKeyBase64 = publicKeyData.base64EncodedString()
        completion(true, publicKeyBase64)
    }
    
    func getStoredPublicKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            print("❌ Error fetching key")
            return nil
        }
        
        let privateKey = item as! SecKey
        self.privateKey = privateKey
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            print("❌ Error getting public key")
            return nil
        }
        
        self.publicKey = publicKey
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            print("❌ Error getting public key data")
            return nil
        }
        
        return publicKeyData.base64EncodedString()
    }
    
    // MARK: - Encryption/Decryption
    
    func encrypt(_ data: Data) -> Data? {
        guard let publicKey = self.publicKey else {
            print("Public key not available")
            return nil
        }
        
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM
        
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            print("Algorithm not supported")
            return nil
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &error) as Data? else {
            print("❌ Encryption error")
            return nil
        }
        
        return encryptedData
    }
    
    func decrypt(_ encryptedData: Data) -> Data? {
        guard let privateKey = self.privateKey else {
            print("Private key not available")
            return nil
        }
        
        let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorVariableIVX963SHA256AESGCM
        
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            print("Algorithm not supported")
            return nil
        }
        
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, encryptedData as CFData, &error) as Data? else {
            print("❌ Decryption error")
            return nil
        }
        
        return decryptedData
    }
    
    // MARK: - Signing/Verification
    
    func sign(_ data: Data) -> Data? {
        guard let privateKey = self.privateKey else {
            print("Private key not available")
            return nil
        }
        
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            print("Algorithm not supported")
            return nil
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, data as CFData, &error) as Data? else {
            print("❌ Signing error")
            return nil
        }
        
        return signature
    }
    
    func verify(_ data: Data, signature: Data) -> Bool {
        guard let publicKey = self.publicKey else {
            print("Public key not available")
            return false
        }
        
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) else {
            print("Algorithm not supported")
            return false
        }
        
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(publicKey, algorithm, data as CFData, signature as CFData, &error)
        
        if let error = error {
            print("❌ Verification error: \(error.takeRetainedValue() as Error)")
        }
        
        return isValid
    }
    
    // MARK: - Key Management
    
    func deleteKeys() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            self.privateKey = nil
            self.publicKey = nil
            return true
        }
        
        print("❌ Error deleting keys")
        return false
    }
} 