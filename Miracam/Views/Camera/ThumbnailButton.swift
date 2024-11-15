import SwiftUI

struct ThumbnailButton: View {
    let image: Image?
    let status: CameraStatus
    let action: () -> Void
    
    @State private var isAnimating = false
    @State private var showCheckmark = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if let image = image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .overlay(statusOverlay)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(.white)
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        switch status {
        case .processing:
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 60, height: 60)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .publishing:
            ZStack {
                Color.black.opacity(0.3)
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever()) {
                    isAnimating = true
                }
                showCheckmark = false
            }
            .onDisappear {
                isAnimating = false
                // Show checkmark when publishing completes
                withAnimation {
                    showCheckmark = true
                }
                // Hide checkmark after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCheckmark = false
                    }
                }
            }
        case .ready:
            if showCheckmark {
                ZStack {
                    Color.black.opacity(0.3)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }
        case .error:
            ZStack {
                Color.black.opacity(0.3)
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
} 