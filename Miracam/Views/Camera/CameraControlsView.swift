import SwiftUI

struct CameraControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var lastPhoto: Image?
    @Binding var lastMetadata: [String: Any]?
    @Binding var lastMode: String
    @Binding var showThumbnailSheet: Bool
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                CameraButton(action: {
                    HapticManager.shared.impact(.light)
                    viewModel.cameraService.toggleFlash()
                }, icon: viewModel.cameraService.flashMode == .on ? "bolt.fill" : "bolt.slash.fill",
                   color: viewModel.cameraService.flashMode == .on ? .yellow : .white)
                
                CameraButton(action: {
                    HapticManager.shared.impact(.light)
                    viewModel.cameraService.switchCamera()
                }, icon: "camera.rotate.fill", color: .white)
                
                let isPublic = viewModel.cameraService.isPublicMode
                CameraButton(action: {
                    HapticManager.shared.impact(.light)
                    viewModel.cameraService.isPublicMode.toggle()
                }, icon: isPublic ? "globe" : "lock.fill",
                   color: isPublic ? .green : .red)
                
                ThumbnailView(lastPhoto: lastPhoto,
                             isPublishing: viewModel.isPublishing,
                             status: viewModel.status,
                             showThumbnailSheet: $showThumbnailSheet)
                
                ShutterButton(action: {
                    viewModel.cameraService.capturePhoto()
                    lastPhoto = viewModel.viewfinderImage
                    lastMetadata = ["ExampleKey": "ExampleValue"]
                    lastMode = viewModel.cameraService.isPublicMode ? "Public" : "Private"
                })
                
                TokenCounterView(count: "100")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }
}

struct CameraButton: View {
    let action: () -> Void
    let icon: String
    let color: Color
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(height: 36)
        }
    }
}

struct ShutterButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.white)
                .frame(width: 70, height: 70)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 60, height: 60)
                )
        }
    }
}

struct TokenCounterView: View {
    let count: String
    
    var body: some View {
        Text(count)
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 60, height: 60)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(8)
    }
} 