import UIKit

public extension UIImage {
    /// Generates a thumbnail image constrained to a maximum bounding size maintaining aspect ratio
    func resizedThumbnail(maxSize: CGFloat) -> UIImage {
        let originalSize = self.size
        guard originalSize.width > 0, originalSize.height > 0 else { return self }
        
        let ratio = min(maxSize / originalSize.width, maxSize / originalSize.height)
        if ratio >= 1.0 { return self }
        
        let newSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = self.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
