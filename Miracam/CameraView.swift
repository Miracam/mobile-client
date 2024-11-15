import SwiftUI
import AVFoundation
import Combine

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

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if viewModel.cameraService.isCameraUnavailable {
                VStack {
                    Text("Camera access is required")
                        .foregroundColor(.white)
                    Button("Grant Access") {
                        viewModel.cameraService.checkForPermissions()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                VStack(spacing: 0) {
                    // Mode indicator at the top
                    HStack {
                        Spacer()
                        
                        if viewModel.cameraService.status != .ready {
                            Text(viewModel.cameraService.status.description)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                                .padding(.leading, 16)
                        }
                        
                        Button(action: {
                            viewModel.cameraService.isPublicMode.toggle()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.cameraService.isPublicMode ? "globe" : "lock.fill")
                                    .font(.system(size: 20))
                                Text(viewModel.cameraService.isPublicMode ? "Public" : "Private")
                                    .font(.system(size: 18, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(viewModel.cameraService.isPublicMode ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }
                    .zIndex(1)
                    
                    ZStack {
                        // Viewfinder
                        GeometryReader { geometry in
                            if let image = viewModel.viewfinderImage {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            }
                        }
                        
                        // Add sensor overlay here
                        VStack {
                            SensorOverlayView(sensorManager: viewModel.cameraService.sensorManager)
                                .padding(.top, 60)
                                .padding(.horizontal)
                            Spacer()
                        }
                    }
                    .zIndex(0)
                    
                    // Camera controls
                    HStack(spacing: 60) {
                        Button(action: {
                            viewModel.cameraService.toggleFlash()
                        }) {
                            Image(systemName: viewModel.cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        }
                        
                        // Capture button
                        Button(action: {
                            viewModel.cameraService.capturePhoto()
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
                        
                        // Camera flip button
                        Button(action: {
                            viewModel.cameraService.switchCamera()
                        }) {
                            Image(systemName: "camera.rotate.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        }
                    }
                    .padding(.bottom, 30)
                    .zIndex(1)
                }
            }
        }
        .onAppear {
            viewModel.cameraService.checkForPermissions()
            setOrientationLock()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                setOrientationLock()
            }
        }
        .alert("Publishing Error", 
               isPresented: Binding(
                   get: { viewModel.publishError != nil },
                   set: { if !$0 { viewModel.publishError = nil } }
               ),
               actions: {
                   Button("OK") { viewModel.publishError = nil }
               },
               message: {
                   if let error = viewModel.publishError {
                       Text(error)
                   }
               }
        )
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