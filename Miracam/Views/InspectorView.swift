import SwiftUI

struct InspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userConfig = UserConfiguration.shared
    @State private var showCopiedAlert = false
    @State private var copiedText = ""
    @State private var contentKeyInfo: String = "Loading..."
    
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
                
                Section {
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
        Task {
            print("Starting app reset...")
            
            // Remove all keys and data
            print("Resetting setup manager keys...")
            await SetupManager.shared.resetAllKeys()
            
            print("Deleting secure enclave keys...")
            let seResult = SecureEnclaveManager.shared.deleteKeys()
            print("Secure enclave deletion result: \(seResult)")
            
            print("Removing attestation key ID...")
            let attResult = AttestationManager.shared.removeKeyId()
            print("Attestation key removal result: \(attResult)")
            
            print("Removing content key...")
            let contentResult = ContentKeyManager.shared.removeContentKey()
            print("Content key removal result: \(contentResult)")
            
            print("Removing Ethereum wallet...")
            let ethResult = EthereumManager.shared.removeWallet()
            print("Ethereum wallet removal result: \(ethResult)")
            
            // Reset UserConfiguration settings
            print("Resetting UserConfiguration...")
            UserDefaults.standard.removeObject(forKey: "isPublicMode")
            UserDefaults.standard.removeObject(forKey: "enabledSensors")
            userConfig.isPublicMode = true  // Reset to default value
            userConfig.enabledSensors = Set(SensorType.allCases)  // Reset to default value
            
            // Reset initial setup flag
            print("Resetting UserDefaults...")
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSetup")
            
            // Force synchronize UserDefaults to ensure all changes are saved
            UserDefaults.standard.synchronize()
            
            // Exit the app
            print("Exiting app...")
            exit(0)
        }
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