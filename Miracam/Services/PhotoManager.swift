import Foundation
import UIKit

class PhotoManager: ObservableObject {
    static let shared = PhotoManager()
    
    // Published states
    @Published private(set) var photos: [StoredPhoto] = []
    @Published private(set) var decryptedPhotos: [String: StoredPhoto] = [:]
    @Published private(set) var decryptedMetadata: [String: [String: Any]] = [:]
    @Published private(set) var photoStatuses: [String: CameraStatus] = [:]
    @Published private(set) var isDecryptingAll = false
    @Published private(set) var isUnlocked = false
    
    // Storage properties
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var photosDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("stored_photos")
    }
    
    private var thumbnailsDirectory: URL {
        photosDirectory.appendingPathComponent("thumbnails")
    }
    
    private var metadataFile: URL {
        photosDirectory.appendingPathComponent("photos_metadata.json")
    }
    
    private init() {
        createDirectoriesIfNeeded()
        loadPhotos()
    }
    
    // MARK: - Storage Operations
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func loadPhotos() {
        do {
            let data = try Data(contentsOf: metadataFile)
            let loadedPhotos = try decoder.decode([StoredPhoto].self, from: data)
            
            // Remove duplicates and sort
            var uniquePhotos: [String: StoredPhoto] = [:]
            for photo in loadedPhotos {
                if let existing = uniquePhotos[photo.id] {
                    if photo.timestamp > existing.timestamp {
                        uniquePhotos[photo.id] = photo
                    }
                } else {
                    uniquePhotos[photo.id] = photo
                }
            }
            
            photos = uniquePhotos.values.sorted { $0.timestamp > $1.timestamp }
            
            // Log status
            print("📸 Loaded \(photos.count) photos (\(photos.filter { $0.isPublic }.count) public, \(photos.filter { !$0.isPublic }.count) private)")
            
            // Auto-decrypt if unlocked
            if isUnlocked {
                Task {
                    await decryptAllPhotos()
                }
            }
        } catch {
            print("Error loading photos: \(error)")
            photos = []
        }
    }
    
    private func saveMetadata() throws {
        let data = try encoder.encode(photos)
        try data.write(to: metadataFile)
    }
    
    // MARK: - Public Methods
    
    @MainActor
    func savePhoto(from payload: CameraPayload, thumbnail: UIImage, withId id: String? = nil) async throws {
        let photoId = id ?? UUID().uuidString
        let isPublic = payload.content.type == "public"
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(photoId).jpg")
        
        // Save thumbnail for public photos
        if isPublic {
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.5) {
                try thumbnailData.write(to: thumbnailURL)
            }
        }
        
        // Create photo content
        let content = StoredPhoto.PhotoContent(
            mediadata: isPublic ? payload.content.value.mediadata : nil,
            metadata: isPublic ? payload.content.value.metadata : nil,
            encrypted: isPublic ? nil : payload.content.value.encrypted
        )
        
        let photo = StoredPhoto(
            id: photoId,
            timestamp: Date(),
            isPublic: isPublic,
            content: content,
            thumbnailPath: isPublic ? thumbnailURL.path : ""
        )
        
        // Update photos array
        photos.removeAll { $0.id == photoId }
        photos.append(photo)
        photos.sort { $0.timestamp > $1.timestamp }
        
        try saveMetadata()
        
        // Auto-decrypt if unlocked
        if !isPublic && isUnlocked {
            try await decryptPhoto(photo)
        }
    }
    
    @MainActor
    func updatePhotoStatus(id: String, status: CameraStatus) {
        // Don't update if the photo is already in ready state
        if photoStatuses[id] != .ready {
            photoStatuses[id] = status
            
            // If status is ready, remove it after a short delay
            if status == .ready {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    photoStatuses.removeValue(forKey: id)
                }
            }
        }
    }
    
    @MainActor
    func clearPhotoStatus(id: String) {
        // First set to ready state
        photoStatuses[id] = .ready
        
        // Then remove after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            photoStatuses.removeValue(forKey: id)
        }
    }
    
    func clearAllPhotos() async {
        await MainActor.run {
            do {
                try fileManager.removeItem(at: photosDirectory)
                createDirectoriesIfNeeded()
                photos.removeAll()
                decryptedPhotos.removeAll()
                decryptedMetadata.removeAll()
                photoStatuses.removeAll()
                try saveMetadata()
            } catch {
                print("Error clearing photos: \(error)")
            }
        }
    }
    
    // MARK: - Encryption/Decryption
    
    @MainActor
    func toggleDecryptionState() async {
        if !isUnlocked {
            await decryptAllPhotos()
        } else {
            clearDecryptedContent()
        }
    }
    
    @MainActor
    private func decryptAllPhotos() async {
        isDecryptingAll = true
        isUnlocked = true
        
        for photo in photos where !photo.isPublic {
            do {
                try await decryptPhoto(photo)
            } catch {
                print("Error decrypting photo \(photo.id): \(error)")
            }
        }
        
        isDecryptingAll = false
    }
    
    @MainActor
    private func clearDecryptedContent() {
        decryptedPhotos.removeAll()
        decryptedMetadata.removeAll()
        isUnlocked = false
    }
    
    @MainActor
    func decryptPhoto(_ photo: StoredPhoto) async throws {
        guard !photo.isPublic,
              let encryptedString = photo.content.encrypted,
              let encryptedData = Data(base64Encoded: encryptedString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid encrypted data"])
        }
        
        let decryptedData = try await ContentKeyManager.shared.decrypt(encryptedData)
        
        guard let decryptedJson = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
              let mediadata = decryptedJson["mediadata"] as? String,
              let metadata = decryptedJson["metadata"] as? [String: Any] else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid decrypted data"])
        }
        
        // Save decrypted thumbnail
        if let imageData = Data(base64Encoded: mediadata),
           let image = UIImage(data: imageData) {
            let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(photo.id)_decrypted.jpg")
            if let thumbnailData = image.jpegData(compressionQuality: 0.5) {
                try thumbnailData.write(to: thumbnailURL)
            }
            
            let decryptedPhoto = StoredPhoto(
                id: photo.id,
                timestamp: photo.timestamp,
                isPublic: photo.isPublic,
                content: photo.content,
                thumbnailPath: thumbnailURL.path,
                isDecrypted: true
            )
            
            // Update both photo and metadata
            decryptedPhotos[photo.id] = decryptedPhoto
            decryptedMetadata[photo.id] = metadata
        }
    }
} 