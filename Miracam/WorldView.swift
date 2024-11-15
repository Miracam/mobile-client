import SwiftUI

struct WorldView: View {
    var body: some View {
        ZStack {
            Color.green
                .ignoresSafeArea()
            
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                Text("World Screen")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    WorldView()
} 