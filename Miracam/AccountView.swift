import SwiftUI

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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .imageScale(.large)
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                
                Text("Account")
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 20) {
                    // SECP256R1 Key Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SECP256R1 Public Key:")
                            .font(.headline)
                        
                        HStack {
                            Text(publicKey)
                                .font(.system(.footnote, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                copyToClipboard(publicKey)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.leading)
                    }
                    
                    // Attestation Key ID Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Attestation Key ID:")
                            .font(.headline)
                        
                        HStack {
                            Text(attestationKeyId)
                                .font(.system(.footnote, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                copyToClipboard(attestationKeyId)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Ethereum Wallet Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ethereum Wallet:")
                            .font(.headline)
                        
                        HStack {
                            Text(ethAddress)
                                .font(.system(.footnote, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                copyToClipboard(ethAddress)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Balances List with Refresh Button
                        VStack(spacing: 12) {
                            HStack {
                                Text("Balances")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    Task {
                                        await refreshBalances()
                                    }
                                }) {
                                    HStack {
                                        if isRefreshing {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                    }
                                    .frame(width: 20, height: 20)
                                }
                                .disabled(isRefreshing)
                            }
                            
                            Divider()
                            
                            BalanceRow(title: "ETH Balance:", value: ethBalance)
                            Divider()
                            BalanceRow(title: "USDC Balance:", value: usdcBalance)
                            Divider()
                            BalanceRow(title: "Test Balance:", value: testBalance)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Add Content Key Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Content Key Status:")
                            .font(.headline)
                        
                        HStack {
                            Text(contentKeyStatus)
                                .font(.system(.footnote, design: .monospaced))
                            
                            Spacer()
                            
                            Button(action: {
                                testContentKey()
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            if let key = ContentKeyManager.shared.checkExistingContentKey() {
                                let keyBase64 = key.combined.base64EncodedString()
                                UIPasteboard.general.string = keyBase64
                                // Show copied alert
                                showCopiedAlert = true
                            }
                        }) {
                            Text("Export Content Key")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            showEncryptionSheet = true
                        }) {
                            Text("Test Encryption")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        if !encryptedResult.isEmpty {
                            Text("Encrypted:")
                                .font(.headline)
                            
                            HStack {
                                Text(encryptedResult)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(nil)
                                
                                Spacer()
                                
                                Button(action: {
                                    copyToClipboard(encryptedResult)
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
                                Text(decryptedResult)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(nil)
                                
                                Spacer()
                                
                                Button(action: {
                                    copyToClipboard(decryptedResult)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 20) {
                            Button(action: {
                                showSecpSigningSheet = true
                            }) {
                                Text("Test SECP Sign")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                showEthSigningSheet = true
                            }) {
                                Text("Test ETH Sign")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        
                        if !signature.isEmpty {
                            Text("Signature:")
                                .font(.headline)
                            
                            HStack {
                                Text(signature)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(nil)
                                
                                Spacer()
                                
                                Button(action: {
                                    copyToClipboard(signature)
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
                .padding()
                
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .padding(.vertical)
                    
                    Button(action: {
                        resetApp()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset App")
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .onAppear {
            loadKeys()
            Task {
                await loadBalances()
            }
            testContentKey()
        }
        .overlay(
            ToastView(message: "Copied to clipboard", isShowing: $showCopiedAlert)
        )
        .sheet(isPresented: $showSigningSheet) {
            SigningTestView(messageToSign: $messageToSign, signature: $signature)
        }
        .sheet(isPresented: $showEncryptionSheet) {
            EncryptionTestView(
                messageToEncrypt: $messageToEncrypt,
                encryptedResult: $encryptedResult,
                decryptedResult: $decryptedResult
            )
        }
        .sheet(isPresented: $showSecpSigningSheet) {
            SigningTestView(messageToSign: $messageToSign, signature: $signature)
        }
        .sheet(isPresented: $showEthSigningSheet) {
            EthereumSigningTestView()
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
        // Remove all keys
        _ = SecureEnclaveManager.shared.deleteKeys()
        _ = AttestationManager.shared.removeKeyId()
        _ = ContentKeyManager.shared.removeContentKey()
        _ = EthereumManager.shared.removeWallet()
        
        // Reset initial setup flag
        hasCompletedInitialSetup = false
        
        // Exit app
        exit(0)
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

#Preview {
    AccountView()
} 