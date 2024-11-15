import SwiftUI

struct WorldView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("World Screen")
                .font(.title)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen height
    }
}

#Preview {
    WorldView()
} 