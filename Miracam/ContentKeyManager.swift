import Foundation
import CryptoKit
import WebKit
import SwiftUI

enum ContentKeyError: Error {
    case keyGenerationFailed
    case keyStorageFailed
    case keyRetrievalFailed
    case noKeyFound
    case invalidKeyData
}

struct ContentKeyData {
    let key: SymmetricKey
    let nonce: AES.GCM.Nonce
    
    var combined: Data {
        // Combine key and nonce for storage
        let keyData = key.withUnsafeBytes { Data($0) }
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        return keyData + nonceData
    }
    
    static func fromCombinedData(_ data: Data) throws -> ContentKeyData {
        // AES-256 key is 32 bytes, GCM nonce is 12 bytes
        guard data.count == 44 else {
            throw ContentKeyError.invalidKeyData
        }
        
        let keyData = data.prefix(32)
        let nonceData = data.suffix(12)
        
        let key = SymmetricKey(data: keyData)
        guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw ContentKeyError.invalidKeyData
        }
        
        return ContentKeyData(key: key, nonce: nonce)
    }
}

// Add the Lit Protocol encryption result structure
struct LitEncryptionResult: Codable {
    let ciphertext: String
    let dataToEncryptHash: String
}

class ContentKeyManager: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = ContentKeyManager()
    
    private let keychainService = "com.miracam.contentkey"
    @Published var webViewLoadingStatus = "Initializing..."
    @Published var isWebViewReady = false
    private var webView: WKWebView?
    private var encryptionCompletion: ((Result<LitEncryptionResult, Error>) -> Void)?
    
    private enum KeychainKey {
        static let contentKey = "content_key"
    }
    
    private override init() {
        super.init()
        // Don't setup WebView immediately
    }
    
    /// Gets or creates a content key with Lit Protocol encryption
    /// - Returns: Tuple containing the ContentKeyData and its Lit-encrypted version
    func getOrCreateContentKey() async throws -> (ContentKeyData, LitEncryptionResult) {
        if let existingKey = checkExistingContentKey() {
            // If we have an existing key, create a dummy LitEncryptionResult
            // This is just to maintain the API contract
            return (existingKey, LitEncryptionResult(
                ciphertext: "existing_key",
                dataToEncryptHash: "existing_key_hash"
            ))
        }
        
        // Only setup WebView and Lit Protocol when we need to create a new key
        if webView == nil {
            setupWebView()
            
            // Wait for WebView to be ready
            let startTime = Date()
            let timeout = TimeInterval(10) // 10 seconds timeout
            
            while !isWebViewReady {
                if Date().timeIntervalSince(startTime) > timeout {
                    throw NSError(domain: "LitProtocol", code: 1, 
                                userInfo: [NSLocalizedDescriptionKey: "WebView timeout"])
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            // Get Ethereum private key and setup Lit
            guard let privateKey = try await EthereumManager.shared.getPrivateKey() else {
                throw NSError(domain: "LitProtocol", code: 2, 
                            userInfo: [NSLocalizedDescriptionKey: "No Ethereum private key available"])
            }
            
            try await setupLit(privateKeyHex: privateKey)
        }
        
        // Generate and store new key
        let (newKey, litEncryptedKey) = try await generateContentKey()
        try storeContentKey(newKey)
        return (newKey, litEncryptedKey)
    }
    
    // MARK: - WebView Setup
    private func setupWebView() {
        print("🔵 ContentKeyManager: Setting up WebView")
        
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Add message handlers
        contentController.add(self, name: "encryptionHandler")
        contentController.add(self, name: "jsMessageHandler")
        contentController.add(self, name: "litSetupHandler")
        
        // Add console.log interceptor
        let consoleScript = WKUserScript(
            source: """
            console.log = (function(originalLog) {
                return function(...args) {
                    window.webkit.messageHandlers.jsMessageHandler.postMessage({
                        type: 'log',
                        message: args.map(arg => 
                            typeof arg === 'object' ? JSON.stringify(arg) : String(arg)
                        ).join(' ')
                    });
                    originalLog.apply(console, args);
                };
            })(console.log);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(consoleScript)
        
        configuration.userContentController = contentController
        
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
            let htmlUrl = URL(fileURLWithPath: htmlPath)
            let baseUrl = htmlUrl.deletingLastPathComponent()
            
            do {
                let htmlContent = try String(contentsOf: htmlUrl, encoding: .utf8)
                webView.loadHTMLString(htmlContent, baseURL: baseUrl)
            } catch {
                print("❌ Failed to load HTML content: \(error)")
                webViewLoadingStatus = "Error: Failed to load HTML content"
            }
        }
        
        self.webView = webView
    }
    
    // MARK: - WebView Delegates
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ ContentKeyManager: WebView finished loading")
        webViewLoadingStatus = "Page loaded"
        isWebViewReady = true
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "encryptionHandler":
            handleEncryptionMessage(message)
        case "litSetupHandler":
            if let dict = message.body as? [String: Any] {
                let success = dict["success"] as? Bool ?? false
                let error = dict["error"] as? String
                setupCompletionHandler?(success, error)
            }
        case "jsMessageHandler":
            if let dict = message.body as? [String: Any],
               let type = dict["type"] as? String,
               let messageText = dict["message"] as? String {
                print("📱 JS \(type): \(messageText)")
            }
        default:
            print("📨 Unknown message handler: \(message.name)")
        }
    }
    
    private func handleEncryptionMessage(_ message: WKScriptMessage) {
        guard let completion = encryptionCompletion else { return }
        
        if let dict = message.body as? [String: Any],
           let success = dict["success"] as? Bool {
            if success {
                if let result = dict["result"] as? String,
                   let jsonData = result.data(using: .utf8) {
                    do {
                        let encryptionResult = try JSONDecoder().decode(LitEncryptionResult.self, from: jsonData)
                        completion(.success(encryptionResult))
                    } catch {
                        completion(.failure(error))
                    }
                }
            } else {
                let error = dict["error"] as? String ?? "Unknown error"
                completion(.failure(NSError(domain: "LitProtocol", code: 6, 
                                         userInfo: [NSLocalizedDescriptionKey: error])))
            }
        }
        
        encryptionCompletion = nil
    }
    
    // MARK: - Content Key Management with Lit Protocol
    /// Generates a new AES-GCM key and encrypts it with Lit Protocol
    /// - Returns: Tuple containing the ContentKeyData and its Lit-encrypted version
    private func generateContentKey() async throws -> (ContentKeyData, LitEncryptionResult) {
        // Generate a random AES-256 key
        let key = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let contentKeyData = ContentKeyData(key: key, nonce: nonce)
        
        // Encrypt the content key with Lit Protocol
        let litEncryptedKey = try await encryptWithLitProtocol(contentKeyData.combined.base64EncodedString())
        
        return (contentKeyData, litEncryptedKey)
    }
    
    private func encryptWithLitProtocol(_ message: String) async throws -> LitEncryptionResult {
        return try await withCheckedThrowingContinuation { continuation in
            guard isWebViewReady else {
                continuation.resume(throwing: NSError(domain: "LitProtocol", code: 1, 
                                                   userInfo: [NSLocalizedDescriptionKey: "WebView not ready"]))
                return
            }
            
            encryptionCompletion = { result in
                continuation.resume(with: result)
            }
            
            let script = """
                try {
                    window.executeEncrypt(
                        '\(message)',
                        function(result) {
                            window.webkit.messageHandlers.encryptionHandler.postMessage({
                                success: true,
                                result: result
                            });
                        }
                    );
                    null;
                } catch (error) {
                    window.webkit.messageHandlers.encryptionHandler.postMessage({
                        success: false,
                        error: error.toString()
                    });
                    null;
                }
            """
            
            webView?.evaluateJavaScript(script) { _, error in
                if let error = error {
                    self.encryptionCompletion?(.failure(error))
                    self.encryptionCompletion = nil
                }
            }
        }
    }
    
    /// Checks if a content key exists for the current Ethereum wallet
    /// - Returns: The existing content key if found
    func checkExistingContentKey() -> ContentKeyData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.contentKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let keyData = result as? Data,
              let contentKeyData = try? ContentKeyData.fromCombinedData(keyData) else {
            return nil
        }
        
        return contentKeyData
    }
    
    /// Stores the content key in the keychain
    /// - Parameter keyData: The key data to store
    func storeContentKey(_ keyData: ContentKeyData) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.contentKey,
            kSecValueData as String: keyData.combined
        ]
        
        // First, try to delete any existing key
        SecItemDelete(query as CFDictionary)
        
        // Then add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw ContentKeyError.keyStorageFailed
        }
    }
    
    /// Encrypts data using the content key
    /// - Parameter data: The data to encrypt
    /// - Returns: The encrypted data
    func encrypt(_ data: Data) async throws -> Data {
        let (keyData, _) = try await getOrCreateContentKey() // Destructure the tuple
        let sealedBox = try AES.GCM.seal(data,
                                        using: keyData.key,
                                        nonce: keyData.nonce)
        return sealedBox.combined!
    }
    
    /// Decrypts data using the content key
    /// - Parameter encryptedData: The data to decrypt
    /// - Returns: The decrypted data
    func decrypt(_ encryptedData: Data) async throws -> Data {
        let (keyData, _) = try await getOrCreateContentKey() // Destructure the tuple
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: keyData.key)
    }
    
    /// Removes the content key from the keychain
    /// - Returns: True if the key was successfully removed, false otherwise
    func removeContentKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.contentKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Sets up Lit Protocol with the given Ethereum private key
    /// - Parameter privateKeyHex: The Ethereum private key in hexadecimal format
    func setupLit(privateKeyHex: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard isWebViewReady else {
                continuation.resume(throwing: NSError(domain: "LitProtocol", code: 1, 
                                                   userInfo: [NSLocalizedDescriptionKey: "WebView not ready"]))
                return
            }
            
            let script = """
                (async function() {
                    try {
                        await window.setupLit('\(privateKeyHex)');
                        // Signal completion through the dedicated handler
                        window.webkit.messageHandlers.litSetupHandler.postMessage({
                            success: true,
                            message: 'Lit setup completed'
                        });
                    } catch (error) {
                        console.error('Setup Lit error:', error);
                        window.webkit.messageHandlers.litSetupHandler.postMessage({
                            success: false,
                            error: error.toString()
                        });
                    }
                })();
                // Return null to avoid Promise issues
                null;
            """
            
            print("🔵 ContentKeyManager: Executing setupLit script")
            
            // Add handler for setup completion
            self.setupCompletionHandler = { success, error in
                if success {
                    print("✅ ContentKeyManager: Lit setup successful")
                    continuation.resume(returning: ())
                } else {
                    let setupError = error ?? "Unknown setup error"
                    print("❌ ContentKeyManager: Failed to setup Lit: \(setupError)")
                    continuation.resume(throwing: NSError(domain: "LitProtocol", code: 3,
                                                       userInfo: [NSLocalizedDescriptionKey: setupError]))
                }
                // Clear the completion handler
                self.setupCompletionHandler = nil
            }
            
            webView?.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("❌ ContentKeyManager: Failed to execute setup script: \(error)")
                    self.setupCompletionHandler?(false, error.localizedDescription)
                }
                // Success case will be handled by message handler
            }
        }
    }
    
    // Add property for setup completion handler
    private var setupCompletionHandler: ((Bool, String?) -> Void)?
    
    // Add this method to ContentKeyManager
    func getWebView() -> WKWebView? {
        return webView
    }
} 