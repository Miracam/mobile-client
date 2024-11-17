import SwiftUI

struct InspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userConfig = UserConfiguration.shared
    @State private var showCopiedAlert = false
    @State private var copiedText = ""
    @State private var contentKeyInfo: String = "Loading..."
    @State private var showResetConfirmation = false
    @State private var showOnboardingResetConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Wallet") {
                    if let address = EthereumManager.shared.getWalletAddress() {
                        KeyInfoRow(
                            title: "Ethereum Address",
                            value: address,
                            onCopy: { copyToClipboard(address) }
                        )
                        
                        Button(action: {
                            Task {
                                if let privateKey = try? await EthereumManager.shared.getPrivateKey() {
                                    copyToClipboard(privateKey)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("Copy Private Key")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Keys") {
                    if let publicKey = SecureEnclaveManager.shared.getStoredPublicKey() {
                        KeyInfoRow(
                            title: "SECP256R1",
                            value: publicKey,
                            onCopy: { copyToClipboard(publicKey) }
                        )
                    }
                    
                    if let keyId = AttestationManager.shared.getStoredKeyId() {
                        KeyInfoRow(
                            title: "Attestation Key ID",
                            value: keyId,
                            onCopy: { copyToClipboard(keyId) }
                        )
                    }
                    
                    KeyInfoRow(
                        title: "Content Key",
                        value: contentKeyInfo,
                        onCopy: { copyToClipboard(contentKeyInfo) }
                    )
                }
                
                Section("Device Info") {
                    InfoRow(title: "Model", value: UIDevice.current.model)
                    InfoRow(title: "System Version", value: UIDevice.current.systemVersion)
                }
                
                Section("App Info") {
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        InfoRow(title: "Version", value: version)
                    }
                }
                
                Section("Development") {
                    Button(action: {
                        showOnboardingResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Onboarding")
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                    }
                    
                    Button(action: {
                        resetApp()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset App")
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Reset App", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    print("Starting app reset...")
                    await SetupManager.shared.resetAllKeys()
                    print("Reset complete, exiting app...")
                    exit(0)
                }
            }
        } message: {
            Text("This will reset all app data and keys. You'll need to go through the setup process again. Are you sure?")
        }
        .alert("Reset Onboarding", isPresented: $showOnboardingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetOnboarding()
            }
        } message: {
            Text("This will only reset the onboarding flow. Your keys and data will be preserved. Continue?")
        }
        .onAppear {
            // Load content key info once when view appears
            if let contentKey = ContentKeyManager.shared.checkExistingContentKey() {
                contentKeyInfo = contentKey.combined.base64EncodedString()
            } else {
                contentKeyInfo = "No content key found"
            }
        }
        .overlay(
            ToastView(message: "Copied: \(copiedText)", isShowing: $showCopiedAlert)
        )
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        copiedText = String(text.prefix(20)) + "..."
        showCopiedAlert = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
    
    private func resetApp() {
        showResetConfirmation = true
    }
    
    private func resetOnboarding() {
        // Reset only the onboarding-related flags
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.usernameKey)
        UserDefaults.standard.set(false, forKey: "hasCompletedInitialSetup")
        UserDefaults.standard.synchronize()
        
        // Force app restart
        exit(0)
    }
}

struct KeyInfoRow: View {
    let title: String
    let value: String
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
            }
            
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.gray)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    InspectorView()
} 