import SwiftUI
import AVFoundation
import Combine
import UIKit // Import UIKit for haptic feedback

class CameraViewModel: ObservableObject {
    @Published var viewfinderImage: Image?
    @Published var isPublishing = false
    @Published var publishError: String?
    
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
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Viewfinder section
                ZStack {
                    // Viewfinder and border container
                    if let image = viewModel.viewfinderImage {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width)
                            .clipShape(ContinuousRoundedRectangle(cornerRadius: 39))
                            .overlay(
                                ContinuousRoundedRectangle(cornerRadius: 39)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    } else {
                        Color.black
                            .frame(width: geometry.size.width)
                            .clipShape(ContinuousRoundedRectangle(cornerRadius: 39))
                            .overlay(
                                ContinuousRoundedRectangle(cornerRadius: 39)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    // Border overlay
                    if !viewModel.cameraService.isPublicMode {
                        ZStack {
                            ContinuousRoundedRectangle(cornerRadius: 39)
                                .fill(Color.red.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            ContinuousRoundedRectangle(cornerRadius: 39)
                                .fill(Color.black)
                                .padding(12)
                        }
                    }
                    
                    // Overlays
                    VStack {
                        SensorDataView(sensorManager: viewModel.cameraService.sensorManager)
                            .padding(.top, 44)
                        
                        Spacer()
                        
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Controls section
                VStack(spacing: 8) {
                    // Grid layout for buttons and shutter
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        // Flash button
                        Button(action: { viewModel.cameraService.toggleFlash() }) {
                            Image(systemName: viewModel.cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(viewModel.cameraService.flashMode == .on ? .yellow : .white)
                                .frame(height: 36)
                        }
                        
                        // Flip button
                        Button(action: { viewModel.cameraService.switchCamera() }) {
                            Image(systemName: "camera.rotate.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(height: 36)
                        }
                        
                        // Public/Private toggle
                        Button(action: { viewModel.cameraService.isPublicMode.toggle() }) {
                            Image(systemName: viewModel.cameraService.isPublicMode ? "globe" : "lock.fill")
                                .font(.system(size: 20))
                                .foregroundColor(viewModel.cameraService.isPublicMode ? .green : .red)
                                .frame(height: 36)
                        }
                        
                        // Thumbnail with status overlay
                        if let lastPhoto = lastPhoto {
                            ZStack {
                                lastPhoto
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipped()
                                    .cornerRadius(8)
                                
                                // Progress overlay
                                if viewModel.isPublishing {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                    
                                    // Status icon with pulsing animation
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 20))
                                        .scaleEffect(isAnimating ? 1.5 : 1.0)
                                        .animation(
                                            Animation.easeInOut(duration: 0.5)
                                                .repeatForever(autoreverses: true),
                                            value: isAnimating
                                        )
                                        .onAppear {
                                            isAnimating = true
                                        }
                                        .onDisappear {
                                            isAnimating = false
                                        }
                                }
                            }
                            .onTapGesture {
                                showThumbnailSheet = true
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                .onTapGesture {
                                    showThumbnailSheet = true
                                }
                        }
                        
                        // Shutter
                        Button(action: { 
                            viewModel.cameraService.capturePhoto()
                            // Simulate capturing a photo
                            lastPhoto = viewModel.viewfinderImage
                            lastMetadata = ["ExampleKey": "ExampleValue"] // Replace with actual metadata
                            lastMode = viewModel.cameraService.isPublicMode ? "Public" : "Private"
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                                        .frame(width: 60, height: 60)
                                )
                        }
                        
                        // Token counter
                        Text("100")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 60, height: 60)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .background(Color.black)
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