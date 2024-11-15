import Foundation
import AVFoundation
import Photos
import SwiftUI
import CryptoKit

enum CameraStatus: Equatable {
    case ready
    case processing
    case publishing
    case error(String)
    
    static func == (lhs: CameraStatus, rhs: CameraStatus) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready),
             (.processing, .processing),
             (.publishing, .publishing):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .ready: return ""
        case .processing: return "Processing..."
        case .publishing: return "Publishing..."
        case .error(let message): return "Error: \(message)"
        }
    }
}

class CameraService: NSObject, ObservableObject {
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var shouldShowSpinner = false
    @Published var willCapturePhoto = false
    @Published var isCameraButtonDisabled = true
    @Published var isCameraUnavailable = true
    @Published var photo: Photo?
    @Published var viewfinderImage: Image?
    @Published var capturedImageBase64: String?
    @Published var imageProperties: [String: Any]?
    @Published var isPublicMode: Bool = true {
        didSet {
            print("📱 CameraService: Mode changed from \(oldValue) to \(isPublicMode)")
        }
    }
    @Published var isPublishing = false
    @Published var publishError: String?
    @Published var status: CameraStatus = .ready
    
    private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput = AVCapturePhotoOutput()
    
    private var isConfigured = false
    private var isCaptureSessionRunning = false
    
    override init() {
        super.init()
        checkForPermissions()
    }
    
    func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isCameraUnavailable = false
            self.configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isCameraUnavailable = !granted
                    if granted {
                        self?.configureCaptureSession()
                    }
                }
            }
        default:
            self.isCameraUnavailable = true
        }
    }
    
    private func configureCaptureSession() {
        guard !isConfigured else { return }
        
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            isConfigured = true
        }
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get video device")
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            guard captureSession.canAddInput(videoDeviceInput) else {
                print("Failed to add video device input")
                return
            }
            captureSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            guard captureSession.canAddOutput(videoOutput) else {
                print("Failed to add video output")
                return
            }
            captureSession.addOutput(videoOutput)
            self.videoOutput = videoOutput
            
            if let connection = videoOutput.connection(with: .video) {
                setVideoRotation(for: connection)
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }
            
            guard captureSession.canAddOutput(photoOutput) else {
                print("Failed to add photo output")
                return
            }
            captureSession.addOutput(photoOutput)
            
            if let photoConnection = photoOutput.connection(with: .video) {
                setVideoRotation(for: photoConnection)
                if photoConnection.isVideoMirroringSupported {
                    photoConnection.isVideoMirrored = false
                }
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                self?.isCaptureSessionRunning = true
            }
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func toggleFlash() {
        flashMode = flashMode == .on ? .off : .on
    }
    
    func switchCamera() {
        guard let currentInput = videoDeviceInput else { return }
        
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
        
        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)
        
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            videoDeviceInput = newInput
            
            // Update video output connection for the new camera
            if let videoConnection = videoOutput?.connection(with: .video) {
                setVideoRotation(for: videoConnection)
                if videoConnection.isVideoMirroringSupported {
                    videoConnection.isVideoMirrored = (newPosition == .front)
                }
            }
            
            // Update photo output connection for the new camera
            if let photoConnection = photoOutput.connection(with: .video) {
                setVideoRotation(for: photoConnection)
                if photoConnection.isVideoMirroringSupported {
                    photoConnection.isVideoMirrored = (newPosition == .front)
                }
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    private func setVideoRotation(for connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // 90 degrees = portrait
        }
    }
    
    private func publishPayload(_ payload: CameraPayload) async throws {
        isPublishing = true
        defer { isPublishing = false }
        
        let url = URL(string: AppConstants.Server.publishEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(payload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: httpResponse.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: "Server error: \(errorMessage)"])
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        DispatchQueue.main.async {
            self.viewfinderImage = Image(uiImage: UIImage(cgImage: cgImage))
        }
    }
}

// First, update the payload structures
struct CameraPayload: Codable {
    let content: Content
    let sha256: String
    let eth: EthSignature
    let secp256r1: SecpSignature
    
    struct Content: Codable {
        let type: String // "public" or "private"
        let value: ContentValue
    }
    
    struct ContentValue: Codable {
        let mediadata: String?
        let metadata: [String: String]?
        let encrypted: String?
        
        // Custom encoding to handle the either/or case
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let mediadata = mediadata, let metadata = metadata {
                try container.encode(mediadata, forKey: .mediadata)
                try container.encode(metadata, forKey: .metadata)
            } else if let encrypted = encrypted {
                try container.encode(encrypted, forKey: .encrypted)
            }
        }
    }
    
    struct EthSignature: Codable {
        let pubkey: String
        let signature: String
    }
    
    struct SecpSignature: Codable {
        let pubkey: String
        let signature: String
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.status = .error(error.localizedDescription)
            }
            return
        }
        
        // Start processing immediately in background
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.status = .processing
                // Enable camera button immediately so user can take more photos while processing
                self.isCameraButtonDisabled = false
            }
            
            guard let imageData = photo.fileDataRepresentation(),
                  let originalImage = UIImage(data: imageData) else {
                await MainActor.run {
                    self.status = .error("Failed to process image")
                }
                return
            }
            
            // Process image in background
            let deviceOrientation = await MainActor.run { UIDevice.current.orientation }
            let rotatedImage = await self.rotateImage(originalImage, orientation: deviceOrientation)
            guard let jpegData = rotatedImage.jpegData(compressionQuality: 0.8) else { return }
            let base64String = jpegData.base64EncodedString()
            
            do {
                let payload = try await self.createPayload(base64String)
                
                await MainActor.run {
                    self.status = .publishing
                }
                
                try await self.publishPayload(payload)
                
                await MainActor.run {
                    self.photo = Photo(originalData: jpegData)
                    if let jsonData = try? JSONEncoder().encode(payload) {
                        self.capturedImageBase64 = String(data: jsonData, encoding: .utf8)
                    }
                    self.status = .ready
                }
            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                    print("Error processing/publishing photo: \(error)")
                }
            }
        }
    }
    
    // Add this new helper method to create the payload
    private func createPayload(_ base64String: String) async throws -> CameraPayload {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let contentValue: CameraPayload.ContentValue
        let contentType: String
        let contentToHash: String
        
        if isPublicMode {
            contentType = "public"
            let metadata = ["timestamp": timestamp]
            
            contentValue = CameraPayload.ContentValue(
                mediadata: base64String,
                metadata: metadata,
                encrypted: nil
            )
            
            let valueDict: [String: String] = [
                "mediadata": base64String,
                "metadata.timestamp": timestamp
            ]
            contentToHash = jsonToSortedQueryString(valueDict)
        } else {
            contentType = "private"
            let privateContent: [String: Any] = [
                "mediadata": base64String,
                "metadata": ["timestamp": timestamp]
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: privateContent)
            let encryptedData = try ContentKeyManager.shared.encrypt(jsonData)
            let encryptedString = encryptedData.base64EncodedString()
            
            contentValue = CameraPayload.ContentValue(
                mediadata: nil,
                metadata: nil,
                encrypted: encryptedString
            )
            
            contentToHash = encryptedString
        }
        
        // Calculate SHA256
        let contentData = contentToHash.data(using: .utf8)!
        let hash = SHA256.hash(data: contentData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Get signatures concurrently
        async let ethSignature = EthereumManager.shared.signMessage(hashString)
        let secpSignature = SecureEnclaveManager.shared.sign(contentData)?.base64EncodedString() ?? ""
        
        return CameraPayload(
            content: CameraPayload.Content(
                type: contentType,
                value: contentValue
            ),
            sha256: hashString,
            eth: CameraPayload.EthSignature(
                pubkey: EthereumManager.shared.getWalletAddress() ?? "",
                signature: try await ethSignature
            ),
            secp256r1: CameraPayload.SecpSignature(
                pubkey: SecureEnclaveManager.shared.getStoredPublicKey() ?? "",
                signature: secpSignature
            )
        )
    }
    
    // Add helper method to handle image rotation asynchronously
    private func rotateImage(_ image: UIImage, orientation: UIDeviceOrientation) async -> UIImage {
        switch orientation {
        case .landscapeLeft:
            return image.rotate(radians: -.pi/2)
        case .landscapeRight:
            return image.rotate(radians: .pi/2)
        case .portraitUpsideDown:
            return image.rotate(radians: .pi)
        default:
            return image
        }
    }
}

// Add this extension to UIImage for rotation
extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            context.translateBy(x: rotatedSize.width/2, y: rotatedSize.height/2)
            context.rotate(by: radians)
            draw(in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
            
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return rotatedImage ?? self
        }
        return self
    }
}

struct Photo: Identifiable {
    let id: String
    let originalData: Data
    
    init(id: String = UUID().uuidString, originalData: Data) {
        self.id = id
        self.originalData = originalData
    }
}

// Update the query string formatter to handle nested objects better
extension CameraService {
    private func jsonToSortedQueryString(_ json: [String: Any], prefix: String = "") -> String {
        let sortedKeys = Array(json.keys).sorted()
        return sortedKeys.compactMap { key in
            guard let value = json[key] else { return nil }
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"
            
            if let dict = value as? [String: Any] {
                return jsonToSortedQueryString(dict, prefix: fullKey)
            } else {
                let stringValue = String(describing: value)
                return "\(fullKey)=\(stringValue)"
            }
        }.joined(separator: "&")
    }
} 