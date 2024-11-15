import Foundation

enum SetupCheckType: String, CaseIterable {
    case secp256r1 = "Generating secure keys..."
    case ethereum = "Setting up wallet..."
    case contentKey = "Encrypting content key..."
    case attestation = "Minting access NFT..."
    case litSecret = "Verifying Lit Protocol..."
    
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
    @Published var elapsedTime: TimeInterval = 0
    
    @Published var ethereumAddress: String?
    
    @Published var username: String = ""
    
    // Singleton instance
    static let shared = SetupManager()
    private var startTime: Date?
    private var timer: Timer?
    
    private init() {}
    
    func runAllChecks() async -> Bool {
        // Start timer and setup
        startSetup()
        
        defer {
            stopTimer()
        }
        
        // Check if we already have valid access NFT
        if AttestationManager.shared.hasStoredAccessNFT() {
            currentCheck = .attestation
            
            // Still verify that all required keys exist
            let secp256r1Exists = SecureEnclaveManager.shared.getStoredPublicKey() != nil
            let ethereumExists = EthereumManager.shared.getWalletAddress() != nil
            let contentKeyExists = ContentKeyManager.shared.checkExistingContentKey() != nil
            let attestationExists = AttestationManager.shared.getStoredKeyId() != nil
            
            if secp256r1Exists && ethereumExists && contentKeyExists && attestationExists {
                print("✅ Found valid access NFT and all required keys")
                isChecking = false
                return true
            }
        }
        
        // If not, proceed with full setup
        // 1. Generate SECP256R1 keys
        let secp256r1Result = await checkWithUpdate(.secp256r1)
        guard secp256r1Result else {
            await handleFailure([.secp256r1])
            return false
        }
        
        // 2. Generate Ethereum keys
        let ethereumResult = await checkWithUpdate(.ethereum)
        guard ethereumResult else {
            await handleFailure([.secp256r1, .ethereum])
            return false
        }
        
        // 3. Generate and encrypt content key with Lit
        let contentKeyResult = await checkWithUpdate(.contentKey)
        guard contentKeyResult else {
            await handleFailure([.secp256r1, .ethereum, .contentKey])
            return false
        }
        
        // 4. Create attestation and mint access NFT
        let attestationResult = await checkWithUpdate(.attestation)
        let allSucceeded = attestationResult
        
        isChecking = false
        setupFailed = !allSucceeded
        if !allSucceeded {
            failedChecks = [.secp256r1, .ethereum, .contentKey, .attestation]
                .filter { !checkResults[$0, default: false] }
        }
        
        // Add this somewhere appropriate in your setup process
        self.ethereumAddress = "0x..." // Replace with actual ethereum address generation/fetching
        
        return allSucceeded
    }
    
    private func startSetup() {
        isChecking = true
        setupFailed = false
        failedChecks = []
        startTime = Date()
        elapsedTime = 0
        
        // Start timer on main actor
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func handleFailure(_ checks: [SetupCheckType]) async {
        await MainActor.run {
            isChecking = false
            setupFailed = true
            failedChecks = checks
        }
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
        case .contentKey:
            return await checkContentKey()
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
            let _ = try await AttestationManager.shared.attestDeviceIfNeeded()
            print("✅ Attestation successful")
            return true
        } catch {
            print("❌ Attestation failed")
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
    
    private func checkContentKey() async -> Bool {
        print("🔑 Starting content key setup...")
        
        do {
            // Try to get or create content key
            let (_, litEncryptedKey) = try await ContentKeyManager.shared.ensureContentKeyWithLit()
            
            // If we got here, either we have an existing key or successfully created a new one
            if litEncryptedKey.ciphertext == "existing_key" {
                print("✅ Content key found in keychain")
            } else {
                print("✅ New content key created and encrypted")
            }
            
            return true
        } catch {
            print("❌ Content key setup failed")
            return false
        }
    }
    
    // Add method to reset all keys
    @MainActor
    func resetAllKeys() async {
        // Reset all check results
        checkResults.removeAll()
        currentCheck = nil
        setupFailed = false
        failedChecks = []
        ethereumAddress = nil
        
        // Reset all stored keys and data
        _ = SecureEnclaveManager.shared.deleteKeys()
        _ = AttestationManager.shared.removeKeyId()
        _ = ContentKeyManager.shared.removeContentKey()
        _ = EthereumManager.shared.removeWallet()
        
        // Reset any cached data
        startTime = nil
        elapsedTime = 0
        isChecking = false
        
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.usernameKey)
        username = ""
    }
    
    // Add formatted elapsed time string
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int((elapsedTime * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
    
    func saveUsername(_ username: String) {
        self.username = username
        UserDefaults.standard.set(username, forKey: AppConstants.UserDefaults.usernameKey)
    }
    
    func getStoredUsername() -> String? {
        return UserDefaults.standard.string(forKey: AppConstants.UserDefaults.usernameKey)
    }
} 