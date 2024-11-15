import Foundation

struct StoredPhoto: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let isPublic: Bool
    let content: PhotoContent
    var thumbnailPath: String
    var isDecrypted: Bool
    
    init(id: String, timestamp: Date, isPublic: Bool, content: PhotoContent, thumbnailPath: String, isDecrypted: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.isPublic = isPublic
        self.content = content
        self.thumbnailPath = thumbnailPath
        self.isDecrypted = isDecrypted
    }
    
    struct PhotoContent: Codable {
        // For public photos and decrypted private photos
        let mediadata: String?
        let metadata: String?
        
        // For private photos (always keep the encrypted data)
        let encrypted: String?
    }
    
    // Computed property to determine if photo is locked
    var isLocked: Bool {
        return !isPublic && !isDecrypted
    }
    
    // Computed property to determine if thumbnail should be shown
    var shouldShowThumbnail: Bool {
        return isPublic || isDecrypted
    }
} 