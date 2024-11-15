import SwiftUI

struct ViewfinderView: View {
    let image: Image?
    let isPublicMode: Bool
    let cornerRadius: CGFloat = 39
    
    var body: some View {
        ZStack {
            // Viewfinder and border container
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(ContinuousRoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        ContinuousRoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
            } else {
                Color.black
                    .clipShape(ContinuousRoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        ContinuousRoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
            }
            
            // Private mode overlay
            if !isPublicMode {
                PrivateModeOverlay(cornerRadius: cornerRadius)
            }
        }
    }
}

struct PrivateModeOverlay: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        ContinuousRoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.red.opacity(0.5))
            .mask {
                ContinuousRoundedRectangle(cornerRadius: cornerRadius)
                    .padding(12)
                    .invertedMask()
            }
    }
}

// Add this extension somewhere in your file
extension View {
    func invertedMask() -> some View {
        Rectangle()
            .overlay(self.blendMode(.destinationOut))
    }
} 