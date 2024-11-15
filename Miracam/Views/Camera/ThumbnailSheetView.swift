import SwiftUI

struct ThumbnailSheetView: View {
    let image: Image?
    let metadata: [String: Any]?
    let mode: String
    let hasPhoto: Bool

    var body: some View {
        VStack {
            // Image preview
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Text("No photo available")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }

            // Metadata and mode
            if let metadata = metadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata:")
                        .font(.headline)
                    ForEach(metadata.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(String(describing: metadata[key]!))")
                            .font(.subheadline)
                    }
                    Text("Mode: \(mode)")
                        .font(.subheadline)
                }
                .padding()
            }

            // Footer with buttons
            HStack {
                if hasPhoto {
                    Button(action: {
                        // Action for viewing in explorer
                    }) {
                        Text("View in Explorer")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }

                Button(action: {
                    // Action for viewing profile
                }) {
                    Text("View My Profile")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .edgesIgnoringSafeArea(.bottom)
    }
} 