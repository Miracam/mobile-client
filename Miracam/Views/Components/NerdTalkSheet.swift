import SwiftUI

struct NerdTalkSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: {
                    // Action for "How does it work?"
                }) {
                    Text("How does it work?")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                }
                
                Button(action: {
                    // Action for "What is $FILM?"
                }) {
                    Text("What is $FILM?")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                }
                
                Button(action: {
                    // Action for "What is NFT?"
                }) {
                    Text("What is NFT?")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                }
                
                Spacer()
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .navigationTitle("Choose a topic to learn more")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    }
                }
            }
        }
    }
} 