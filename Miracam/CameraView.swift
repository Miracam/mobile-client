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
                            print("🔘 Toggle button pressed")
                            viewModel.cameraService.isPublicMode.toggle()
                            print("🔄 Mode after toggle: \(viewModel.cameraService.isPublicMode ? "Public" : "Private")")
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
        
        // Ensure all future presentations are portrait only
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
} 