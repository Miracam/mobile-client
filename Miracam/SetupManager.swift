import Foundation

enum SetupCheckType: String, CaseIterable {
    case secp256r1 = "Checking SECP256R1 key..."
    case attestation = "Verifying attestation key ID..."
    case ethereum = "Checking Ethereum keypair..."
    case litSecret = "Verifying Lit Protocol secret key..."
    case wallet = "Checking external wallet connection..."
    
    var description: String {
        return self.rawValue
    }
}

@MainActor
class SetupManager: ObservableObject {
    @Published var currentCheck: SetupCheckType?
    @Published var isChecking = false
    @Published var checkResults: [SetupCheckType: Bool] = [:]
    
    // Singleton instance
    static let shared = SetupManager()
    
    private init() {}
    
    func runAllChecks() async -> Bool {
        isChecking = true
        
        for check in SetupCheckType.allCases {
            await MainActor.run {
                currentCheck = check
            }
            let result = await performCheck(check)
            await MainActor.run {
                checkResults[check] = result
            }
            // Add artificial delay for visual feedback
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        await MainActor.run {
            isChecking = false
        }
        return checkResults.values.allSatisfy { $0 }
    }
    
    private func performCheck(_ check: SetupCheckType) async -> Bool {
        switch check {
        case .secp256r1:
            return await checkSecp256r1Key()
        case .attestation:
            return await checkAttestationKeyId()
        case .ethereum:
            return await checkEthereumKeyPair()
        case .litSecret:
            return await checkLitSecretKey()
        case .wallet:
            return await checkExternalWallet()
        }
    }
    
    private func checkSecp256r1Key() async -> Bool {
        if SecureEnclaveManager.shared.getStoredPublicKey() != nil {
            return true
        }
        
        return await withCheckedContinuation { continuation in
            SecureEnclaveManager.shared.generateAndStoreKey { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    
    private func checkAttestationKeyId() async -> Bool {
        print("🔐 Starting attestation check...")
        do {
            let keyId = try await AttestationManager.shared.attestDeviceIfNeeded()
            print("✅ Attestation successful with key ID: \(keyId)")
            return true
        } catch {
            print("❌ Attestation failed with error: \(error)")
            if let attestError = error as? AttestationError {
                switch attestError {
                case .keyGenerationFailed(let underlyingError):
                    print("  - Key generation failed: \(String(describing: underlyingError))")
                case .attestationFailed(let underlyingError):
                    print("  - Attestation failed: \(String(describing: underlyingError))")
                case .nonceRetrievalFailed(let underlyingError):
                    print("  - Nonce retrieval failed: \(String(describing: underlyingError))")
                case .validationFailed(let underlyingError):
                    print("  - Validation failed: \(String(describing: underlyingError))")
                case .serverError(let underlyingError):
                    print("  - Server error: \(String(describing: underlyingError))")
                case .noKeyId:
                    print("  - No key ID available")
                }
            }
            return false
        }
    }
    
    private func checkEthereumKeyPair() async -> Bool {
        do {
            _ = try await EthereumManager.shared.createOrLoadWallet()
            return true
        } catch {
            print("Failed to setup Ethereum wallet: \(error)")
            return false
        }
    }
    
    private func checkLitSecretKey() async -> Bool {
        // TODO: Implement actual Lit Protocol secret key check
        return true
    }
    
    private func checkExternalWallet() async -> Bool {
        // TODO: Implement actual external wallet connection check
        return true
    }
} 