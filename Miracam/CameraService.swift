import Foundation
import AVFoundation
import Photos
import SwiftUI

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
                rotatedImage = originalImage.rotate(radians: -.pi/2) // -90 degrees
            case .landscapeRight:
                rotatedImage = originalImage.rotate(radians: .pi/2) // 90 degrees
            case .portraitUpsideDown:
                rotatedImage = originalImage.rotate(radians: .pi) // 180 degrees
            case .portrait, .faceUp, .faceDown, .unknown:
                rotatedImage = originalImage // Keep original orientation
            @unknown default:
                rotatedImage = originalImage
            }
            
            // Convert rotated image to JPEG data with full quality
            if let jpegData = rotatedImage.jpegData(compressionQuality: 1.0) {
                self.photo = Photo(originalData: jpegData)
                self.capturedImageBase64 = jpegData.base64EncodedString()
                print("Base64 string length: \(jpegData.base64EncodedString().count)")
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