import Foundation
import AVFoundation
import Photos
import SwiftUI
import CryptoKit

class CameraService: NSObject, ObservableObject {
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var shouldShowAlertView = false
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
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("Failed to get image data")
            return
        }
        
        // Get the device orientation
        let deviceOrientation = UIDevice.current.orientation
        print("📱 Device orientation: \(deviceOrientation.rawValue)")
        
        // Create UIImage and rotate based on device orientation
        if let originalImage = UIImage(data: imageData) {
            let rotatedImage: UIImage
            
            switch deviceOrientation {
            case .landscapeLeft:
                rotatedImage = originalImage.rotate(radians: -.pi/2)
            case .landscapeRight:
                rotatedImage = originalImage.rotate(radians: .pi/2)
            case .portraitUpsideDown:
                rotatedImage = originalImage.rotate(radians: .pi)
            case .portrait, .faceUp, .faceDown, .unknown:
                rotatedImage = originalImage
            @unknown default:
                rotatedImage = originalImage
            }
            
            // Convert rotated image to JPEG data with full quality
            if let jpegData = rotatedImage.jpegData(compressionQuality: 1.0) {
                let base64String = jpegData.base64EncodedString()
                
                Task {
                    do {
                        let contentValue: CameraPayload.ContentValue
                        let contentType: String
                        var contentToHash: String
                        
                        if isPublicMode {
                            contentType = "public"
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            let metadata = ["timestamp": timestamp]
                            
                            // Create the content value for public mode
                            contentValue = CameraPayload.ContentValue(
                                mediadata: base64String,
                                metadata: metadata,
                                encrypted: nil
                            )
                            
                            // Create hash from the value object
                            let valueDict: [String: Any] = [
                                "mediadata": base64String,
                                "metadata": metadata
                            ]
                            contentToHash = jsonToSortedQueryString(valueDict)
                        } else {
                            contentType = "private"
                            let privateContent = [
                                "mediadata": base64String,
                                "metadata": ["timestamp": ISO8601DateFormatter().string(from: Date())]
                            ]
                            let jsonData = try JSONSerialization.data(withJSONObject: privateContent)
                            let encryptedData = try ContentKeyManager.shared.encrypt(jsonData)
                            let encryptedString = encryptedData.base64EncodedString()
                            
                            // Create the content value for private mode
                            contentValue = CameraPayload.ContentValue(
                                mediadata: nil,
                                metadata: nil,
                                encrypted: encryptedString
                            )
                            
                            contentToHash = encryptedString
                        }
                        
                        // Calculate SHA256 and convert to hex string
                        let contentData = contentToHash.data(using: .utf8)!
                        let hash = SHA256.hash(data: contentData)
                        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                        
                        // Get signatures
                        let ethSignature = try await EthereumManager.shared.signMessage(hashString)
                        let secpSignature = SecureEnclaveManager.shared.sign(contentData)?.base64EncodedString() ?? ""
                        
                        let payload = CameraPayload(
                            content: CameraPayload.Content(
                                type: contentType,
                                value: contentValue
                            ),
                            sha256: hashString,
                            eth: CameraPayload.EthSignature(
                                pubkey: EthereumManager.shared.getWalletAddress() ?? "",
                                signature: ethSignature
                            ),
                            secp256r1: CameraPayload.SecpSignature(
                                pubkey: SecureEnclaveManager.shared.getStoredPublicKey() ?? "",
                                signature: secpSignature
                            )
                        )
                        
                        // Convert final payload to JSON string
                        let jsonEncoder = JSONEncoder()
                        jsonEncoder.outputFormatting = .prettyPrinted
                        let finalJsonData = try jsonEncoder.encode(payload)
                        
                        if let jsonString = String(data: finalJsonData, encoding: .utf8) {
                            do {
                                // Publish the payload
                                try await publishPayload(payload)
                                
                                await MainActor.run {
                                    self.photo = Photo(originalData: jpegData)
                                    self.capturedImageBase64 = jsonString
                                }
                            } catch {
                                await MainActor.run {
                                    self.publishError = error.localizedDescription
                                    print("Publishing error: \(error.localizedDescription)")
                                }
                            }
                        }
                    } catch {
                        print("Error creating payload: \(error)")
                    }
                }
            } else {
                print("Failed to convert rotated image to JPEG")
            }
        } else {
            print("Failed to create UIImage from captured data")
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