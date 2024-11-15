import SwiftUI

struct ThumbnailView: View {
    let lastPhoto: Image?
    let isPublishing: Bool
    let status: CameraStatus
    @Binding var showThumbnailSheet: Bool
    @State private var isAnimating = false
    @State private var showCheckmark = false
    
    var body: some View {
        if let lastPhoto = lastPhoto {
            ZStack {
                lastPhoto
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
                
                if isPublishing || status == .processing || showCheckmark {
                    ProcessingOverlay(
                        status: status,
                        isAnimating: $isAnimating,
                        showCheckmark: $showCheckmark
                    )
                }
            }
            .onTapGesture {
                showThumbnailSheet = true
            }
            .onChange(of: status) { oldValue, newValue in
                if oldValue != .ready && newValue == .ready {
                    // Show checkmark when processing completes
                    showCheckmark = true
                    // Hide checkmark after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation {
                            showCheckmark = false
                        }
                    }
                }
            }
        } else {
            EmptyThumbnail(showThumbnailSheet: $showThumbnailSheet)
        }
    }
}

struct ProcessingOverlay: View {
    let status: CameraStatus
    @Binding var isAnimating: Bool
    @Binding var showCheckmark: Bool
    
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: 60, height: 60)
            .cornerRadius(8)
        
        if showCheckmark {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 24))
                .transition(.opacity)
        } else {
            Image(systemName: status == .processing ? "gear" : "arrow.up.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 20))
                .scaleEffect(isAnimating ? 1.5 : 1.0)
                .rotationEffect(.degrees(status == .processing ? isAnimating ? 360 : 0 : 0))
                .animation(
                    status == .processing ?
                        Animation.linear(duration: 2).repeatForever(autoreverses: false) :
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
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
}

struct EmptyThumbnail: View {
    @Binding var showThumbnailSheet: Bool
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            .onTapGesture {
                showThumbnailSheet = true
            }
    }
} 