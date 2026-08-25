import Foundation
import CoreGraphics
import Accelerate

/// Utilities for high-performance pixel extraction and vector arithmetic using Accelerate (vDSP)
public enum PixelBuffer {
    
    /// Default pixel SAD tolerance for sensor noise
    public static let defaultPixelSADTolerance: Float = 3.5
    /// Standard maximum SAD range used for linear confidence scoring
    public static let maxConfidenceSADRange: Float = 50.0
    
    /// Extracts a grayscale representation of a sub-rect from a CGImage as raw UInt8 intensity values in Float representation (0.0 ... 255.0).
    /// - Parameters:
    ///   - image: Source CGImage
    ///   - rect: Target rectangle within image coordinates
    /// - Returns: Float array of grayscale intensity values (0.0 ... 255.0)
    public static func extractGrayscalePixels(from image: CGImage, rect: CGRect) -> [Float] {
        guard let cropped = image.safeCropping(to: rect) ?? image.cropping(to: rect) else {
            return []
        }
        
        let width = cropped.width
        let height = cropped.height
        let totalPixels = width * height
        guard totalPixels > 0 else { return [] }
        
        let grayColorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: grayColorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let dataPtr = context.data else {
            return []
        }
        
        context.interpolationQuality = .none
        context.setAllowsAntialiasing(false)
        
        // Flip CGContext vertically so memory row 0 corresponds to image top row (top-to-bottom)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Convert UInt8 buffer to Float buffer using vDSP with stride safety
        var floatPixels = [Float](repeating: 0, count: totalPixels)
        let actualBytesPerRow = context.bytesPerRow
        let uint8Ptr = dataPtr.bindMemory(to: UInt8.self, capacity: actualBytesPerRow * height)
        
        if actualBytesPerRow == width {
            vDSP_vfltu8(uint8Ptr, 1, &floatPixels, 1, vDSP_Length(totalPixels))
        } else {
            floatPixels.withUnsafeMutableBufferPointer { floatBuf in
                guard let floatBase = floatBuf.baseAddress else { return }
                for row in 0..<height {
                    let srcRow = uint8Ptr.advanced(by: row * actualBytesPerRow)
                    let dstRow = floatBase.advanced(by: row * width)
                    vDSP_vfltu8(srcRow, 1, dstRow, 1, vDSP_Length(width))
                }
            }
        }
        
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
        
        return bufferA.withUnsafeBufferPointer { ptrA in
            bufferB.withUnsafeBufferPointer { ptrB in
                guard let baseA = ptrA.baseAddress, let baseB = ptrB.baseAddress else { return Float.infinity }
                var diff = [Float](repeating: 0, count: count)
                return diff.withUnsafeMutableBufferPointer { diffPtr in
                    guard let baseDiff = diffPtr.baseAddress else { return Float.infinity }
                    return computeSADDirect(ptrA: baseA, ptrB: baseB, count: count, diffBuffer: baseDiff)
                }
            }
        }
    }
    
    /// Computes the Sum of Absolute Differences (SAD) directly between two memory pointers using a pre-allocated difference buffer.
    /// This eliminates repeated heap allocations during high-frequency matching loops.
    public static func computeSADDirect(
        ptrA: UnsafePointer<Float>,
        ptrB: UnsafePointer<Float>,
        count: Int,
        diffBuffer: UnsafeMutablePointer<Float>
    ) -> Float {
        guard count > 0 else { return Float.infinity }
        
        // diff = ptrA - ptrB
        vDSP_vsub(ptrB, 1, ptrA, 1, diffBuffer, 1, vDSP_Length(count))
        // diff = |diff|
        vDSP_vabs(diffBuffer, 1, diffBuffer, 1, vDSP_Length(count))
        // sad = sum(diff)
        var sad: Float = 0
        vDSP_sve(diffBuffer, 1, &sad, vDSP_Length(count))
        
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
