import Foundation
import web3swift
import Web3Core
import BigInt

enum EthereumError: Error {
    case walletCreationFailed
    case walletStorageFailed
    case noWalletFound
    case invalidAddress
    case web3InitFailed
    case contractError
    case balanceError
}

class EthereumManager {
    static let shared = EthereumManager()
    
    private let keychainService = "com.miracam.ethereum"
    private let encryptionKey = UUID().uuidString
    private let baseRPCUrl = "https://mainnet.base.org"
    
    private enum KeychainKey {
        static let privateKey = "ethereum_private_key"
        static let address = "ethereum_address"
    }
    
    private enum TokenContract {
        static let usdc = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
        static let testToken = "0x067AaD821d4d42d536DC82A0c83Da21b84f4D596"
    }
    
    private init() {}
    
    func hasWallet() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.privateKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }
    
    func createOrLoadWallet() async throws -> EthereumAddress {
        if hasWallet() {
            return try getStoredWallet()
        } else {
            return try createNewWallet()
        }
    }
    
    private func createNewWallet() throws -> EthereumAddress {
        guard let keystore = try? EthereumKeystoreV3(password: encryptionKey),
              let address = keystore.addresses?.first else {
            throw EthereumError.walletCreationFailed
        }
        
        guard let privateKey = try? keystore.UNSAFE_getPrivateKeyData(password: encryptionKey, account: address) else {
            throw EthereumError.walletCreationFailed
        }
        
        try storeWalletData(privateKey: privateKey, address: address)
        return address
    }
    
    private func storeWalletData(privateKey: Data, address: EthereumAddress) throws {
        let privateKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.privateKey,
            kSecValueData as String: privateKey
        ]
        
        let addressQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.address,
            kSecValueData as String: address.address.data(using: .utf8)!
        ]
        
        SecItemDelete(privateKeyQuery as CFDictionary)
        SecItemDelete(addressQuery as CFDictionary)
        
        let privateKeyStatus = SecItemAdd(privateKeyQuery as CFDictionary, nil)
        let addressStatus = SecItemAdd(addressQuery as CFDictionary, nil)
        
        guard privateKeyStatus == errSecSuccess && addressStatus == errSecSuccess else {
            throw EthereumError.walletStorageFailed
        }
    }
    
    private func getStoredWallet() throws -> EthereumAddress {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.privateKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let privateKeyData = result as? Data,
              let keystore = try? EthereumKeystoreV3(privateKey: privateKeyData, password: encryptionKey),
              let address = keystore.addresses?.first else {
            throw EthereumError.noWalletFound
        }
        
        return address
    }
    
    func getWalletAddress() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.address,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let addressData = result as? Data,
              let address = String(data: addressData, encoding: .utf8) else {
            return nil
        }
        
        return address
    }
    
    func getBalances() async throws -> (eth: String, usdc: String, test: String) {
        let eth = try await getETHBalance()
        let usdc = try await getTokenBalance(tokenContract: TokenContract.usdc)
        let test = try await getTokenBalance(tokenContract: TokenContract.testToken)
        return (eth, usdc, test)
    }
    
    private func getETHBalance() async throws -> String {
        guard let address = getWalletAddress(),
              let ethereumAddress = EthereumAddress(address) else {
            throw EthereumError.invalidAddress
        }
        
        guard let web3 = try? await Web3.new(URL(string: baseRPCUrl)!) else {
            throw EthereumError.web3InitFailed
        }
        
        let balanceWei = try await web3.eth.getBalance(for: ethereumAddress)
        let divisor = BigUInt(10).power(18)
        let balanceETH = Double(balanceWei) / Double(divisor)
        
        return String(format: "%.4f", balanceETH)
    }
    
    private func getTokenBalance(tokenContract: String) async throws -> String {
        guard let address = getWalletAddress(),
              let ethereumAddress = EthereumAddress(address),
              let contractAddress = EthereumAddress(tokenContract) else {
            throw EthereumError.invalidAddress
        }
        
        guard let web3 = try? await Web3.new(URL(string: baseRPCUrl)!) else {
            throw EthereumError.web3InitFailed
        }
        
        let erc20ABI = """
        [{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"},
         {"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]
        """
        
        guard let contract = web3.contract(erc20ABI, at: contractAddress) else {
            throw EthereumError.contractError
        }
        
        let decimalsResult = try await contract.createReadOperation("decimals")!.callContractMethod()
        guard let decimals = decimalsResult["0"] as? BigUInt else {
            throw EthereumError.balanceError
        }
        
        let balanceResult = try await contract.createReadOperation("balanceOf", parameters: [ethereumAddress] as [AnyObject])!.callContractMethod()
        guard let balance = balanceResult["0"] as? BigUInt else {
            throw EthereumError.balanceError
        }
        
        let divisor = BigUInt(10).power(Int(decimals))
        let balanceDecimal = Double(balance) / Double(divisor)
        
        return String(format: "%.4f", balanceDecimal)
    }
    
    func signMessage(_ message: String) async throws -> String {
        // Get stored private key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: KeychainKey.privateKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let privateKeyData = result as? Data else {
            throw EthereumError.noWalletFound
        }
        
        // Create keystore from private key
        guard let keystore = try? EthereumKeystoreV3(privateKey: privateKeyData, password: encryptionKey),
              let address = keystore.addresses?.first else {
            throw EthereumError.walletCreationFailed
        }
        
        // Convert message to data
        let messageData = message.data(using: .utf8)!
        
        // Sign the message
        guard let signature = try? Web3Signer.signPersonalMessage(messageData, keystore: keystore, account: address, password: encryptionKey) else {
            throw EthereumError.contractError
        }
        
        return signature.toHexString()
    }
} 