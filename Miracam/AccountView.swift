import SwiftUI

struct QRCodeView: View {
    let address: String
    
    var body: some View {
        Group {
            if let qrImage = QRCodeGenerator.generateQRCode(from: address) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Text("QR Error")
                            .foregroundColor(.gray)
                    )
            }
        }
        .background(Color.white)
        .cornerRadius(12)
    }
}

struct AccountView: View {
    @State private var publicKey: String = "Loading..."
    @State private var attestationKeyId: String = "Loading..."
    @State private var ethAddress: String = "Loading..."
    @State private var ethBalance: String = "Loading..."
    @State private var usdcBalance: String = "Loading..."
    @State private var testBalance: String = "Loading..."
    @State private var contentKeyStatus: String = "Loading..."
    @State private var showCopiedAlert = false
    @State private var isRefreshing = false
    @State private var messageToSign: String = ""
    @State private var signature: String = ""
    @State private var showSigningSheet = false
    @State private var showEncryptionSheet = false
    @State private var messageToEncrypt: String = ""
    @State private var encryptedResult: String = ""
    @State private var decryptedResult: String = ""
    @State private var showSecpSigningSheet = false
    @State private var showEthSigningSheet = false
    @State private var showInspector = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @StateObject private var userConfig = UserConfiguration.shared
    
    @State private var showBuyActionSheet = false
    @State private var showWalletActionSheet = false
    
    @State private var showWebView = false
    @State private var webURL: URL?
    
    @State private var showCopyMenu = false
    
    @StateObject private var setupManager = SetupManager.shared
    
    private var displayUsername: String {
        setupManager.getStoredUsername() ?? "unnamed"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Inspector Button
            HStack {
                Spacer()
                Button(action: {
                    showInspector = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .padding()
            }
            
            // Main content with flexible spacing
            VStack {
                Spacer()
                
                // Replace the QR Code placeholder with the actual QR code
                if let address = EthereumManager.shared.getWalletAddress() {
                    QRCodeView(address: address)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 160, height: 160)
                        .overlay(
                            Text("Loading...")
                                .foregroundColor(.gray)
                        )
                }
                
                // Name Row
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(displayUsername).miracam.com")
                                .font(.headline)
                            if let ethAddress = EthereumManager.shared.getWalletAddress() {
                                Text(ethAddress.prefix(6) + "..." + ethAddress.suffix(4))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(action: {
                            if let address = EthereumManager.shared.getWalletAddress() {
                                showCopyMenu(address: address)
                            }
                        }) {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Balance Row
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Balance")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("0.00 FILM")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(action: {
                            showBuyActionSheet = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.vertical, 20)
                
                Spacer()
            }
            
            // Bottom Grid Section
            VStack(spacing: 12) {
                // Connect Wallet Button (full width)
                Button(action: {
                    webURL = URL(string: AppConstants.WebView.externalWalletURL)
                    showWebView = true
                }) {
                    Text("connect external wallet")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .sheet(isPresented: $showWebView) {
                    if let url = webURL {
                        SafariWebView(url: url)
                    }
                }
                
                // Control Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ControlButton(
                        title: "Compass",
                        icon: "location.north.fill",
                        isEnabled: userConfig.enabledSensors.contains(.compass)
                    )
                    ControlButton(
                        title: "Motion",
                        icon: "gyroscope",
                        isEnabled: userConfig.enabledSensors.contains(.motion)
                    )
                    ControlButton(
                        title: "Audio",
                        icon: "speaker.wave.2",
                        isEnabled: userConfig.enabledSensors.contains(.audio)
                    )
                    ControlButton(
                        title: "Location",
                        icon: "location",
                        isEnabled: userConfig.enabledSensors.contains(.coordinates)
                    )
                    ControlButton(
                        title: "Battery",
                        icon: "battery.100",
                        isEnabled: userConfig.enabledSensors.contains(.battery)
                    )
                    ControlButton(
                        title: "Private",
                        icon: "lock",
                        isEnabled: !userConfig.isPublicMode
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
        }
        .background(Color.gray.opacity(0.1))
        .fullScreenCover(isPresented: $showInspector) {
            InspectorView()
        }
        .confirmationDialog("Buy FILM", isPresented: $showBuyActionSheet) {
            Button("Buy with Credit Card") { }
            Button("Buy with Crypto") { }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Copy", isPresented: $showCopyMenu, titleVisibility: .hidden) {
            Button("Copy ENS") {
                copyToClipboard("\(displayUsername).miracam.com")
            }
            if let address = EthereumManager.shared.getWalletAddress() {
                Button("Copy Address") {
                    copyToClipboard(address)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        showCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
    
    private func loadKeys() {
        // Load SECP256R1 public key
        if let key = SecureEnclaveManager.shared.getStoredPublicKey() {
            let chunks = key.chunked(into: 64)
            publicKey = chunks.joined(separator: "\n")
        } else {
            publicKey = "No key found"
        }
        
        // Load attestation key ID
        if let keyId = AttestationManager.shared.getStoredKeyId() {
            attestationKeyId = keyId
        } else {
            attestationKeyId = "No attestation key found"
        }
        
        // Load Ethereum address
        if let address = EthereumManager.shared.getWalletAddress() {
            ethAddress = address
        } else {
            ethAddress = "No wallet found"
        }
    }
    
    private func loadBalances() async {
        await refreshBalances()
    }
    
    private func refreshBalances() async {
        guard !isRefreshing else { return }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        do {
            let balances = try await EthereumManager.shared.getBalances()
            await MainActor.run {
                ethBalance = balances.eth
                usdcBalance = balances.usdc
                testBalance = balances.test
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                ethBalance = "Error"
                usdcBalance = "Error"
                testBalance = "Error"
                isRefreshing = false
            }
        }
    }
    
    private func testContentKey() {
        Task {
            do {
                // First, check if key exists
                if let existingKey = ContentKeyManager.shared.checkExistingContentKey() {
                    contentKeyStatus = "Existing key found: \(existingKey.combined.count) bytes"
                } else {
                    contentKeyStatus = "No existing key found"
                    
                    // Generate and store new key
                    let (newKey, litEncryptedKey) = try await ContentKeyManager.shared.getOrCreateContentKey()
                    contentKeyStatus = """
                        New key generated and stored: \(newKey.combined.count) bytes
                        Lit encrypted key hash: \(litEncryptedKey.dataToEncryptHash)
                        """
                    
                    // Verify it was stored
                    if ContentKeyManager.shared.checkExistingContentKey() != nil {
                        contentKeyStatus += "\nVerified: Key is stored"
                    } else {
                        contentKeyStatus += "\nError: Key storage verification failed"
                    }
                }
            } catch {
                contentKeyStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func resetApp() {
        Task {
            print("🔄 Starting app reset...")
            
            // Remove all keys and data in specific order
            print("1️⃣ Removing content key...")
            let contentResult = ContentKeyManager.shared.removeContentKey()
            print("Content key removal result: \(contentResult)")
            
            print("2️⃣ Removing Ethereum wallet...")
            let ethResult = EthereumManager.shared.removeWallet()
            print("Ethereum wallet removal result: \(ethResult)")
            
            print("3️⃣ Removing attestation key ID...")
            let attResult = AttestationManager.shared.removeKeyId()
            print("Attestation key removal result: \(attResult)")
            
            print("4️⃣ Deleting secure enclave keys...")
            let seResult = SecureEnclaveManager.shared.deleteKeys()
            print("Secure enclave deletion result: \(seResult)")
            
            print("5️⃣ Resetting setup manager keys...")
            await SetupManager.shared.resetAllKeys()
            
            // Reset UserConfiguration settings
            print("6️⃣ Resetting UserConfiguration...")
            UserDefaults.standard.removeObject(forKey: "isPublicMode")
            UserDefaults.standard.removeObject(forKey: "enabledSensors")
            userConfig.isPublicMode = true  // Reset to default value
            userConfig.enabledSensors = Set(SensorType.allCases)  // Reset to default value
            
            // Reset initial setup flag
            print("7️⃣ Resetting UserDefaults...")
            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSetup")
            
            // Force synchronize UserDefaults
            UserDefaults.standard.synchronize()
            
            print("8️⃣ Cleanup complete, exiting app...")
            exit(0)
        }
    }
    
    private func showCopyMenu(address: String) {
        showCopyMenu = true
    }
}

// Balance Row Component
struct BalanceRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

// Toast View Component
struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack {
                Spacer()
                Text(message)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom))
            .animation(.easeInOut, value: isShowing)
        }
    }
}

// Helper extension to chunk the key string
extension String {
    func chunked(into size: Int) -> [String] {
        return stride(from: 0, to: count, by: size).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: min(size, count - $0))
            return String(self[start..<end])
        }
    }
}

struct SigningTestView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var messageToSign: String
    @Binding var signature: String
    @State private var localSignature: String = ""
    @State private var hasSigned = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextEditor(text: $messageToSign)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding()
                
                if messageToSign.isEmpty {
                    Text("Enter message to sign")
                        .foregroundColor(.gray)
                        .padding(.top, -60) // Overlay placeholder text
                }
                
                if !hasSigned {
                    Button("Sign Message") {
                        signMessage()
                    }
                    .disabled(messageToSign.isEmpty)
                }
                
                if hasSigned {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Signature:")
                            .font(.headline)
                        
                        HStack {
                            Text(localSignature)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = localSignature
                                signature = localSignature // Update main view signature
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Sign Message")
            .navigationBarItems(trailing: Button("Done") {
                if hasSigned {
                    signature = localSignature
                }
                dismiss()
            })
        }
    }
    
    private func signMessage() {
        guard let messageData = messageToSign.data(using: .utf8),
              let signatureData = SecureEnclaveManager.shared.sign(messageData) else {
            localSignature = "Signing failed"
            hasSigned = true
            return
        }
        
        localSignature = signatureData.base64EncodedString()
        signature = localSignature // Update main view signature immediately
        hasSigned = true
    }
}

struct EncryptionTestView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var messageToEncrypt: String
    @Binding var encryptedResult: String
    @Binding var decryptedResult: String
    @State private var localEncrypted: String = ""
    @State private var localDecrypted: String = ""
    @State private var hasEncrypted = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextEditor(text: $messageToEncrypt)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding()
                
                if messageToEncrypt.isEmpty {
                    Text("Enter message to encrypt")
                        .foregroundColor(.gray)
                        .padding(.top, -60)
                }
                
                if !hasEncrypted {
                    Button("Encrypt Message") {
                        encryptMessage()
                    }
                    .disabled(messageToEncrypt.isEmpty)
                }
                
                if hasEncrypted {
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            Text("Encrypted:")
                                .font(.headline)
                            
                            HStack {
                                Text(localEncrypted)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                                
                                Button(action: {
                                    UIPasteboard.general.string = localEncrypted
                                }) {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            
                            Text("Decrypted:")
                                .font(.headline)
                            
                            HStack {
                                Text(localDecrypted)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                                
                                Button(action: {
                                    UIPasteboard.general.string = localDecrypted
                                }) {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Test Encryption")
            .navigationBarItems(trailing: Button("Done") {
                if hasEncrypted {
                    encryptedResult = localEncrypted
                    decryptedResult = localDecrypted
                }
                dismiss()
            })
        }
    }
    
    private func encryptMessage() {
        Task {
            do {
                guard let messageData = messageToEncrypt.data(using: .utf8) else {
                    localEncrypted = "Error: Invalid input"
                    return
                }
                
                // Encrypt
                let encryptedData = try await ContentKeyManager.shared.encrypt(messageData)
                localEncrypted = encryptedData.base64EncodedString()
                
                // Decrypt to verify
                let decryptedData = try await ContentKeyManager.shared.decrypt(encryptedData)
                if let decryptedString = String(data: decryptedData, encoding: .utf8) {
                    localDecrypted = decryptedString
                } else {
                    localDecrypted = "Error: Decryption failed"
                }
                
                hasEncrypted = true
            } catch {
                localEncrypted = "Error: \(error.localizedDescription)"
                localDecrypted = "Decryption not attempted"
                hasEncrypted = true
            }
        }
    }
}

struct EthereumSigningTestView: View {
    @Environment(\.dismiss) var dismiss
    @State private var messageToSign: String = ""
    @State private var signature: String = ""
    @State private var hasSigned = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextEditor(text: $messageToSign)
                    .frame(height: 100)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding()
                
                if messageToSign.isEmpty {
                    Text("Enter message to sign")
                        .foregroundColor(.gray)
                        .padding(.top, -60)
                }
                
                if !hasSigned {
                    Button(action: {
                        Task {
                            await signMessage()
                        }
                    }) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Sign with Ethereum")
                        }
                    }
                    .disabled(messageToSign.isEmpty || isLoading)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
                
                if hasSigned {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ethereum Signature:")
                            .font(.headline)
                        
                        HStack {
                            Text(signature)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = signature
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Ethereum Sign")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
    
    private func signMessage() async {
        isLoading = true
        errorMessage = nil
        
        do {
            signature = try await EthereumManager.shared.signMessage(messageToSign)
            hasSigned = true
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// New component for control buttons
struct ControlButton: View {
    @ObservedObject private var userConfig = UserConfiguration.shared
    let title: String
    let icon: String
    let isEnabled: Bool
    
    var body: some View {
        Button(action: {
            handleTap()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(isEnabled ? .white : .gray)
            .cornerRadius(8)
        }
    }
    
    private func handleTap() {
        switch title {
        case "Private":
            userConfig.isPublicMode.toggle()
        case "Compass":
            toggleSensor(.compass)
        case "Motion":
            toggleSensor(.motion)
        case "Audio":
            toggleSensor(.audio)
        case "Location":
            toggleSensor(.coordinates)
        case "Battery":
            toggleSensor(.battery)
        default:
            break
        }
        HapticManager.shared.impact(.light)
    }
    
    private func toggleSensor(_ sensor: SensorType) {
        if userConfig.enabledSensors.contains(sensor) {
            userConfig.enabledSensors.remove(sensor)
        } else {
            userConfig.enabledSensors.insert(sensor)
        }
    }
}

#Preview {
    AccountView()
} 