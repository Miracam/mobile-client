//
//  ContentView.swift
//  SignApp
//
//  Created by Junyao Chan on 16/11/2024.
//

import SwiftUI
import web3swift
import Web3Core
import BigInt

// Add EIP712TypedData structure and related code
struct EIP712TypedData {
    let types: [String: [TypeProperty]]
    let primaryType: String
    let domain: [String: Any]
    let message: [String: Any]
    
    struct TypeProperty {
        let name: String
        let type: String
    }
    
    var signHash: Data {
        let domainHash = hashStruct(data: domain, type: "EIP712Domain")
        let messageHash = hashStruct(data: message, type: primaryType)
        let typeHash = Data([0x19, 0x01]) + domainHash + messageHash
        return typeHash.sha3(.keccak256)
    }
    
    private func hashStruct(data: [String: Any], type: String) -> Data {
        let typeHash = encodeType(type: type).sha3(.keccak256)
        let encodedData = encodeData(data: data, type: type)
        return (typeHash + encodedData).sha3(.keccak256)
    }
    
    private func encodeType(type: String) -> Data {
        var deps = findDependencies(primaryType: type)
        deps.remove(type)
        let sorted = [type] + Array(deps).sorted()
        
        let encoded = sorted.map { t in
            let props = types[t]!.map { "\($0.type) \($0.name)" }.joined(separator: ",")
            return "\(t)(\(props))"
        }.joined()
        
        return encoded.data(using: .utf8) ?? Data()
    }
    
    private func findDependencies(primaryType: String, dependencies: Set<String> = Set()) -> Set<String> {
        var deps = dependencies
        guard let properties = types[primaryType] else { return deps }
        
        for property in properties {
            let type = property.type
            if deps.contains(type) { continue }
            if types[type] == nil { continue }
            deps.insert(type)
            deps = findDependencies(primaryType: type, dependencies: deps)
        }
        return deps
    }
    
    private func encodeData(data: [String: Any], type: String) -> Data {
        guard let properties = types[type] else { return Data() }
        
        return properties.reduce(into: Data()) { result, prop in
            if let value = data[prop.name] {
                result.append(encodeValue(value: value, type: prop.type))
            }
        }
    }
    
    private func encodeValue(value: Any, type: String) -> Data {
        if type == "string" || type == "bytes" {
            let valueData: Data
            if let stringValue = value as? String {
                valueData = stringValue.data(using: .utf8) ?? Data()
            } else if let dataValue = value as? Data {
                valueData = dataValue
            } else {
                return Data()
            }
            return valueData.sha3(.keccak256)
        }
        
        if type == "bool" {
            return (value as? Bool == true) ? Data([1]) + Data(count: 31) : Data(count: 32)
        }
        
        if type == "address" {
            if let stringValue = value as? String,
               let address = EthereumAddress(stringValue) {
                return Data(count: 12) + address.addressData // Pad to 32 bytes
            }
            return Data(count: 32)
        }
        
        if type.hasPrefix("uint") || type.hasPrefix("int") {
            if let stringValue = value as? String,
               let bigInt = BigUInt(stringValue) {
                var data = Data(count: 32)
                let bytes = bigInt.serialize()
                data.replaceSubrange((32 - bytes.count)..., with: bytes)
                return data
            }
            return Data(count: 32)
        }
        
        return Data(count: 32)
    }
}

struct EIP712Domain {
    let name: String
    let version: String
    let chainId: BigUInt
    let verifyingContract: EthereumAddress
}

struct Permit {
    let owner: EthereumAddress
    let spender: EthereumAddress
    let value: BigUInt
    let nonce: BigUInt
    let deadline: BigUInt
}

// Add this function near the top of the file, after the struct definitions
func generatePermitSignature(
    privateKey: String,
    spenderAddress: String,
    tokenAddress: String,
    amount: String,
    chainId: String,
    deadline: String = "1731755366",
    nonce: String = "0"
) -> (signature: String?, error: String?) {
    // Validate inputs
    guard let tokenAddr = EthereumAddress(tokenAddress) else {
        return (nil, "Invalid token address")
    }
    
    guard let spenderAddr = EthereumAddress(spenderAddress) else {
        return (nil, "Invalid spender address")
    }
    
    guard let amountBigUInt = BigUInt(amount) else {
        return (nil, "Invalid amount")
    }
    
    guard let deadlineBigUInt = BigUInt(deadline) else {
        return (nil, "Invalid deadline")
    }
    
    guard let nonceBigUInt = BigUInt(nonce) else {
        return (nil, "Invalid nonce")
    }
    
    do {
        // Create private key data
        let privateKeyData = Data(hex: privateKey)
        
        // Get wallet address from private key
        let keystore = try EthereumKeystoreV3(privateKey: privateKeyData, password: "")!
        guard let address = keystore.addresses?.first else {
            return (nil, "Failed to get wallet address")
        }
        
        // Create the message to sign
        let types: [String: [EIP712TypedData.TypeProperty]] = [
            "EIP712Domain": [
                .init(name: "name", type: "string"),
                .init(name: "version", type: "string"),
                .init(name: "chainId", type: "uint256"),
                .init(name: "verifyingContract", type: "address")
            ],
            "Permit": [
                .init(name: "owner", type: "address"),
                .init(name: "spender", type: "address"),
                .init(name: "value", type: "uint256"),
                .init(name: "nonce", type: "uint256"),
                .init(name: "deadline", type: "uint256")
            ]
        ]
        
        let domain: [String: Any] = [
            "name": "Token",
            "version": "1",
            "chainId": chainId,
            "verifyingContract": tokenAddr.address
        ]
        
        let message: [String: Any] = [
            "owner": address.address,
            "spender": spenderAddr.address,
            "value": amountBigUInt.description,
            "nonce": nonceBigUInt.description,
            "deadline": deadlineBigUInt.description
        ]
        
        let typedData = EIP712TypedData(
            types: types,
            primaryType: "Permit",
            domain: domain,
            message: message
        )
        
        let messageData = typedData.signHash
        
        // Sign the message using SECP256K1
        let signatureResult = SECP256K1.signForRecovery(hash: messageData, privateKey: privateKeyData)
        guard let serializedSignature = signatureResult.serializedSignature else {
            return (nil, "Failed to serialize signature")
        }
        guard let rawSignature = signatureResult.rawSignature else {
            return (nil, "Failed to get raw signature")
        }
        
        // Extract r, s from the serialized signature
        let r = serializedSignature[..<32]
        let s = serializedSignature[32...]
        
        // Calculate v (recovery ID + 27)
        let v = UInt8(rawSignature.last ?? 0) + 27
        
        // Concatenate the signature parts
        let signature = r + s + Data([v])
        
        let result = """
        Signature Components:
        v: \(v)
        r: \(r.toHexString())
        s: \(s.toHexString())
        
        Full Signature (hex):
        0x\(signature.toHexString())
        """
        
        return (result, nil)
        
    } catch {
        return (nil, "Error signing permit: \(error.localizedDescription)")
    }
}

struct ContentView: View {
    @State private var walletAddress: String = "No wallet generated"
    @State private var privateKey: String = "No private key"
    @State private var signatureResult: String = "No signature yet"
    
    // States for permit parameters with default values
    @State private var spenderAddress: String = "0x16e4ED67216A66c1D16A6b06c60C2AeC96e95D46"
    @State private var amount: String = "1000000000000000000"
    @State private var tokenAddress: String = "0x5B9b2472b0921D2b31daeed3461027485b4F1b98"
    
    // Add default private key constant
    private let defaultPrivateKey = "79ab9295afc46a88056b58eea95013522314df70b26a774125333f83c111629b"
    
    @State private var currentNonce: String = "0"
    
    // Change from @State variable to constant
    private let currentDeadline: String = "1731755366"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Wallet Section
                walletSection
                
                // Add Use Default Wallet button
                Button(action: useDefaultWallet) {
                    Text("Use Default Wallet")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                }
                
                // Permit Parameters Section
                permitParametersSection
                
                // Sign Button
                Button(action: signPermit) {
                    Text("Sign Permit")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                // Update Signature Result Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Signature Result:")
                            .font(.headline)
                        
                        if signatureResult != "No signature yet" {
                            Button(action: {
                                UIPasteboard.general.string = signatureResult
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                                    .padding(.leading)
                            }
                        }
                    }
                    Text(signatureResult)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
        }
    }
    
    private var walletSection: some View {
        VStack {
            Text("Ethereum Wallet Generator")
                .font(.title)
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Wallet Address:")
                    .font(.headline)
                Text(walletAddress)
                    .font(.body)
                    .textSelection(.enabled)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Private Key:")
                            .font(.headline)
                        Text(privateKey)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    
                    if privateKey != "No private key" && privateKey != "Error generating wallet" {
                        Button(action: {
                            UIPasteboard.general.string = privateKey
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                                .padding(.leading)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding()
            
            Button(action: generateWallet) {
                Text("Generate New Wallet")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
    
    private var permitParametersSection: some View {
        VStack(spacing: 15) {
            TextField("Token Address", text: $tokenAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            TextField("Spender Address", text: $spenderAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            TextField("Amount", text: $amount)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
            
            // Add nonce display
            HStack {
                VStack(alignment: .leading) {
                    Text("Current Nonce:")
                        .font(.headline)
                    Text(currentNonce)
                        .font(.body)
                        .textSelection(.enabled)
                }
                
                Button(action: {
                    UIPasteboard.general.string = currentNonce
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                        .padding(.leading)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Deadline display
            HStack {
                VStack(alignment: .leading) {
                    Text("Computed Deadline:")
                        .font(.headline)
                    Text(currentDeadline)
                        .font(.body)
                        .textSelection(.enabled)
                }
                
                if currentDeadline != "No deadline computed" {
                    Button(action: {
                        UIPasteboard.general.string = currentDeadline
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                            .padding(.leading)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    func generateWallet() {
        do {
            let password = ""
            let keystore = try EthereumKeystoreV3(password: password)!
            
            guard let address = keystore.addresses?.first else {
                print("Failed to get wallet address")
                return
            }
            
            let privateKeyData = try keystore.UNSAFE_getPrivateKeyData(password: password, account: address)
            
            walletAddress = address.address
            privateKey = privateKeyData.toHexString()
            
        } catch {
            print("Error generating wallet: \(error)")
            walletAddress = "Error generating wallet"
            privateKey = "Error generating wallet"
        }
    }
    
    func signPermit() {
        let (signature, error) = generatePermitSignature(
            privateKey: privateKey,
            spenderAddress: spenderAddress,
            tokenAddress: tokenAddress,
            amount: amount,
            chainId: "31337"  // You might want to make this configurable
        )
        
        if let error = error {
            signatureResult = error
        } else if let signature = signature {
            signatureResult = signature
        }
    }
    
    // Add function to use default wallet
    func useDefaultWallet() {
        do {
            let privateKeyData = Data(hex: defaultPrivateKey)
            let keystore = try EthereumKeystoreV3(privateKey: privateKeyData, password: "")!
            guard let address = keystore.addresses?.first else {
                print("Failed to get wallet address")
                return
            }
            
            walletAddress = address.address
            privateKey = defaultPrivateKey
            
        } catch {
            print("Error using default wallet: \(error)")
            walletAddress = "Error using default wallet"
            privateKey = "Error using default wallet"
        }
    }
}

#Preview {
    ContentView()
}
