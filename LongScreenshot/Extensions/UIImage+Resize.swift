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
    
    /// Normalizes image orientation to .up so that CGImage pixel data matches visual orientation
    func normalizedOrientation() -> UIImage {
        guard self.imageOrientation != .up else { return self }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
    
    /// Scales down the image by a given quality/scale ratio (0.1 ... 1.0)
    func scaled(by factor: CGFloat) -> UIImage {
        guard factor > 0 && factor < 1.0 else { return self }
        let targetSize = CGSize(width: self.size.width * factor, height: self.size.height * factor)
        guard targetSize.width > 10 && targetSize.height > 10 else { return self }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
