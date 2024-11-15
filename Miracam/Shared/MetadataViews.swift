import SwiftUI

struct PublishMetadataView: View {
    let metadata: [String: Any]
    let mode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metadata")
                .font(.headline)
            
            if mode == "Public" {
                // Timestamp
                if let timestamp = metadata["timestamp"] as? String {
                    MetadataItem(title: "Timestamp", value: timestamp)
                }
                
                // Sensor Data
                if let sensorData = metadata["sensorData"] as? [String: Any] {
                    MetadataSection(title: "Sensor Data", data: sensorData)
                }
                
                // Device Info
                if let deviceInfo = metadata["deviceInfo"] as? [String: Any] {
                    MetadataSection(title: "Device Info", data: deviceInfo)
                }
                
                // Image Properties with EXIF
                if let imageProps = metadata["imageProperties"] as? [String: Any],
                   let image = imageProps["image"] as? [String: Any] {
                    if let exif = image["exif"] as? [String: Any] {
                        MetadataSection(title: "EXIF Data", data: filterExifData(exif))
                    }
                    if let basic = image["basic"] as? [String: Any] {
                        MetadataSection(title: "Basic Properties", data: basic)
                    }
                }
            } else {
                Text("Private photo metadata is encrypted")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // Filter and format EXIF data to show important fields
    private func filterExifData(_ exif: [String: Any]) -> [String: Any] {
        let importantFields = [
            "FocalLength",
            "ExposureTime",
            "FNumber",
            "ISOSpeedRatings",
            "LensModel",
            "DateTimeOriginal"
        ]
        
        return exif.filter { importantFields.contains($0.key) }
    }
}

struct MetadataSection: View {
    let title: String
    let data: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            ForEach(Array(data.keys.sorted()), id: \.self) { key in
                if let value = data[key] {
                    if let nestedDict = value as? [String: Any] {
                        MetadataItem(
                            title: key,
                            value: formatNestedDict(nestedDict)
                        )
                    } else {
                        MetadataItem(
                            title: key,
                            value: "\(value)"
                        )
                    }
                }
            }
            Divider()
        }
    }
    
    private func formatNestedDict(_ dict: [String: Any]) -> String {
        dict.map { key, value in
            "\(key): \(value)"
        }.joined(separator: "\n")
    }
}

struct MetadataItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
} 