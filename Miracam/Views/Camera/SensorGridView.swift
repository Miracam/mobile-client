import SwiftUI
import CoreLocation

struct SensorGridView: View {
    @ObservedObject var sensorManager: SensorDataManager
    @ObservedObject private var userConfig = UserConfiguration.shared
    
    private func cardinalDirection(from heading: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Main sensor bar
            HStack(spacing: 4) {
                // Compass Data
                if userConfig.enabledSensors.contains(.compass) {
                    SensorGridBadge(
                        icon: "location.north.fill",
                        value: "\(Int(sensorManager.heading))°\(cardinalDirection(from: sensorManager.heading))"
                    )
                    
                    SensorGridBadge(
                        icon: "arrow.up.right.circle",
                        value: "\(Int(sensorManager.altitude))m"
                    )
                }
                
                // Audio Data
                if userConfig.enabledSensors.contains(.audio) {
                    SensorGridBadge(
                        icon: "speaker.wave.2",
                        value: "\(Int(sensorManager.decibels))"
                    )
                }
                
                // Motion Data
                if userConfig.enabledSensors.contains(.motion) {
                    Group {
                        SensorGridBadge(icon: "p.circle", value: "\(Int(sensorManager.pitch))°")
                        SensorGridBadge(icon: "r.circle", value: "\(Int(sensorManager.roll))°")
                        SensorGridBadge(icon: "y.circle", value: "\(Int(sensorManager.yaw))°")
                    }
                }
                
                // Battery Data
                if userConfig.enabledSensors.contains(.battery) {
                    SensorGridBadge(
                        icon: "battery.100",
                        value: "\(sensorManager.batteryLevel)%"
                    )
                }
            }
            
            // Location details (only show if coordinates are enabled)
            if userConfig.enabledSensors.contains(.coordinates), !sensorManager.locationName.isEmpty {
                HStack {
                    Text(sensorManager.locationName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(String(format: "%.4f, %.4f", 
                              sensorManager.latitude,
                              sensorManager.longitude))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.bottom, 28)
        .onChange(of: sensorManager.latitude, initial: false) { oldValue, newValue in
            if newValue != 0 {
                sensorManager.updateLocationName(latitude: sensorManager.latitude, longitude: sensorManager.longitude)
            }
        }
        .onChange(of: sensorManager.longitude, initial: false) { oldValue, newValue in
            if newValue != 0 {
                sensorManager.updateLocationName(latitude: sensorManager.latitude, longitude: sensorManager.longitude)
            }
        }
        .onChange(of: userConfig.enabledSensors, initial: false) { oldValue, newValue in
            sensorManager.updateLocationName(latitude: sensorManager.latitude, longitude: sensorManager.longitude)
        }
    }
}

struct SensorGridBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
            
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.05))
        .cornerRadius(4)
    }
} 