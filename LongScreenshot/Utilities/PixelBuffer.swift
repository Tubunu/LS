import Foundation
import CoreGraphics
import Accelerate

/// Utilities for high-performance pixel extraction and vector arithmetic using Accelerate (vDSP)
public enum PixelBuffer {
    
    /// Extracts a grayscale representation of a sub-rect from a CGImage as a normalized [Float] buffer (0...255).
    /// - Parameters:
    ///   - image: Source CGImage
    ///   - rect: Target rectangle within image coordinates
    /// - Returns: Float array of grayscale intensity values
    public static func extractGrayscalePixels(from image: CGImage, rect: CGRect) -> [Float] {
        let width = max(1, Int(rect.width))
        let height = max(1, Int(rect.height))
        let totalPixels = width * height
        
        var rawPixels = [UInt8](repeating: 0, count: totalPixels)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let context = CGContext(
            data: &rawPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return [Float](repeating: 0, count: totalPixels)
        }
        
        // Draw the cropped portion into our grayscale buffer
        context.interpolationQuality = .none
        context.setAllowsAntialiasing(false)
        
        // Invert Y coordinate since CoreGraphics has origin at bottom-left
        let drawRect = CGRect(
            x: -rect.origin.x,
            y: rect.origin.y + CGFloat(height) - CGFloat(image.height),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        
        context.draw(image, in: drawRect)
        
        // Convert UInt8 buffer to Float buffer using vDSP
        var floatPixels = [Float](repeating: 0, count: totalPixels)
        vDSP_vfltu8(rawPixels, 1, &floatPixels, 1, vDSP_Length(totalPixels))
        
        return floatPixels
    }
    
    /// Computes the Sum of Absolute Differences (SAD) between two Float pixel buffers.
    /// - Parameters:
    ///   - bufferA: First pixel buffer
    ///   - bufferB: Second pixel buffer
    /// - Returns: Normalized average difference per pixel
    public static func computeSAD(bufferA: [Float], bufferB: [Float]) -> Float {
        let count = min(bufferA.count, bufferB.count)
        guard count > 0 else { return Float.infinity }
        
        var diff = [Float](repeating: 0, count: count)
        var sad: Float = 0
        
        // diff = bufferA - bufferB
        vDSP_vsub(bufferB, 1, bufferA, 1, &diff, 1, vDSP_Length(count))
        // diff = |diff|
        vDSP_vabs(diff, 1, &diff, 1, vDSP_Length(count))
        // sad = sum(diff)
        vDSP_sve(diff, 1, &sad, vDSP_Length(count))
        
        return sad / Float(count)
    }
    
    /// Computes Normalized Cross Correlation (NCC) between two equal-sized pixel buffers
    public static func computeNCC(bufferA: [Float], bufferB: [Float]) -> Float {
        let count = min(bufferA.count, bufferB.count)
        guard count > 0 else { return 0 }
        
        var meanA: Float = 0
        var meanB: Float = 0
        vDSP_meanv(bufferA, 1, &meanA, vDSP_Length(count))
        vDSP_meanv(bufferB, 1, &meanB, vDSP_Length(count))
        
        var negMeanA = -meanA
        var negMeanB = -meanB
        var normA = [Float](repeating: 0, count: count)
        var normB = [Float](repeating: 0, count: count)
        
        vDSP_vsadd(bufferA, 1, &negMeanA, &normA, 1, vDSP_Length(count))
        vDSP_vsadd(bufferB, 1, &negMeanB, &normB, 1, vDSP_Length(count))
        
        var dotProd: Float = 0
        vDSP_dotpr(normA, 1, normB, 1, &dotProd, vDSP_Length(count))
        
        var sumSqA: Float = 0
        var sumSqB: Float = 0
        vDSP_svesq(normA, 1, &sumSqA, vDSP_Length(count))
        vDSP_svesq(normB, 1, &sumSqB, vDSP_Length(count))
        
        let denom = sqrt(sumSqA * sumSqB)
        guard denom > 1e-5 else { return 0 }
        return dotProd / denom
    }
}
