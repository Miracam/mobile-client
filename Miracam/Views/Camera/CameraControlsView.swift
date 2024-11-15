import SwiftUI
import Combine

struct CameraControlsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var lastPhoto: Image?
    @Binding var lastMetadata: [String: Any]?
    @Binding var lastMode: String
    @Binding var showThumbnailSheet: Bool
    @Binding var showSettings: Bool
    @State private var isAnimating = false
    @StateObject private var tokenManager = TokenBalanceManager.shared
    
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
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSettings.toggle()
                    }
                }, icon: showSettings ? "camera.fill" : "gearshape.fill",
                   color: showSettings ? .black : .white,
                   backgroundColor: showSettings ? .yellow : .clear)
                
                let isPublic = viewModel.cameraService.isPublicMode
                CameraButton(action: {
                    HapticManager.shared.impact(.light)
                    viewModel.cameraService.isPublicMode.toggle()
                }, icon: isPublic ? "globe" : "lock.fill",
                   color: isPublic ? .green : .red)
                
                thumbnailButton
                
                ShutterButton(action: {
                    viewModel.cameraService.capturePhoto()
                    lastPhoto = viewModel.viewfinderImage
                    lastMetadata = ["ExampleKey": "ExampleValue"]
                    lastMode = viewModel.cameraService.isPublicMode ? "Public" : "Private"
                }, count: formattedBalance)
                
                CameraButton(action: {
                    HapticManager.shared.impact(.light)
                    viewModel.cameraService.switchCamera()
                }, icon: "camera.rotate.fill", color: .white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(white: 0.1))
        .onAppear {
            Task {
                await tokenManager.refreshBalance()
            }
        }
        .onChange(of: viewModel.status) { oldValue, newValue in
            if oldValue == .publishing && newValue == .ready {
                Task {
                    await tokenManager.refreshBalance()
                }
            }
        }
    }
    
    private var formattedBalance: String {
        if let value = Double(tokenManager.balance), value > 1000 {
            return "999+"
        }
        return tokenManager.balance
    }
    
    var thumbnailButton: some View {
        ThumbnailButton(
            image: lastPhoto,
            status: viewModel.status
        ) {
            showThumbnailSheet = true
        }
    }
}

struct CameraButton: View {
    let action: () -> Void
    let icon: String
    let color: Color
    var backgroundColor: Color = .clear
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .cornerRadius(8)
        }
    }
}

struct ShutterButton: View {
    let action: () -> Void
    let count: String
    
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
                .overlay(
                    Text(count)
                        .foregroundColor(.black)
                        .font(.system(size: 16, weight: .medium))
                )
        }
    }
} 