import SwiftUI

struct FlipContentView: View {
    let viewfinderContent: ViewfinderView
    @Binding var showSettings: Bool
    
    var body: some View {
        ZStack {
            viewfinderContent
                .offset(y: showSettings ? -UIScreen.main.bounds.height : 0)
                .opacity(showSettings ? 0 : 1)
            
            AccountView()
                .offset(y: showSettings ? 0 : UIScreen.main.bounds.height)
                .opacity(showSettings ? 1 : 0)
        }
        .background(Color(white: 0.1))
        .clipShape(ContinuousRoundedRectangle(cornerRadius: AppConstants.UI.containerRadius))
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showSettings)
    }
} 