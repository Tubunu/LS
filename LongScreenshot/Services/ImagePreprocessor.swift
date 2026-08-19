import UIKit
import CoreGraphics

/// Service responsible for cropping fixed status bars, navigation bars, and tab bars from screenshots
public struct ImagePreprocessor: Sendable {
    
    public init() {}
    
    /// Preprocesses a screenshot in a sequence by cropping the top and/or bottom fixed elements
    /// - Parameters:
    ///   - image: Source UIImage
    ///   - index: Zero-based index of the image in the scroll sequence
    ///   - total: Total number of screenshots in the sequence
    ///   - config: Crop configuration parameters
    /// - Returns: Cropped UIImage
    public func preprocessImage(_ image: UIImage, at index: Int, total: Int, config: CropConfig) -> UIImage {
        let normalized = image.normalizedOrientation()
        guard let cgImage = normalized.cgImage else { return normalized }
        
        let width = CGFloat(cgImage.width)
        let effectiveScale: CGFloat
        if normalized.scale > 1.0 {
            effectiveScale = normalized.scale
        } else if width >= 1000 {
            effectiveScale = 3.0
        } else if width >= 640 {
            effectiveScale = 2.0
        } else {
            effectiveScale = 1.0
        }
        
        let effectiveConfig = (config == .standard) ? CropConfig.adaptive(for: CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))) : config
        
        var cropY: CGFloat = 0
        var cropHeight: CGFloat = CGFloat(cgImage.height)
        
        // For images after the first, crop top fixed UI (status bar / nav bar)
        if index > 0 {
            let topCrop = effectiveConfig.statusBarHeight * effectiveScale
            cropY += topCrop
            cropHeight -= topCrop
        }
        
        // For images before the last, crop bottom fixed UI (home indicator / tab bar)
        if index < total - 1 {
            let bottomCrop = effectiveConfig.bottomSafeArea * effectiveScale
            cropHeight -= bottomCrop
        }
        
        guard cropHeight > 10 else { return normalized }
        
        let cropRect = CGRect(x: 0, y: cropY, width: width, height: cropHeight)
        guard let croppedCG = cgImage.safeCropping(to: cropRect) else { return normalized }
        
        return UIImage(cgImage: croppedCG, scale: effectiveScale, orientation: .up)
    }
    
    /// Normalizes the pixel width of an image to a target width maintaining aspect ratio
    public func normalizeWidth(of image: UIImage, targetWidth: CGFloat) -> UIImage {
        let normalized = image.normalizedOrientation()
        guard let cg = normalized.cgImage, CGFloat(cg.width) != targetWidth, targetWidth > 0 else {
            return normalized
        }
        
        let originalWidth = CGFloat(cg.width)
        let originalHeight = CGFloat(cg.height)
        guard originalWidth > 0 else { return normalized }
        
        let ratio = targetWidth / originalWidth
        let targetHeight = (originalHeight * ratio).rounded()
        guard targetHeight > 0 else { return normalized }
        
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Batch preprocesses an array of screenshots
    public func preprocessBatch(_ images: [UIImage], config: CropConfig) -> [UIImage] {
        let total = images.count
        guard total > 1 else { return images }
        
        // Determine primary baseline width from first valid image
        let firstNormalized = images[0].normalizedOrientation()
        let targetWidth = CGFloat(firstNormalized.cgImage?.width ?? Int(firstNormalized.size.width * firstNormalized.scale))
        
        let widthNormalizedImages = images.map { img in
            normalizeWidth(of: img, targetWidth: targetWidth)
        }
        
        return widthNormalizedImages.enumerated().map { index, image in
            preprocessImage(image, at: index, total: total, config: config)
        }
    }
}
