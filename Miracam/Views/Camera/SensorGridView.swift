import SwiftUI
import CoreLocation

struct SensorGridView: View {
    @ObservedObject var sensorManager: SensorDataManager
    @ObservedObject private var userConfig = UserConfiguration.shared
    @State private var locationName: String = ""
    
    private func cardinalDirection(from heading: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
    
    private func updateLocationName() {
        guard userConfig.enabledSensors.contains(.coordinates),
              sensorManager.latitude != 0 && sensorManager.longitude != 0 else {
            return
        }
        
        let location = CLLocation(latitude: sensorManager.latitude, longitude: sensorManager.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                // Print all available location information
                print("📍 Location Details:")
                print("  Name: \(placemark.name ?? "N/A")")
                print("  Thoroughfare (Street): \(placemark.thoroughfare ?? "N/A")")
                print("  SubThoroughfare: \(placemark.subThoroughfare ?? "N/A")")
                print("  Locality (City): \(placemark.locality ?? "N/A")")
                print("  SubLocality: \(placemark.subLocality ?? "N/A")")
                print("  Administrative Area (State/Province): \(placemark.administrativeArea ?? "N/A")")
                print("  SubAdministrative Area: \(placemark.subAdministrativeArea ?? "N/A")")
                print("  Postal Code: \(placemark.postalCode ?? "N/A")")
                print("  Country: \(placemark.country ?? "N/A")")
                print("  ISO Country Code: \(placemark.isoCountryCode ?? "N/A")")
                print("  Ocean: \(placemark.ocean ?? "N/A")")
                print("  Inland Water: \(placemark.inlandWater ?? "N/A")")
                print("  Area of Interest: \(placemark.areasOfInterest?.joined(separator: ", ") ?? "N/A")")
                
                // Format location string as "City, Country"
                let city = placemark.locality ?? placemark.subLocality ?? placemark.name ?? ""
                let country = placemark.country ?? ""
                
                DispatchQueue.main.async {
                    if !city.isEmpty || !country.isEmpty {
                        self.locationName = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                    }
                }
            }
        }
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
            if userConfig.enabledSensors.contains(.coordinates), !locationName.isEmpty {
                HStack {
                    Text(locationName)
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
        .padding(.bottom, 8)
        .onChange(of: sensorManager.latitude) { _, newValue in
            if newValue != 0 {
                updateLocationName()
            }
        }
        .onChange(of: sensorManager.longitude) { _, newValue in
            if newValue != 0 {
                updateLocationName()
            }
        }
        .onChange(of: userConfig.enabledSensors) { _ in
            // Update location name when sensors are toggled
            updateLocationName()
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