import SwiftUI
import AVFoundation
import Combine

class CameraViewModel: ObservableObject {
    @Published var viewfinderImage: Image?
    @Published var showCapturedData = false
    @Published var capturedBase64: String = ""
    
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
        
        cameraService.$capturedImageBase64
            .receive(on: DispatchQueue.main)
            .sink { [weak self] base64String in
                if let base64String = base64String {
                    print("ViewModel received base64 string of length: \(base64String.count)")
                    self?.capturedBase64 = base64String
                    self?.showCapturedData = true
                } else {
                    print("ViewModel received nil base64 string")
                }
            }
            .store(in: &cancellables)
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
        .sheet(isPresented: $viewModel.showCapturedData) {
            CapturedDataView(base64String: viewModel.capturedBase64)
        }
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

struct CapturedDataView: View {
    let base64String: String
    @Environment(\.dismiss) var dismiss
    @State private var isEncrypted: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Try to decode as JSON first
                    if let data = base64String.data(using: .utf8),
                       (try? JSONDecoder().decode(CameraPayload.self, from: data)) != nil {
                        // Public mode - show decoded data
                        // ... existing public mode view ...
                    } else {
                        // Private mode - show encrypted data
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20))
                            Text("Private Mode (Encrypted)")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.8))
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                        )
                        .foregroundColor(.white)
                        
                        Text("Encrypted Data Preview (first 100 chars):")
                            .font(.headline)
                        Text(String(base64String.prefix(100)))
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(nil)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        
                        Text("Total length: \(base64String.count) characters")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        UIPasteboard.general.string = base64String
                    }) {
                        Label("Copy Full Payload", systemImage: "doc.on.doc")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Capture Result")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
} 