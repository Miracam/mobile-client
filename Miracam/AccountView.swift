import SwiftUI

struct AccountView: View {
    @State private var publicKey: String = "Loading..."
    @State private var attestationKeyId: String = "Loading..."
    @State private var ethAddress: String = "Loading..."
    @State private var ethBalance: String = "Loading..."
    @State private var usdcBalance: String = "Loading..."
    @State private var testBalance: String = "Loading..."
    @State private var showCopiedAlert = false
    @State private var isRefreshing = false
    
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
                }
                .padding()
                
                Spacer()
            }
        }
        .onAppear {
            loadKeys()
            Task {
                await loadBalances()
            }
        }
        .overlay(
            ToastView(message: "Copied to clipboard", isShowing: $showCopiedAlert)
        )
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

#Preview {
    AccountView()
} 