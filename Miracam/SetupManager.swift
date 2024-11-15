import Foundation

enum SetupCheckType: String, CaseIterable {
    case secp256r1 = "Checking SECP256R1 key..."
    case attestation = "Verifying attestation key ID..."
    case ethereum = "Checking Ethereum keypair..."
    case litSecret = "Verifying Lit Protocol secret key..."
    
    var description: String {
        return self.rawValue
    }
}

@MainActor
class SetupManager: ObservableObject {
    @Published var currentCheck: SetupCheckType?
    @Published var isChecking = false
    @Published var checkResults: [SetupCheckType: Bool] = [:]
    @Published var setupFailed = false
    @Published var failedChecks: [SetupCheckType] = []
    
    // Singleton instance
    static let shared = SetupManager()
    
    private init() {}
    
    func runAllChecks() async -> Bool {
        await MainActor.run {
            isChecking = true
            setupFailed = false
            failedChecks = []
        }
        
        // Run all checks in parallel
        async let secp256r1Result = checkWithUpdate(.secp256r1)
        async let attestationResult = checkWithUpdate(.attestation)
        async let ethereumResult = checkWithUpdate(.ethereum)
        async let litSecretResult = checkWithUpdate(.litSecret)
        
        // Wait for all checks to complete
        let results = await [
            secp256r1Result,
            attestationResult,
            ethereumResult,
            litSecretResult
        ]
        
        let allSucceeded = results.allSatisfy { $0 }
        
        await MainActor.run {
            isChecking = false
            setupFailed = !allSucceeded
            
            // Collect failed checks if any
            if !allSucceeded {
                failedChecks = zip(SetupCheckType.allCases, results)
                    .filter { !$0.1 }
                    .map { $0.0 }
            }
        }
        
        return allSucceeded
    }
    
    // Helper function to perform check and update UI
    private func checkWithUpdate(_ check: SetupCheckType) async -> Bool {
        await MainActor.run {
            currentCheck = check
        }
        
        let result = await performCheck(check)
        
        await MainActor.run {
            checkResults[check] = result
        }
        
        // Keep the artificial delay for visual feedback
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        return result
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
} 