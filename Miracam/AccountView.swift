import SwiftUI

struct AccountView: View {
    var body: some View {
        VStack {
            Image(systemName: "person.circle.fill")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Account Screen")
                .font(.title)
        }
    }
}

#Preview {
    AccountView()
} 