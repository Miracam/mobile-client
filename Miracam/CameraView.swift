import SwiftUI

struct CameraView: View {
    var body: some View {
        VStack {
            Image(systemName: "camera.fill")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Camera Screen")
                .font(.title)
        }
    }
}

#Preview {
    CameraView()
} 