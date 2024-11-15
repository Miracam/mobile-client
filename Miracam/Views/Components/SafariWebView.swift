import SwiftUI
import WebKit

struct SafariWebView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = WebViewCoordinator()
    let onCompletion: (Bool) -> Void
    
    var body: some View {
        NavigationView {
            WebView(url: url, coordinator: coordinator)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                            onCompletion(false)
                        }
                    }
                }
        }
        .onChange(of: coordinator.shouldDismiss) { oldValue, newValue in
            if newValue {
                dismiss()
                onCompletion(true)
            }
        }
    }
}

class WebViewCoordinator: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var shouldDismiss = false
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("📨 Received message from web app")
        print("Raw message body: \(message.body)")
        
        guard let messageString = message.body as? String else {
            print("❌ Message body is not a string")
            return
        }
        
        print("📝 Message string: \(messageString)")
        
        guard let decodedString = messageString.removingPercentEncoding else {
            print("❌ Failed to decode percent encoding")
            return
        }
        
        print("🔓 Decoded string: \(decodedString)")
        
        guard let jsonData = decodedString.data(using: .utf8) else {
            print("❌ Failed to convert string to data")
            return
        }
        
        guard let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse JSON payload")
            return
        }
        
        print("📦 Parsed payload: \(payload)")
        
        guard let type = payload["type"] as? String else {
            print("❌ No type field in payload")
            return
        }
        
        print("🏷 Message type: \(type)")
        
        switch type {
        case "login_success":
            print("🔑 Handling login success")
            handleLoginSuccess(webView: message.webView)
            
        case "wallet_signed":
            print("✍️ Handling wallet signature")
            handleWalletSigned(payload: payload, webView: message.webView)
            
        case "registration_complete":
            print("🎉 Registration Complete")
            handleRegistrationComplete(payload: payload)
            
        case "get_eth_private_key":
            print("🔐 Handling get ETH private key request")
            handleGetEthPrivateKey(webView: message.webView)
            
        default:
            print("❓ Unknown message type: \(type)")
        }
    }
    
    private func handleLoginSuccess(webView: WKWebView?) {
        print("🏁 Starting handleLoginSuccess")
        Task {
            // 1. Get our Ethereum address
            guard let ethAddress = EthereumManager.shared.getWalletAddress() else {
                print("❌ No ETH address available")
                return
            }
            print("📍 Got ETH address: \(ethAddress)")
            
            // 2. Get our SECP public key
            guard let secpPublicKey = SecureEnclaveManager.shared.getStoredPublicKey() else {
                print("❌ No SECP public key available")
                return
            }
            print("🔑 Got SECP public key: \(secpPublicKey)")
            
            // 3. Get username
            let username = SetupManager.shared.getStoredUsername() ?? "unnamed"
            print("👤 Got username: \(username)")
            
            // 4. Get device info
            let deviceInfo = UIDevice.current.name
            print("📱 Got device info: \(deviceInfo)")
            
            // Create user info payload
            let userInfo: [String: Any] = [
                "username": username,
                "ethereumAddress": ethAddress,
                "secpPublicKey": secpPublicKey,
                "deviceInfo": deviceInfo
            ]
            print("📦 Created user info payload: \(userInfo)")
            
            // Encode and send back to web app
            if let jsonData = try? JSONSerialization.data(withJSONObject: userInfo),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let encodedString = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let jsCall = "window.receiveUserInfo('\(encodedString)')"
                print("📤 Sending JS call: \(jsCall)")
                
                await MainActor.run {
                    webView?.evaluateJavaScript(jsCall) { result, error in
                        if let error = error {
                            print("❌ JS evaluation error: \(error)")
                        } else {
                            print("✅ JS call successful, result: \(String(describing: result))")
                        }
                    }
                }
            } else {
                print("❌ Failed to encode user info to JSON")
            }
        }
    }
    
    private func handleWalletSigned(payload: [String: Any], webView: WKWebView?) {
        print("🏁 Starting handleWalletSigned")
        print("📦 Received payload: \(payload)")
        
        Task {
            guard let externalSignature = payload["signature"] as? String,
                  let originalMessage = payload["message"] as? String else {
                print("❌ Missing signature or message in payload")
                return
            }
            
            print("📝 Original message: \(originalMessage)")
            print("✍️ External signature: \(externalSignature)")
            
            do {
                // 1. Sign with our Ethereum wallet
                print("🔐 Signing with ETH wallet...")
                let ethSignature = try await EthereumManager.shared.signMessage(externalSignature)
                print("✅ ETH signature: \(ethSignature)")
                
                // 2. Sign with SECP
                print("🔐 Signing with SECP...")
                guard let messageData = externalSignature.data(using: .utf8),
                      let secpSignature = SecureEnclaveManager.shared.sign(messageData) else {
                    print("❌ SECP signing failed")
                    return
                }
                print("✅ SECP signature: \(secpSignature.base64EncodedString())")
                
                // Create response payload
                let signatureResponse: [String: Any] = [
                    "originalMessage": originalMessage,
                    "externalSignature": externalSignature,
                    "ethSignature": ethSignature,
                    "secpSignature": secpSignature.base64EncodedString()
                ]
                print("📦 Created signature response: \(signatureResponse)")
                
                // Encode and send back to web app
                if let jsonData = try? JSONSerialization.data(withJSONObject: signatureResponse),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let encodedString = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let jsCall = "window.receiveWebkitSignature('\(encodedString)')"
                    print("📤 Sending JS call: \(jsCall)")
                    
                    await MainActor.run {
                        webView?.evaluateJavaScript(jsCall) { result, error in
                            if let error = error {
                                print("❌ JS evaluation error: \(error)")
                            } else {
                                print("✅ JS call successful, result: \(String(describing: result))")
                            }
                        }
                    }
                } else {
                    print("❌ Failed to encode signature response to JSON")
                }
            } catch {
                print("❌ Error during signing: \(error)")
            }
        }
    }
    
    private func handleRegistrationComplete(payload: [String: Any]) {
        print("📦 Registration completion payload:", payload)
        
        if let receipt = payload["receipt"] as? [String: Any] {
            print("📝 Server Receipt:", receipt)
        }
        if let originalMessage = payload["originalMessage"] as? String {
            print("📄 Original Message:", originalMessage)
        }
        
        // Notify to dismiss webview and show alert
        DispatchQueue.main.async { [weak self] in
            self?.shouldDismiss = true
        }
    }
    
    private func handleGetEthPrivateKey(webView: WKWebView?) {
        print("🏁 Starting handleGetEthPrivateKey")
        Task {
            do {
                guard let privateKey = try await EthereumManager.shared.getPrivateKey() else {
                    print("❌ No private key available")
                    return
                }
                
                let response: [String: Any] = [
                    "privateKey": privateKey
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: response),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let encodedString = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let jsCall = "window.receiveEthPrivateKey('\(encodedString)')"
                    print("📤 Sending JS call: \(jsCall)")
                    
                    await MainActor.run {
                        webView?.evaluateJavaScript(jsCall) { result, error in
                            if let error = error {
                                print("❌ JS evaluation error: \(error)")
                            } else {
                                print("✅ JS call successful, result: \(String(describing: result))")
                            }
                        }
                    }
                }
            } catch {
                print("❌ Error getting private key: \(error)")
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let coordinator: WebViewCoordinator
    
    func makeCoordinator() -> WebViewCoordinator {
        coordinator
    }
    
    func makeUIView(context: Context) -> WKWebView {
        print("🏗 Creating WKWebView")
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        print("📱 Adding message handler")
        userContentController.add(context.coordinator, name: "webViewMessageHandler")
        configuration.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        print("🌐 Setting custom user agent")
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1 MIRAcam/1.0"
        
        print("🔄 Loading URL: \(url)")
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // No update needed
    }
} 