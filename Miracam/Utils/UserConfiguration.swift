import Foundation
import Combine

class UserConfiguration: ObservableObject {
    static let shared = UserConfiguration()
    
    @Published var isPublicMode: Bool {
        didSet {
            UserDefaults.standard.set(isPublicMode, forKey: "isPublicMode")
            NotificationCenter.default.post(name: .publicModeDidChange, object: isPublicMode)
        }
    }
    
    @Published var enabledSensors: Set<SensorType> {
        didSet {
            let array = Array(enabledSensors.map { $0.rawValue })
            UserDefaults.standard.set(array, forKey: "enabledSensors")
        }
    }
    
    private init() {
        self.isPublicMode = UserDefaults.standard.bool(forKey: "isPublicMode", defaultValue: true)
        
        // Initialize enabled sensors from UserDefaults or use default set
        if let savedSensors = UserDefaults.standard.array(forKey: "enabledSensors") as? [String] {
            self.enabledSensors = Set(savedSensors.compactMap { SensorType(rawValue: $0) })
        } else {
            // Default: all sensors enabled
            self.enabledSensors = Set(SensorType.allCases)
        }
        
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(handlePublicModeChange),
                                             name: .publicModeDidChange,
                                             object: nil)
    }
    
    @objc private func handlePublicModeChange(_ notification: Notification) {
        if let newValue = notification.object as? Bool {
            if newValue != isPublicMode {
                isPublicMode = newValue
            }
        }
    }
}

enum SensorType: String, CaseIterable {
    case coordinates = "Coordinates"
    case compass = "Compass"
    case motion = "Motion"
    case audio = "Audio"
    case battery = "Battery"
    
    var icon: String {
        switch self {
        case .coordinates: return "mappin.circle"
        case .compass: return "location.north.fill"
        case .motion: return "gyroscope"
        case .audio: return "speaker.wave.2"
        case .battery: return "battery.100"
        }
    }
    
    var description: String {
        switch self {
        case .coordinates: return "Location coordinates and city name"
        case .compass: return "Compass heading and altitude"
        case .motion: return "Device orientation (pitch, roll, yaw)"
        case .audio: return "Audio level in decibels"
        case .battery: return "Device battery level"
        }
    }
}

// Add notification name
extension Notification.Name {
    static let publicModeDidChange = Notification.Name("publicModeDidChange")
}

// Helper extension for UserDefaults
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            set(defaultValue, forKey: key)
            return defaultValue
        }
        return bool(forKey: key)
    }
} 