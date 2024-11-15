import SwiftUI

struct ViewfinderView: View {
    let image: Image?
    let isPublicMode: Bool
    @ObservedObject var sensorManager: SensorDataManager
    
    var body: some View {
        ZStack {
            if let image = image {
                GeometryReader { geometry in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            } else {
                Color(white: 0.1)
            }
            
            if !isPublicMode {
                PrivateModeOverlay(cornerRadius: AppConstants.UI.privateModeOuterRadius)
            }
            
            VStack {
                Spacer()
                SensorGridView(sensorManager: sensorManager)
            }
        }
    }
}

struct PrivateModeOverlay: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        ContinuousRoundedRectangle(cornerRadius: AppConstants.UI.privateModeOuterRadius)
            .fill(Color.red.opacity(0.5))
            .mask {
                ContinuousRoundedRectangle(cornerRadius: AppConstants.UI.privateModeInnerRadius)
                    .padding(12)
                    .invertedMask()
            }
    }
}

extension View {
    func invertedMask() -> some View {
        Rectangle()
            .overlay(self.blendMode(.destinationOut))
    }
} 