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
                    self?.capturedBase64 = base64String
                    self?.showCapturedData = true
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
                VStack {
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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Captured Image Data")
                        .font(.headline)
                    
                    Text(base64String)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(nil)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    Button(action: {
                        UIPasteboard.general.string = base64String
                    }) {
                        Label("Copy Base64", systemImage: "doc.on.doc")
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