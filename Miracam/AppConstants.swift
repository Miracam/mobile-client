import Foundation
import UIKit

struct AppConstants {
    struct UI {
        static let containerRadius: CGFloat = 40  // For the main container/viewfinder
        static let privateModeOuterRadius: CGFloat = 40  // For the red border overlay
        static let privateModeInnerRadius: CGFloat = 34  // For the inner mask
    }
    
    struct Server {
        static let baseURL = "https://api.miracam.xyz"
        static let publicKeyEndpoint = "\(baseURL)/public-key"
        static let nonceEndpoint = "\(baseURL)/nonce"
        static let attestKeyEndpoint = "\(baseURL)/attest-key"
        static let challengeEndpoint = "\(baseURL)/challenge"
        static let publishEndpoint = "\(baseURL)/publish"
    }
    
    struct WebView {
        static let appURL = "https://film-mono.pages.dev"
        static let walletConnectURL = "\(appURL)/connect"
        static let externalWalletURL = "\(appURL)/connect"
    }
    
    struct Keychain {
        static let accessTokenKey = "com.example.toycam.accesstoken"
        static let attestationKeyIdKey = "AttestationKeyId"
    }
    
    struct SecureEnclave {
        static let publicKeyTag = "com.example.toycam.secureenclave"
    }
    
    struct UserDefaults {
        static let usernameKey = "com.example.toycam.username"
    }
    
    struct Fonts {
        static let brandFont = "BrandFont" // Replace with your actual brand font name
        static let contentFont = "Comic Sans MS"
    }
}
