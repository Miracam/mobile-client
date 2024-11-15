import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import UIKit

class SensorDataManager: NSObject, ObservableObject {
    @Published var heading: Double = 0
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var altitude: Double = 0
    @Published var batteryLevel: Int = 0
    @Published var decibels: Float = 0
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var yaw: Double = 0
    @Published var gravity: (x: Double, y: Double, z: Double) = (0, 0, 0)
    
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var timer: Timer?
    private var isActive = false
    
    // Add update intervals for different sensors
    private let locationUpdateInterval: TimeInterval = 1.0  // 1 second
    private let motionUpdateInterval: TimeInterval = 1.0/30.0  // 30Hz instead of 60Hz
    private let audioUpdateInterval: TimeInterval = 0.1  // 100ms
    
    override init() {
        self.inputNode = audioEngine.inputNode
        super.init()
        setupManagers()
    }
    
    private func setupManagers() {
        // Location setup
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters  // Reduced accuracy
        locationManager.distanceFilter = 5.0  // Only update if moved 5 meters
        locationManager.headingFilter = 5.0   // Only update if heading changes by 5 degrees
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        
        // Motion setup
        motionManager.deviceMotionUpdateInterval = motionUpdateInterval
        
        // Battery setup
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    private func setupAudioMonitoring() {
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
            // Process audio less frequently
            guard let self = self,
                  self.isActive else { return }
            
            // Use a larger buffer size and process less frequently
            let channelData = buffer.floatChannelData?[0]
            let frameLength = UInt(buffer.frameLength)
            
            var rms: Float = 0
            let strideValue = 4  // Process every 4th sample
            for i in 0..<Int(frameLength) where i % strideValue == 0 {
                let sample = channelData?[i] ?? 0
                rms += sample * sample
            }
            rms = sqrt(rms / Float(frameLength/UInt(strideValue)))
            
            let db = 20 * log10(rms)
            
            DispatchQueue.main.async {
                self.decibels = (self.decibels * 0.8) + (self.normalizeDecibelValue(db) * 0.2)
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func startUpdates() {
        guard !isActive else { return }
        isActive = true
        
        // Location updates
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        // Motion updates with reduced frequency
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
                guard let self = self,
                      self.isActive,
                      let motion = motion,
                      error == nil else { return }
                
                self.pitch = motion.attitude.pitch * 180 / .pi
                self.roll = motion.attitude.roll * 180 / .pi
                self.yaw = motion.attitude.yaw * 180 / .pi
                self.gravity = (
                    x: motion.gravity.x,
                    y: motion.gravity.y,
                    z: motion.gravity.z
                )
            }
        }
        
        // Battery updates
        updateBatteryLevel()
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateBatteryLevel()
        }
        
        // Audio updates
        setupAudioMonitoring()
    }
    
    func stopUpdates() {
        isActive = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        timer?.invalidate()
        timer = nil
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
    }
    
    @objc private func updateBatteryLevel() {
        guard isActive else { return }
        DispatchQueue.main.async {
            self.batteryLevel = Int(UIDevice.current.batteryLevel * 100)
            if self.batteryLevel < 0 {
                self.batteryLevel = UIDevice.current.isBatteryMonitoringEnabled ? 0 : 100
            }
        }
    }
    
    private func normalizeDecibelValue(_ value: Float) -> Float {
        let calibratedValue = value + 85
        return max(20, min(calibratedValue, 110))
    }
    
    func getSensorData() -> [String: Any] {
        return [
            "heading": heading,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "batteryLevel": batteryLevel,
            "decibels": decibels,
            "deviceModel": UIDevice.current.modelName,
            "timestamp": Date().timeIntervalSince1970,
            "motion": [
                "pitch": pitch,
                "roll": roll,
                "yaw": yaw,
                "gravity": [
                    "x": gravity.x,
                    "y": gravity.y,
                    "z": gravity.z
                ]
            ]
        ]
    }
}

extension SensorDataManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            self.altitude = location.altitude
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.trueHeading
        }
    }
}

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        switch identifier {
        case "iPhone14,4":                              return "iPhone 13 mini"
        case "iPhone14,5":                              return "iPhone 13"
        case "iPhone14,2":                              return "iPhone 13 Pro"
        case "iPhone14,3":                              return "iPhone 13 Pro Max"
        case "iPhone14,7":                              return "iPhone 14"
        case "iPhone14,8":                              return "iPhone 14 Plus"
        case "iPhone15,2":                              return "iPhone 14 Pro"
        case "iPhone15,3":                              return "iPhone 14 Pro Max"
        case "iPhone15,4":                              return "iPhone 15"
        case "iPhone15,5":                              return "iPhone 15 Plus"
        case "iPhone16,1":                              return "iPhone 15 Pro"
        case "iPhone16,2":                              return "iPhone 15 Pro Max"
        case "iPhone13,1":                              return "iPhone 12 mini"
        case "iPhone13,2":                              return "iPhone 12"
        case "iPhone13,3":                              return "iPhone 12 Pro"
        case "iPhone13,4":                              return "iPhone 12 Pro Max"
        case "iPhone12,1":                              return "iPhone 11"
        case "iPhone12,3":                              return "iPhone 11 Pro"
        case "iPhone12,5":                              return "iPhone 11 Pro Max"
        case "iPhone11,8":                              return "iPhone XR"
        case "iPhone11,2":                              return "iPhone XS"
        case "iPhone11,4", "iPhone11,6":                return "iPhone XS Max"
        case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                return "iPhone X"
        case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
        case "iPhone8,4":                               return "iPhone SE (1st generation)"
        case "iPhone12,8":                              return "iPhone SE (2nd generation)"
        case "iPhone14,6":                              return "iPhone SE (3rd generation)"
        case "i386", "x86_64", "arm64":                 return "Simulator \(mapToDevice(identifier: ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"))"
        default:                                        return identifier
        }
    }
    
    private func mapToDevice(identifier: String) -> String {
        switch identifier {
        case "iPhone14,4":                              return "iPhone 13 mini"
        case "iPhone14,5":                              return "iPhone 13"
        case "iPhone14,2":                              return "iPhone 13 Pro"
        case "iPhone14,3":                              return "iPhone 13 Pro Max"
        case "iPhone14,7":                              return "iPhone 14"
        case "iPhone14,8":                              return "iPhone 14 Plus"
        case "iPhone15,2":                              return "iPhone 14 Pro"
        case "iPhone15,3":                              return "iPhone 14 Pro Max"
        case "iPhone15,4":                              return "iPhone 15"
        case "iPhone15,5":                              return "iPhone 15 Plus"
        case "iPhone16,1":                              return "iPhone 15 Pro"
        case "iPhone16,2":                              return "iPhone 15 Pro Max"
        default:                                        return identifier
        }
    }
} 