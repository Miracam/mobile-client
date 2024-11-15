import SwiftUI
import AVFoundation
import Combine
import UIKit // Import UIKit for haptic feedback

class CameraViewModel: ObservableObject {
    @Published var viewfinderImage: Image?
    @Published var isPublishing = false
    @Published var publishError: String?
    @Published var status: CameraStatus = .ready
    
    let cameraService = CameraService()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        cameraService.$viewfinderImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.viewfinderImage = image
            }
            .store(in: &cancellables)
        
        cameraService.$isPublishing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPublishing)
        
        cameraService.$publishError
            .receive(on: DispatchQueue.main)
            .assign(to: &$publishError)
        
        cameraService.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
    }
}

struct ContinuousRoundedRectangle: Shape {
    let cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath)
    }
}

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showThumbnailSheet = false
    @State private var lastPhoto: Image? = nil
    @State private var lastMetadata: [String: Any]? = nil
    @State private var lastMode: String = "Public"
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    ViewfinderView(
                        image: viewModel.viewfinderImage,
                        isPublicMode: viewModel.cameraService.isPublicMode
                    )
                    
                    VStack {
                        SensorDataView(sensorManager: viewModel.cameraService.sensorManager)
                            .padding(.top, 44)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                CameraControlsView(
                    viewModel: viewModel,
                    lastPhoto: $lastPhoto,
                    lastMetadata: $lastMetadata,
                    lastMode: $lastMode,
                    showThumbnailSheet: $showThumbnailSheet
                )
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            viewModel.cameraService.checkForPermissions()
            setOrientationLock()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                setOrientationLock()
            }
        }
        .sheet(isPresented: $showThumbnailSheet) {
            ThumbnailSheetView(
                image: lastPhoto,
                metadata: lastMetadata,
                mode: lastMode,
                hasPhoto: lastPhoto != nil
            )
        }
        .onShake {
            viewModel.cameraService.isPublicMode.toggle()
            HapticManager.shared.notification(.warning)
        }
    }
    
    private func setOrientationLock() {
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}

struct SensorOverlayView: View {
    @ObservedObject var sensorManager: SensorDataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                SensorBadge(icon: "location.north.fill", 
                           value: "\(Int(sensorManager.heading))° \(cardinalDirection(from: sensorManager.heading))")
                SensorBadge(icon: "mappin.and.ellipse", 
                           value: String(format: "%.4f, %.4f", 
                                       sensorManager.latitude, 
                                       sensorManager.longitude))
            }
            
            HStack(spacing: 4) {
                SensorBadge(icon: "arrow.up.right.circle", 
                           value: "\(Int(sensorManager.altitude))m")
                SensorBadge(icon: "battery.100", value: "\(sensorManager.batteryLevel)%")
                SensorBadge(icon: "speaker.wave.2", value: "\(Int(sensorManager.decibels))dB")
            }
            
            HStack(spacing: 4) {
                SensorBadge(icon: "gyroscope", 
                           value: String(format: "P:%.1f° R:%.1f°", 
                                       sensorManager.pitch, 
                                       sensorManager.roll))
                SensorBadge(icon: "rotate.3d", 
                           value: String(format: "Y:%.1f°", 
                                       sensorManager.yaw))
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
    
    private func cardinalDirection(from heading: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
}

struct SensorBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 12, height: 12)
            Text(value)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color.gray.opacity(0.5))
        .cornerRadius(4)
    }
}

// Sensor data view component
struct SensorDataView: View {
    @ObservedObject var sensorManager: SensorDataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(sensorManager.heading))° \(cardinalDirection(from: sensorManager.heading)) | \(String(format: "%.4f, %.4f", sensorManager.latitude, sensorManager.longitude))")
                .foregroundColor(.white)
                .font(.system(size: 12, design: .monospaced))
            
            Text("\(Int(sensorManager.altitude))m ALT | \(sensorManager.batteryLevel)% BAT | \(Int(sensorManager.decibels))dB")
                .foregroundColor(.white)
                .font(.system(size: 12, design: .monospaced))
            
            Text(String(format: "P:%.1f° R:%.1f° Y:%.1f°", sensorManager.pitch, sensorManager.roll, sensorManager.yaw))
                .foregroundColor(.white)
                .font(.system(size: 12, design: .monospaced))
        }
    }
    
    private func cardinalDirection(from heading: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
}

struct ThumbnailSheetView: View {
    let image: Image?
    let metadata: [String: Any]?
    let mode: String
    let hasPhoto: Bool

    var body: some View {
        VStack {
            // Image preview
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Text("No photo available")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }

            // Metadata and mode
            if let metadata = metadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata:")
                        .font(.headline)
                    ForEach(metadata.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(String(describing: metadata[key]!))")
                            .font(.subheadline)
                    }
                    Text("Mode: \(mode)")
                        .font(.subheadline)
                }
                .padding()
            }

            // Footer with buttons
            HStack {
                if hasPhoto {
                    Button(action: {
                        // Action for viewing in explorer
                    }) {
                        Text("View in Explorer")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }

                Button(action: {
                    // Action for viewing profile
                }) {
                    Text("View My Profile")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}