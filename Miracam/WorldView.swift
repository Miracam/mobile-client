import SwiftUI
import WebKit

struct WorldViewWebKit: UIViewRepresentable {
    @State private var urlWithPrivateKey: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        
        // Load URL with private key
        Task {
            do {
                if let privateKey = try await EthereumManager.shared.getPrivateKey() {
                    let baseURL = AppConstants.WebView.appURL
                    let urlString = "\(baseURL)?pk=0x\(privateKey)"
                    
                    if let url = URL(string: urlString) {
                        DispatchQueue.main.async {
                            let request = URLRequest(url: url)
                            webView.load(request)
                        }
                    }
                }
            } catch {
                print("Error loading private key:", error)
                // Fallback to base URL if private key loading fails
                if let url = URL(string: AppConstants.WebView.appURL) {
                    let request = URLRequest(url: url)
                    webView.load(request)
                }
            }
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WorldView: View {
    var body: some View {
        WorldViewWebKit()
            .ignoresSafeArea()
    }
}

#Preview {
    WorldView()
} 