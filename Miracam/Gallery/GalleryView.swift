import SwiftUI

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var photoManager = PhotoManager.shared
    @State private var showingClearAlert = false
    @State private var selectedPhoto: StoredPhoto?
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(photoManager.photos) { photo in
                        PhotoThumbnailView(
                            photo: photoManager.decryptedPhotos[photo.id] ?? photo,
                            isUnlocked: photoManager.isUnlocked
                        )
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPhoto = photoManager.decryptedPhotos[photo.id] ?? photo
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Gallery")
                        if !photoManager.photos.isEmpty {
                            Image(systemName: photoManager.isUnlocked ? "lock.open.fill" : "lock.fill")
                                .foregroundColor(photoManager.isUnlocked ? .green : .red)
                                .imageScale(.small)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if !photoManager.isDecryptingAll {
                            Button {
                                Task {
                                    await photoManager.toggleDecryptionState()
                                }
                            } label: {
                                Label(photoManager.isUnlocked ? "Lock All" : "Decrypt All", 
                                      systemImage: photoManager.isUnlocked ? "lock" : "lock.open")
                            }
                        }
                        
                        Button(role: .destructive) {
                            showingClearAlert = true
                        } label: {
                            Label("Clear Local", systemImage: "trash")
                        }
                        
                        Button {
                            // Placeholder for sync
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(photoManager.isDecryptingAll)
                }
            }
            .alert("Clear All Photos", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    Task {
                        await photoManager.clearAllPhotos()
                    }
                }
            } message: {
                Text("This will delete all locally stored photos. This action cannot be undone.")
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
            .overlay {
                if photoManager.isDecryptingAll {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: StoredPhoto
    let isUnlocked: Bool
    @StateObject private var photoManager = PhotoManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if photo.shouldShowThumbnail, 
                   let thumbnail = UIImage(contentsOfFile: photo.thumbnailPath) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if !photo.isPublic && !photo.isLocked {
                                Image(systemName: "lock.open.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                                    .padding(4)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .padding(4)
                            }
                        }
                } else if !photo.isPublic && !isUnlocked {
                    Color.black
                        .overlay(
                            Image(systemName: "lock.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        )
                }
                
                // Only show status overlay for active operations
                if let status = photoManager.photoStatuses[photo.id],
                   status != .ready {  // Don't show overlay for ready state
                    switch status {
                    case .processing:
                        Color.black.opacity(0.3)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                            .transition(.opacity)
                    case .publishing:
                        Color.black.opacity(0.3)
                            .overlay(
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                            )
                            .transition(.opacity)
                            .onAppear {
                                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever()) {
                                    isAnimating = true
                                }
                            }
                            .onDisappear {
                                isAnimating = false
                            }
                    case .error:
                        Color.black.opacity(0.3)
                            .overlay(
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                            )
                            .transition(.opacity)
                    case .ready:
                        EmptyView()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: photoManager.photoStatuses[photo.id])
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PhotoDetailView: View {
    @StateObject private var photoManager = PhotoManager.shared
    let photo: StoredPhoto
    @State private var isDecrypting = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Photo display
                    if let decrypted = photoManager.decryptedPhotos[photo.id], 
                       let thumbnail = UIImage(contentsOfFile: decrypted.thumbnailPath) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    } else if photo.isPublic, 
                              let thumbnail = UIImage(contentsOfFile: photo.thumbnailPath) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    } else {
                        // Show lock placeholder
                        Image(systemName: "lock.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                    }
                    
                    // Photo info and metadata
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Photo #\(photo.id.prefix(8))")
                                .font(.headline)
                            Spacer()
                            Text(photo.isPublic ? "Public" : "Private")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(photo.isPublic ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .cornerRadius(8)
                        }
                        
                        if photo.isLocked {
                            Button {
                                decryptPhoto()
                            } label: {
                                Label("Decrypt", systemImage: "lock.open")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isDecrypting)
                        }
                        
                        // Show metadata based on photo state
                        Group {
                            if let status = photoManager.photoStatuses[photo.id] {
                                switch status {
                                case .processing:
                                    Text("Processing metadata...")
                                        .foregroundColor(.gray)
                                case .publishing:
                                    Text("Publishing...")
                                        .foregroundColor(.gray)
                                case .error(let message):
                                    Text("Error: \(message)")
                                        .foregroundColor(.red)
                                case .ready:
                                    showMetadata
                                }
                            } else {
                                showMetadata
                            }
                        }
                        
                        Button {
                            // Placeholder for view in explorer
                        } label: {
                            Label("View in Explorer", systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var showMetadata: some View {
        if let _ = photoManager.decryptedPhotos[photo.id],
           let decryptedContent = photoManager.decryptedMetadata[photo.id] {
            #if DEBUG
            let _ = print("📊 Showing decrypted metadata: \(decryptedContent)")
            #endif
            PublishMetadataView(
                metadata: decryptedContent,
                mode: "Public" // Use public mode to show all metadata
            )
        } else if photo.isPublic,
                  let metadata = photo.content.metadata?.data(using: .utf8),
                  let jsonMetadata = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any] {
            #if DEBUG
            let _ = print("📊 Showing public metadata: \(jsonMetadata)")
            #endif
            PublishMetadataView(
                metadata: jsonMetadata,
                mode: "Public"
            )
        } else if !photo.isPublic && !photo.isLocked {
            #if DEBUG
            let _ = print("⏳ Photo is unlocked but no metadata available. Content: \(photo.content)")
            #endif
            // Show loading state for decryption in progress
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Decrypting metadata...")
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
            }
        }
    }
    
    private func decryptPhoto() {
        isDecrypting = true
        Task {
            do {
                print("🔓 Starting decryption for photo: \(photo.id)")
                
                // Use PhotoManager to decrypt
                try await PhotoManager.shared.decryptPhoto(photo)
                
                await MainActor.run {
                    isDecrypting = false
                    print("🔓 Updated UI with decrypted content")
                }
            } catch {
                print("❌ Decryption error: \(error)")
                await MainActor.run {
                    isDecrypting = false
                }
            }
        }
    }
} 