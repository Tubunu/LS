import UIKit
import CoreGraphics

/// Service responsible for rendering and blending overlapping image regions seamlessly
public actor ImageBlender {
    
    public init() {}
    
    /// Blends two images along their calculated overlap region using gradient alpha transition
    /// - Parameters:
    ///   - image1: The upper image
    ///   - image2: The lower image
    ///   - overlapOffset: Offset in image2 where overlap starts
    ///   - overlapHeight: Total height of the overlapping region
    ///   - blendTransitionWidth: Height of the smooth alpha blend transition band (in px)
    /// - Returns: Composite blended CGImage
    public func blendTwoImages(
        image1: CGImage,
        image2: CGImage,
        overlapOffset: Int,
        overlapHeight: Int,
        blendTransitionWidth: Int = 40
    ) -> CGImage? {
        let width = image1.width
        guard width == image2.width, width > 0 else { return nil }
        
        let totalHeight = image1.height + image2.height - overlapHeight
        guard totalHeight > 0 else { return nil }
        
        let size = CGSize(width: CGFloat(width), height: CGFloat(totalHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let nonOverlapTopHeight = max(0, image1.height - overlapHeight)
            let cgWidth = CGFloat(width)
            
            // 1. Draw non-overlapping top portion of Image 1
            if nonOverlapTopHeight > 0,
               let topPart = image1.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(nonOverlapTopHeight))) {
                ctx.draw(topPart, in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(nonOverlapTopHeight)))
            }
            
            // 2. Blend the overlap transition zone
            let blendHeight = min(overlapHeight, max(10, blendTransitionWidth))
            let blendStartY = nonOverlapTopHeight
            
            for row in 0..<blendHeight {
                let alpha2 = CGFloat(row) / CGFloat(blendHeight)
                let alpha1 = 1.0 - alpha2
                let currentY = CGFloat(blendStartY + row)
                
                // Draw slice from image1
                let img1RowY = image1.height - overlapHeight + row
                if img1RowY >= 0 && img1RowY < image1.height,
                   let r1 = image1.safeCropping(to: CGRect(x: 0, y: CGFloat(img1RowY), width: cgWidth, height: 1.0)) {
                    ctx.saveGState()
                    ctx.setAlpha(alpha1)
                    ctx.draw(r1, in: CGRect(x: 0, y: currentY, width: cgWidth, height: 1.0))
                    ctx.restoreGState()
                }
                
                // Draw slice from image2
                let img2RowY = row
                if img2RowY >= 0 && img2RowY < image2.height,
                   let r2 = image2.safeCropping(to: CGRect(x: 0, y: CGFloat(img2RowY), width: cgWidth, height: 1.0)) {
                    ctx.saveGState()
                    ctx.setAlpha(alpha2)
                    ctx.draw(r2, in: CGRect(x: 0, y: currentY, width: cgWidth, height: 1.0))
                    ctx.restoreGState()
                }
            }
            
            // 3. Draw remaining overlap region from Image 2
            let remainingOverlapHeight = overlapHeight - blendHeight
            if remainingOverlapHeight > 0,
               let midPart = image2.safeCropping(to: CGRect(x: 0, y: CGFloat(blendHeight), width: cgWidth, height: CGFloat(remainingOverlapHeight))) {
                ctx.draw(midPart, in: CGRect(x: 0, y: CGFloat(blendStartY + blendHeight), width: cgWidth, height: CGFloat(remainingOverlapHeight)))
            }
            
            // 4. Draw non-overlapping bottom portion of Image 2
            let bottomNonOverlapHeight = image2.height - overlapHeight
            if bottomNonOverlapHeight > 0,
               let bottomPart = image2.safeCropping(to: CGRect(x: 0, y: CGFloat(overlapHeight), width: cgWidth, height: CGFloat(bottomNonOverlapHeight))) {
                ctx.draw(bottomPart, in: CGRect(x: 0, y: CGFloat(nonOverlapTopHeight + overlapHeight), width: cgWidth, height: CGFloat(bottomNonOverlapHeight)))
            }
        }
        
        return image.cgImage
    }
}
