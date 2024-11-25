import Foundation
import AVFoundation
import Photos
import SwiftUI
import CryptoKit
import Combine
import web3swift
import Web3Core
import BigInt
import CoreLocation

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
    @Published var isPublicMode: Bool = UserConfiguration.shared.isPublicMode {
        didSet {
            print("📱 CameraService: Mode changed from \(oldValue) to \(isPublicMode)")
            NotificationCenter.default.post(name: .publicModeDidChange, object: isPublicMode)
        }
    }
    @Published var isPublishing = false
    @Published var publishError: String?
    @Published var status: CameraStatus = .ready
    @Published var sensorManager = SensorDataManager()
    @Published var lastMetadata: [String: Any]?
    
    private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput = AVCapturePhotoOutput()
    
    private var isConfigured = false
    private var isCaptureSessionRunning = false
    
    private var audioSession: AVAudioSession?
    
    private var publishingHapticTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        checkForPermissions()
        sensorManager.startUpdates()
        
        UserConfiguration.shared.$isPublicMode
            .sink { [weak self] newValue in
                if self?.isPublicMode != newValue {
                    self?.isPublicMode = newValue
                }
            }
            .store(in: &cancellables)
        
        if SecureEnclaveManager.shared.getStoredPublicKey() == nil {
            SecureEnclaveManager.shared.generateAndStoreKey { success, _ in
                if !success {
                    print("Failed to generate secure enclave keys")
                }
            }
        }
    }
    
    deinit {
        sensorManager.stopUpdates()
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
        
        // Configure audio session to allow haptics
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth])
            if #available(iOS 13.0, *) {
                try audioSession?.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
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
        // Initial shutter haptic
        HapticManager.shared.impact(.medium)
        
        // Start heartbeat haptics after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startPublishingHaptics()
        }
        
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
    
    private func startPublishingHaptics() {
        // Clear any existing timer
        publishingHapticTimer?.invalidate()
        
        // First heartbeat immediately
        playHeartbeatHaptic()
        
        // Create a new timer that fires every 1.5 seconds for the heartbeat pattern
        publishingHapticTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.playHeartbeatHaptic()
        }
    }
    
    private func playHeartbeatHaptic() {
        // First beat
        HapticManager.shared.impact(.soft)
        // Second beat after 0.15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            HapticManager.shared.impact(.soft)
        }
    }
    
    private func stopPublishingHaptics() {
        publishingHapticTimer?.invalidate()
        publishingHapticTimer = nil
        // Play stronger completion haptic
        HapticManager.shared.notification(.success)
    }
    
    private func uploadPayload(_ payload: CameraPayload) async throws -> (owner: String, url: String) {
        let uploadUrl = URL(string: "\(AppConstants.Server.baseURL)/upload")!
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try jsonEncoder.encode(payload)
        request.httpBody = jsonData
        
        // print("📤 Upload Request: \(String(data: jsonData, encoding: .utf8) ?? "")")
        print("📤 Uploading")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        // print("📥 Upload Response: \(String(data: data, encoding: .utf8) ?? "")")
        
        print("📥 Uploaded")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: httpResponse.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: "Upload error: \(errorMessage)"])
        }
        
        // Parse the upload response
        guard let uploadResponse = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload response format"])
        }
        
        return (owner: uploadResponse.owner, url: uploadResponse.url)
    }
    
    private func publishWithSignature(owner: String, url: String) async throws -> Bool {
        // Create query string for signing
        let message = "owner=\(owner)&url=\(url)"
        print("📝 Message to sign: \(message)")
        
        // Sign the message using SecureEnclave
        guard let messageData = message.data(using: .utf8),
              let signature = SecureEnclaveManager.shared.sign(messageData),
              let secpPublicKey = SecureEnclaveManager.shared.getStoredPublicKey() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sign message"])
        }
        
        // Generate permit signature
        let permitSig = try await generatePermitSignature()
        
        // Create publish payload with permit
        let publishPayload = PublishPayload(
            owner: owner,
            url: url,
            message: message,
            signature: signature.base64EncodedString(),
            secp256r1_pubkey: secpPublicKey,
            permit: PublishPayload.PermitData(
                signature: permitSig.signature,
                nonce: permitSig.nonce.description,
                deadline: permitSig.deadline.description
            )
        )
        
        // Send publish request
        let publishUrl = URL(string: AppConstants.Server.publishEndpoint)!
        var request = URLRequest(url: publishUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try jsonEncoder.encode(publishPayload)
        request.httpBody = jsonData
        
        // print("📤 Publish Request: \(String(data: jsonData, encoding: .utf8) ?? "")")
        print("📤 Publishing")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        // print("📥 Publish Response: \(String(data: data, encoding: .utf8) ?? "")")
        print("📥 Published")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: httpResponse.statusCode, 
                         userInfo: [NSLocalizedDescriptionKey: "Publish error: \(errorMessage)"])
        }
        
        // Parse the publish response
        guard let publishResponse = try? JSONDecoder().decode(PublishResponse.self, from: data) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid publish response format"])
        }
        
        return publishResponse.success
    }
    
    private func publishPayload(_ payload: CameraPayload) async throws {
        isPublishing = true
        
        do {
            // Step 1: Upload
            let (owner, url) = try await uploadPayload(payload)
            
            // Step 2: Publish with signature
            let success = try await publishWithSignature(owner: owner, url: url)
            
            if !success {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server rejected publish request"])
            }
            
            isPublishing = false
            stopPublishingHaptics()
        } catch {
            isPublishing = false
            stopPublishingHaptics()
            throw error
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
        let metadata: String?
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
                self.stopPublishingHaptics()
            }
            return
        }
        
        // Generate photo ID at the start
        let photoId = UUID().uuidString
        
        // Start processing immediately in background
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Update initial status
            await PhotoManager.shared.updatePhotoStatus(id: photoId, status: .processing)
            
            await MainActor.run {
                self.status = .processing
                self.isCameraButtonDisabled = false
            }
            
            guard let imageData = photo.fileDataRepresentation(),
                  let originalImage = UIImage(data: imageData) else {
                self.status = .error("Failed to process image")
                await PhotoManager.shared.updatePhotoStatus(id: photoId, status: .error("Failed to process image"))
                return
            }
            
            // Store metadata in imageProperties for later use
            let _ = extractImageMetadata(from: imageData)
            let deviceOrientation = await MainActor.run { UIDevice.current.orientation }
            let rotatedImage = await self.rotateImage(originalImage, orientation: deviceOrientation)
            
            // Get base64 string first
            guard let jpegData = rotatedImage.jpegData(compressionQuality: 0.8) else {
                self.status = .error("Failed to compress image")
                await PhotoManager.shared.updatePhotoStatus(id: photoId, status: .error("Failed to compress image"))
                return
            }
            
            let base64String = jpegData.base64EncodedString()
            
            // Create initial payload with the base64String
            let initialPayload = CameraPayload(
                content: CameraPayload.Content(
                    type: self.isPublicMode ? "public" : "private",
                    value: CameraPayload.ContentValue(
                        mediadata: base64String,
                        metadata: "{}",
                        encrypted: nil
                    )
                ),
                sha256: "",
                eth: CameraPayload.EthSignature(pubkey: "", signature: ""),
                secp256r1: CameraPayload.SecpSignature(pubkey: "", signature: "")
            )
            
            // Save to storage immediately to show in grid
            do {
                print("💾 Saving initial photo...")
                try await PhotoManager.shared.savePhoto(from: initialPayload, thumbnail: rotatedImage, withId: photoId)
                print("✅ Initial photo saved successfully")
            } catch {
                print("❌ Error saving initial photo to storage: \(error)")
                print("Payload: \(try? JSONEncoder().encode(initialPayload))")
            }
            
            // Continue with actual processing
            do {
                let payload = try await self.createPayload(base64String)
                
                // Update storage with complete payload
                try await PhotoManager.shared.savePhoto(from: payload, thumbnail: rotatedImage, withId: photoId)
                
                // Then start publishing
                await PhotoManager.shared.updatePhotoStatus(id: photoId, status: .publishing)
                await MainActor.run {
                    self.status = .publishing
                }
                
                try await self.publishPayload(payload)
                
                await MainActor.run {
                    self.photo = Photo(originalData: jpegData)
                    
                    if payload.content.type == "public",
                       let metadataString = payload.content.value.metadata,
                       let metadataData = metadataString.data(using: .utf8),
                       let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                        self.lastMetadata = metadata
                    } else {
                        self.lastMetadata = ["status": "encrypted"]
                    }
                    
                    self.status = .ready
                }
                
                await PhotoManager.shared.clearPhotoStatus(id: photoId)
                
            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                    self.stopPublishingHaptics()
                    print("Error processing/publishing photo: \(error)")
                }
                await PhotoManager.shared.updatePhotoStatus(id: photoId, status: .error(error.localizedDescription))
            }
        }
    }
    
    // Add this new helper method to create the payload
    private func createPayload(_ base64String: String) async throws -> CameraPayload {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Get all metadata
        let sensorData = await MainActor.run { sensorManager.getSensorData() }
        let deviceInfo = await MainActor.run {
            [
                "model": UIDevice.current.modelName,
                "systemVersion": UIDevice.current.systemVersion,
                "name": UIDevice.current.name
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\"", with: "\\\"")
            ]
        }
        
        // Extract camera settings from EXIF data and device
        var cameraSettings: [String: String] = [:]
        print("📸 Image Properties:", imageProperties ?? [:])
        
        // Try to get from EXIF first
        if let exifDict = (imageProperties?[kCGImagePropertyExifDictionary as String] as? [String: Any]) {
            print("📸 EXIF Data:", exifDict)
            
            if let fNumber = exifDict[kCGImagePropertyExifFNumber as String] as? Double {
                cameraSettings["aperture"] = String(format: "f/%.1f", fNumber)
            }
            if let exposureTime = exifDict[kCGImagePropertyExifExposureTime as String] as? Double {
                cameraSettings["shutterSpeed"] = "1/\(Int(1/exposureTime))s"
            }
            if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
               let isoValue = iso.first {
                cameraSettings["iso"] = "ISO \(isoValue)"
            }
        }
        
        // If EXIF data is missing, try to get from current device settings
        if cameraSettings.isEmpty, let device = videoDeviceInput?.device {
            cameraSettings["aperture"] = String(format: "f/%.1f", device.lensAperture)
            cameraSettings["shutterSpeed"] = "1/\(Int(1/device.exposureDuration.seconds))s"
            cameraSettings["iso"] = "ISO \(Int(device.iso))"
        }
        
        print("📸 Final Camera Settings:", cameraSettings)
        
        // Get location name using reverse geocoding
        var locationInfo: [String: String] = [:]
        print("📍 Sensor Data:", sensorData)
        
        if let coordinates = sensorData["coordinates"] as? [String: Any] {
            print("📍 Coordinates:", coordinates)
            if let latitude = coordinates["latitude"] as? Double,
               let longitude = coordinates["longitude"] as? Double {
                
                // Create a semaphore to wait for geocoding
                let semaphore = DispatchSemaphore(value: 0)
                
                // Start geocoding
                let location = CLLocation(latitude: latitude, longitude: longitude)
                let geocoder = CLGeocoder()
                
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    if let error = error {
                        print("📍 Geocoding Error:", error)
                    }
                    
                    if let placemark = placemarks?.first {
                        print("📍 Placemark:", placemark)
                        var components: [String] = []
                        
                        if let subLocality = placemark.subLocality {
                            components.append(subLocality)
                        }
                        
                        if let thoroughfare = placemark.thoroughfare {
                            components.append(thoroughfare)
                        }
                        
                        if let locality = placemark.locality {
                            components.append(locality)
                        }
                        
                        if let country = placemark.country {
                            components.append(country)
                        }
                        
                        locationInfo["name"] = components.joined(separator: ", ")
                        print("📍 Final Location Name:", locationInfo["name"] ?? "None")
                    }
                    semaphore.signal()
                }
                
                // Wait for geocoding to complete with a timeout
                _ = semaphore.wait(timeout: .now() + 2.0)
                print("📍 Location Info after geocoding:", locationInfo)
            }
        }
        
        print("📍 Final Location Info before metadata creation:", locationInfo)
        let metadata: [String: Any] = [
            "timestamp": timestamp,
            "sensorData": formatMetadataForJSON(sensorData),
            "deviceInfo": deviceInfo,
            "imageProperties": formatMetadataForJSON(imageProperties ?? [:]),
            "location": locationInfo,
            "cameraSettings": cameraSettings
        ]
        
        // Debug print the metadata
        print("📝 Metadata Structure:")
        if let prettyPrintedData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]),
           let prettyPrintedString = String(data: prettyPrintedData, encoding: .utf8) {
            print(prettyPrintedString)
        }
        
        // Convert metadata to JSON string with proper formatting
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"
        
        let contentValue: CameraPayload.ContentValue
        let contentType: String
        let contentToHash: String
        
        if isPublicMode {
            contentType = "public"
            contentValue = CameraPayload.ContentValue(
                mediadata: base64String,
                metadata: metadataString,
                encrypted: nil
            )
            
            let valueDict: [String: String] = [
                "mediadata": base64String,
                "metadata": metadataString
            ]
            contentToHash = jsonToSortedQueryString(valueDict)
        } else {
            contentType = "private"
            let privateContent: [String: Any] = [
                "mediadata": base64String,
                "metadata": metadata
            ]
            
            let formattedContent = formatMetadataForJSON(privateContent)
            let jsonData = try JSONSerialization.data(withJSONObject: formattedContent)
            let encryptedData = try await ContentKeyManager.shared.encrypt(jsonData)
            let encryptedString = encryptedData.base64EncodedString()
            
            contentValue = CameraPayload.ContentValue(
                mediadata: nil,
                metadata: nil,
                encrypted: encryptedString
            )
            
            contentToHash = encryptedString
        }
        
        // Calculate SHA256 and continue with the rest of the payload creation
        let contentData = contentToHash.data(using: .utf8)!
        let hash = SHA256.hash(data: contentData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Get signatures
        let ethSignature = try await EthereumManager.shared.signMessage(hashString)
        let secpSignature = SecureEnclaveManager.shared.sign(hashString.data(using: .utf8)!)?.base64EncodedString() ?? ""
        
        return CameraPayload(
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
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\(fullKey)=\(stringValue)"
            }
        }.joined(separator: "&")
    }
}

// Add this helper function to format metadata
private func formatMetadataForJSON(_ metadata: [String: Any]) -> [String: Any] {
    func convertValue(_ value: Any) -> Any {
        switch value {
        case let number as NSNumber:
            // Convert NSNumber to the most appropriate type
            let type = String(cString: number.objCType)
            switch type {
            case "d", "f":
                // Format float/double with fixed precision to avoid scientific notation
                return String(format: "%.6f", number.doubleValue)
            case "B":
                return number.boolValue
            default:
                return number.intValue
            }
        case let string as String:
            // Ensure string is valid JSON
            return string.replacingOccurrences(of: "\u{0000}", with: "")
                        .replacingOccurrences(of: "\\", with: "\\\\")
        case let dict as [String: Any]:
            return dict.mapValues { convertValue($0) }
        case let array as [Any]:
            return array.map { convertValue($0) }
        case let date as Date:
            // Format dates as ISO8601
            return ISO8601DateFormatter().string(from: date)
        default:
            return String(describing: value)
        }
    }
    
    return metadata.mapValues { convertValue($0) }
}

// Add this helper function to extract metadata
private func extractImageMetadata(from imageData: Data) -> [String: Any] {
    var metadata: [String: Any] = [:]
    
    if let cgImageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
       let properties = CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0, nil) as? [String: Any] {
        
        var imageMetadata: [String: Any] = [:]
        
        // Get EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            imageMetadata["exif"] = formatMetadataForJSON(exif)
        }
        
        // Get TIFF data
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            imageMetadata["tiff"] = formatMetadataForJSON(tiff)
        }
        
        // Get GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            imageMetadata["gps"] = formatMetadataForJSON(gps)
        }
        
        // Add basic image properties
        var basic: [String: Any] = [:]
        if let width = properties[kCGImagePropertyPixelWidth as String] {
            basic["width"] = width
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] {
            basic["height"] = height
        }
        if let colorModel = properties[kCGImagePropertyColorModel as String] {
            basic["colorModel"] = colorModel
        }
        if let dpiWidth = properties[kCGImagePropertyDPIWidth as String] {
            basic["dpiWidth"] = dpiWidth
        }
        if let dpiHeight = properties[kCGImagePropertyDPIHeight as String] {
            basic["dpiHeight"] = dpiHeight
        }
        if let depth = properties[kCGImagePropertyDepth as String] {
            basic["depth"] = depth
        }
        if let orientation = properties[kCGImagePropertyOrientation as String] {
            basic["orientation"] = orientation
        }
        
        imageMetadata["basic"] = formatMetadataForJSON(basic)
        metadata["image"] = imageMetadata
    }
    
    return metadata
}

// Add these new structures for response handling
private struct UploadResponse: Codable {
    let owner: String
    let url: String
}

private struct PublishPayload: Codable {
    let owner: String
    let url: String
    let message: String
    let signature: String
    let secp256r1_pubkey: String
    let permit: PermitData
    
    struct PermitData: Codable {
        let signature: String
        let nonce: String
        let deadline: String
    }
}

private struct PublishResponse: Codable {
    let success: Bool
}

// Add these constants near the top of the file
private let PERMIT_TOKEN_ADDRESS = "0xa22Ba08758C024F1570AFb0a3C09461d492A5950"
private let PERMIT_SPENDER_ADDRESS = "0x9D083152dC00b6964D8145E8D7e7E1a300Ff23f5"
private let PERMIT_AMOUNT = "1000000000000000000"
private let PERMIT_CHAIN_ID = BigUInt(84532)

// Add these structures after the existing response structures
private struct PermitSignature {
    let signature: String
    let nonce: BigUInt
    let deadline: BigUInt
}

// Add this extension to handle EIP712 signing
extension CameraService {
    private func generatePermitSignature() async throws -> PermitSignature {
        guard let privateKey = try await EthereumManager.shared.getPrivateKey() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get private key"])
        }
        
        guard let tokenAddr = try? EthereumAddress(PERMIT_TOKEN_ADDRESS),
              let spenderAddr = try? EthereumAddress(PERMIT_SPENDER_ADDRESS),
              let amountBigUInt = BigUInt(PERMIT_AMOUNT) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid permit parameters"])
        }
        
        let deadline = BigUInt(Date().timeIntervalSince1970 + 300)
        
        // Get nonce from contract
        guard let ownerAddress = try await EthereumManager.shared.getWalletAddress(),
              let ethereumAddress = EthereumAddress(ownerAddress),
              let contractAddress = EthereumAddress(PERMIT_TOKEN_ADDRESS),
              let web3 = try? await Web3.new(URL(string: EthereumManager.shared.baseRPCUrl)!) else {
            throw EthereumError.invalidAddress
        }
        
        let erc20ABI = """
        [{"constant":true,"inputs":[{"name":"owner","type":"address"}],"name":"nonces","outputs":[{"name":"","type":"uint256"}],"type":"function"}]
        """
        
        guard let contract = web3.contract(erc20ABI, at: contractAddress) else {
            throw EthereumError.contractError
        }
        
        let noncesResult = try await contract.createReadOperation("nonces", parameters: [ethereumAddress] as [AnyObject])!.callContractMethod()
        guard let nonce = noncesResult["0"] as? BigUInt else {
            throw EthereumError.contractError
        }
        
        print("📝 Domain Data:")
        print("Token Address:", tokenAddr.address)
        print("Chain ID:", PERMIT_CHAIN_ID)
        
        print("📝 Permit Data:")
        print("Owner:", ownerAddress)
        print("Spender:", spenderAddr.address)
        print("Value:", amountBigUInt)
        print("Nonce:", nonce)
        print("Deadline:", deadline)
        
        // Following reference implementation exactly
        let types: [String: [EIP712TypeProperty]] = [
            "EIP712Domain": [
                EIP712TypeProperty(name: "name", type: "string"),
                EIP712TypeProperty(name: "version", type: "string"),
                EIP712TypeProperty(name: "chainId", type: "uint256"),
                EIP712TypeProperty(name: "verifyingContract", type: "address")
            ],
            "Permit": [
                EIP712TypeProperty(name: "owner", type: "address"),
                EIP712TypeProperty(name: "spender", type: "address"),
                EIP712TypeProperty(name: "value", type: "uint256"),
                EIP712TypeProperty(name: "nonce", type: "uint256"),
                EIP712TypeProperty(name: "deadline", type: "uint256")
            ]
        ]
        
        let domain: [String: AnyObject] = [
            "name": "MiraFilm" as AnyObject,  // Changed to match reference
            "version": "1" as AnyObject,
            "chainId": PERMIT_CHAIN_ID.description as AnyObject,  // Changed to match reference
            "verifyingContract": tokenAddr.address as AnyObject  // Removed lowercased
        ]
        
        let message: [String: AnyObject] = [
            "owner": ownerAddress as AnyObject,  // Removed lowercased
            "spender": spenderAddr.address as AnyObject,  // Removed lowercased
            "value": amountBigUInt as AnyObject,  // Changed to match reference
            "nonce": nonce as AnyObject,  // Changed to match reference
            "deadline": deadline as AnyObject  // Changed to match reference
        ]
        
        let typedData = try EIP712TypedData(
            types: types,
            primaryType: "Permit",
            domain: domain,
            message: message
        )
        
        let messageHash = try typedData.signHash()
        print("📝 EIP-712 Message Hash to sign: \(messageHash.toHexString())")
        
        let privateKeyData = Data(hex: privateKey)
        let signatureResult = SECP256K1.signForRecovery(hash: messageHash, privateKey: privateKeyData)
        
        guard let serializedSignature = signatureResult.serializedSignature,
              let rawSignature = signatureResult.rawSignature else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate signature"])
        }
        
        // Extract r, s from the serialized signature (first 64 bytes)
        let r = serializedSignature[..<32]
        let s = serializedSignature[32..<64]  // Changed to only take up to 64
        
        // Calculate v (recovery ID + 27)
        let v = UInt8(rawSignature.last ?? 0) + 27
        
        print("📝 Signature Components:")
        print("R:", r.toHexString())
        print("S:", s.toHexString())
        print("V:", v)
        
        // Construct the signature with exactly one recovery byte
        let signature = r + s + Data([v])
        print(" Final Signature: 0x\(signature.toHexString())")
        
        return PermitSignature(
            signature: "0x" + signature.toHexString(),
            nonce: nonce,
            deadline: deadline
        )
    }
} 