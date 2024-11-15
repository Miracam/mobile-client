import SwiftUI
import AVFoundation
import Combine
import UIKit

class CameraViewModel: ObservableObject {
    @Published var viewfinderImage: Image?
    @Published var isPublishing = false
    @Published var publishError: String?
    @Published var status: CameraStatus = .ready
    @Published var lastMetadata: [String: Any]?
    
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
        
        cameraService.$lastMetadata
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastMetadata)
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
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ZStack {
                        ViewfinderView(
                            image: viewModel.viewfinderImage,
                            isPublicMode: viewModel.cameraService.isPublicMode
                        )
                        
                        VStack {
                            Spacer()
                            SensorGridView(sensorManager: viewModel.cameraService.sensorManager)
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
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
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
            GalleryView()
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