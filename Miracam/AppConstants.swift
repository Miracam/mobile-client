import Foundation

struct AppConstants {
    struct Server {
        static let baseURL = "https://toyapi1.notum.one"
        static let publicKeyEndpoint = "\(baseURL)/public-key"
        static let nonceEndpoint = "\(baseURL)/nonce"
        static let attestKeyEndpoint = "\(baseURL)/attest-key"
        static let challengeEndpoint = "\(baseURL)/challenge"
        static let publishEndpoint = "\(baseURL)/publish"
    }
    
    struct WebView {
        static let walletConnectURL = "https://toyweb1.notum.one/connect"
        static let appURL = "https://toyweb1.notum.one"
    }
    
    struct Keychain {
        static let accessTokenKey = "com.example.toycam.accesstoken"
        static let attestationKeyIdKey = "AttestationKeyId"
    }
    
    struct SecureEnclave {
        static let publicKeyTag = "com.example.toycam.secureenclave"
    }
}
