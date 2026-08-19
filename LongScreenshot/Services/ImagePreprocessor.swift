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
        guard let cgImage = image.cgImage else { return image }
        
        let scale = image.scale
        var cropY: CGFloat = 0
        var cropHeight: CGFloat = CGFloat(cgImage.height)
        let width = CGFloat(cgImage.width)
        
        // For images after the first, crop top fixed UI (status bar / nav bar)
        if index > 0 {
            let topCrop = config.statusBarHeight * scale
            cropY += topCrop
            cropHeight -= topCrop
        }
        
        // For images before the last, crop bottom fixed UI (home indicator / tab bar)
        if index < total - 1 {
            let bottomCrop = config.bottomSafeArea * scale
            cropHeight -= bottomCrop
        }
        
        guard cropHeight > 10 else { return image }
        
        let cropRect = CGRect(x: 0, y: cropY, width: width, height: cropHeight)
        guard let croppedCG = cgImage.safeCropping(to: cropRect) else { return image }
        
        return UIImage(cgImage: croppedCG, scale: scale, orientation: image.imageOrientation)
    }
    
    /// Batch preprocesses an array of screenshots
    public func preprocessBatch(_ images: [UIImage], config: CropConfig) -> [UIImage] {
        let total = images.count
        guard total > 1 else { return images }
        
        return images.enumerated().map { index, image in
            preprocessImage(image, at: index, total: total, config: config)
        }
    }
}
