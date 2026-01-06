import AppKit

class IconCache {
    static let shared = IconCache()
    
    // Key: "BundleID_Size" -> NSImage
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        // Reasonable limit for average use
        cache.countLimit = 500 
    }
    
    func icon(for app: AppItem, size: CGFloat) -> NSImage {
        // Round size to avoid float variance in keys
        let intSize = Int(size)
        // Check cache
        let key = NSString(string: "\(app.id)_\(intSize)")
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // If not found, resize and cache
        let original = app.icon  // This is the source standard icon
        let resized = resize(original, to: size)
        
        cache.setObject(resized, forKey: key)
        return resized
    }
    
    private func resize(_ image: NSImage, to size: CGFloat) -> NSImage {
        let newSize = NSSize(width: size, height: size)
        let newImage = NSImage(size: newSize)
        
        newImage.lockFocus()
        // High quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}
