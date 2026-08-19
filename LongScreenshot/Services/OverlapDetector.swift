import Foundation
import CoreGraphics
import Accelerate

/// Service responsible for detecting pixel-accurate overlapping regions between consecutive screenshots
public actor OverlapDetector {
    
    private static let maxSADConfidenceScale: Float = 60.0
    private static let minAmbiguitySADThreshold: Float = 2.0
    private static let minConfidenceThreshold: Float = 0.50
    
    public init() {}
    
    /// Finds the optimal overlap offset between the bottom portion of image1 and top portion of image2
    /// - Parameters:
    ///   - image1: The upper image (CGImage)
    ///   - image2: The lower image (CGImage)
    ///   - referenceStripHeight: Height of the sample strip taken from the bottom of image1 (default: 200px)
    ///   - searchRange: Maximum height to search in image2 (0 = full height of image2)
    /// - Returns: OverlapResult if a match with confidence >= 0.50 is found, nil otherwise
    public func findOverlap(
        bottomOf image1: CGImage,
        topOf image2: CGImage,
        referenceStripHeight: Int = 200,
        searchRange: Int = 0
    ) -> OverlapResult? {
        let width1 = image1.width
        let width2 = image2.width
        
        // Ensure same width for alignment
        guard width1 == width2, width1 > 0 else { return nil }
        let width = width1
        
        let height1 = image1.height
        let height2 = image2.height
        
        let stripHeight = min(referenceStripHeight, min(height1 / 3, height2 / 3))
        guard stripHeight >= 20 else { return nil }
        
        let actualSearchRange = searchRange > 0 ? min(searchRange, height2) : height2
        let maxOffset = actualSearchRange - stripHeight
        guard maxOffset > 0 else { return nil }
        
        // 1. Extract reference strip from the bottom of image1 (rows: height1 - stripHeight ..< height1)
        let refRect = CGRect(
            x: 0,
            y: CGFloat(height1 - stripHeight),
            width: CGFloat(width),
            height: CGFloat(stripHeight)
        )
        let refStrip = PixelBuffer.extractGrayscalePixels(from: image1, rect: refRect)
        
        // 2. Extract search area from the top of image2 (rows: 0 ..< actualSearchRange)
        let searchRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(actualSearchRange)
        )
        let searchArea = PixelBuffer.extractGrayscalePixels(from: image2, rect: searchRect)
        
        let stripPixelCount = stripHeight * width
        guard refStrip.count == stripPixelCount, searchArea.count >= (maxOffset + stripHeight) * width else {
            return nil
        }
        
        var bestOffset = 0
        var bestSAD: Float = Float.infinity
        var minSADCount = 0
        
        // 3. Slide the reference strip across the search area using zero-allocation pointer arithmetic
        var diffBuffer = [Float](repeating: 0, count: stripPixelCount)
        
        let foundBest = refStrip.withUnsafeBufferPointer { refPtr -> Bool in
            guard let refBase = refPtr.baseAddress else { return false }
            return searchArea.withUnsafeBufferPointer { searchPtr -> Bool in
                guard let searchBase = searchPtr.baseAddress else { return false }
                return diffBuffer.withUnsafeMutableBufferPointer { diffPtr -> Bool in
                    guard let diffBase = diffPtr.baseAddress else { return false }
                    
                    for offset in 0..<maxOffset {
                        let currentSearchPtr = searchBase.advanced(by: offset * width)
                        let sad = PixelBuffer.computeSADDirect(
                            ptrA: refBase,
                            ptrB: currentSearchPtr,
                            count: stripPixelCount,
                            diffBuffer: diffBase
                        )
                        
                        if sad < bestSAD - 0.05 {
                            bestSAD = sad
                            bestOffset = offset
                            minSADCount = 1
                        } else if abs(sad - bestSAD) <= 0.05 {
                            minSADCount += 1
                        }
                    }
                    return true
                }
            }
        }
        
        guard foundBest else { return nil }
        
        // 4. Calculate confidence: 0 SAD difference -> 1.0 confidence, difference of 50 -> 0.0
        var confidence = max(0, 1.0 - bestSAD / Self.maxSADConfidenceScale)
        
        // Ambiguity suppression: If multiple disparate offsets produce near-identical minimum SAD (e.g. flat solid color area), penalize confidence
        if minSADCount > 3 && bestSAD < Self.minAmbiguitySADThreshold {
            confidence = max(0, confidence - 0.4)
        }
        
        guard confidence >= Self.minConfidenceThreshold else {
            AppLogger.stitching.warning("Overlap confidence too low: \(confidence, privacy: .public), bestSAD: \(bestSAD, privacy: .public)")
            return nil
        }
        
        // Geometry Note:
        // - The reference strip is taken from image1's bottom: [height1 - stripHeight, height1].
        // - In image2, this strip matches at [bestOffset, bestOffset + stripHeight].
        // - Therefore, all of image2 from row 0 to (bestOffset + stripHeight) overlaps with the bottom of image1.
        // - Total overlapping height between image1 and image2 is thus exactly `stripHeight + bestOffset`.
        let overlapHeight = stripHeight + bestOffset
        return OverlapResult(offset: bestOffset, confidence: confidence, overlapHeight: overlapHeight)
    }
}
