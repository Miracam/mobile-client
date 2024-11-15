import SwiftUI

struct AccountView: View {
    @State private var publicKey: String = "Loading..."
    @State private var attestationKeyId: String = "Loading..."
    
    var body: some View {
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
                    
                    Text(publicKey)
                        .font(.system(.footnote, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.leading)
                }
                
                // Attestation Key ID Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Attestation Key ID:")
                        .font(.headline)
                    
                    Text(attestationKeyId)
                        .font(.system(.footnote, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
            
            Spacer()
        }
        .onAppear {
            loadKeys()
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