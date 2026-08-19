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
        overlapOffset: Int = 0,
        overlapHeight: Int,
        blendTransitionWidth: Int = 40
    ) -> CGImage? {
        let width = image1.width
        guard width == image2.width, width > 0 else { return nil }
        
        let nonOverlapTopHeight = max(0, image1.height - overlapHeight)
        let totalHeight = max(image1.height, nonOverlapTopHeight - overlapOffset + image2.height)
        guard totalHeight > 0 else { return nil }
        
        let size = CGSize(width: CGFloat(width), height: CGFloat(totalHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let cgWidth = CGFloat(width)
            
            // 1. Draw entire Image 1 (covers top non-overlapping and overlap base)
            UIImage(cgImage: image1).draw(in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(image1.height)))
            
            let blendHeight = max(0, min(overlapHeight, blendTransitionWidth))
            let blendStartY = CGFloat(nonOverlapTopHeight)
            
            // 2. Blend the overlap transition zone smoothly with contiguous slices
            if blendHeight > 0 {
                let steps = min(blendHeight, 20)
                
                for step in 0..<steps {
                    let startY = (CGFloat(step) * CGFloat(blendHeight) / CGFloat(steps)).rounded()
                    let endY = (CGFloat(step + 1) * CGFloat(blendHeight) / CGFloat(steps)).rounded()
                    let sliceHeight = endY - startY
                    guard sliceHeight > 0 else { continue }
                    
                    let alpha = CGFloat(step + 1) / CGFloat(steps + 1)
                    let destY = blendStartY + startY
                    let srcY = CGFloat(overlapOffset) + startY
                    
                    let sliceRect = CGRect(x: 0, y: srcY, width: cgWidth, height: sliceHeight).integral
                    if let slice = image2.safeCropping(to: sliceRect) {
                        ctx.saveGState()
                        ctx.setAlpha(alpha)
                        UIImage(cgImage: slice).draw(in: CGRect(x: 0, y: destY, width: cgWidth, height: sliceHeight))
                        ctx.restoreGState()
                    }
                }
            }
            
            // 3. Draw the remaining portion of Image 2 (from blendHeight to image2.height) with full opacity
            let remainingImage2Height = max(0, image2.height - overlapOffset - blendHeight)
            if remainingImage2Height > 0 {
                let srcY = CGFloat(overlapOffset + blendHeight)
                let bottomRect = CGRect(x: 0, y: srcY, width: cgWidth, height: CGFloat(remainingImage2Height)).integral
                if let bottomPart = image2.safeCropping(to: bottomRect) {
                    UIImage(cgImage: bottomPart).draw(in: CGRect(x: 0, y: blendStartY + CGFloat(blendHeight), width: cgWidth, height: CGFloat(remainingImage2Height)))
                }
            }
        }
        
        return image.cgImage
    }
}
