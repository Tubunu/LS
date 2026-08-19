import Foundation
import CoreGraphics
import Accelerate

/// Service responsible for detecting pixel-accurate overlapping regions between consecutive screenshots
public actor OverlapDetector {
    
    public init() {}
    
    /// Finds the optimal overlap offset between the bottom portion of image1 and top portion of image2
    /// - Parameters:
    ///   - image1: The upper image (CGImage)
    ///   - image2: The lower image (CGImage)
    ///   - referenceStripHeight: Height of the sample strip taken from the bottom of image1 (default: 200px)
    ///   - searchRange: Maximum height to search in image2 (0 = 80% of image2 height)
    /// - Returns: OverlapResult if a match with confidence > 0.7 is found, nil otherwise
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
        
        let actualSearchRange = searchRange > 0 ? min(searchRange, height2) : Int(Double(height2) * 0.85)
        let maxOffset = actualSearchRange - stripHeight
        guard maxOffset > 0 else { return nil }
        
        // 1. Extract reference strip from the bottom of image1
        let refRect = CGRect(
            x: 0,
            y: CGFloat(height1 - stripHeight),
            width: CGFloat(width),
            height: CGFloat(stripHeight)
        )
        let refStrip = PixelBuffer.extractGrayscalePixels(from: image1, rect: refRect)
        
        // 2. Extract search area from the top of image2
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
        
        // 3. Slide the reference strip across the search area in steps
        for offset in 0..<maxOffset {
            let startIdx = offset * width
            let endIdx = startIdx + stripPixelCount
            guard endIdx <= searchArea.count else { break }
            
            let searchSlice = Array(searchArea[startIdx..<endIdx])
            let sad = PixelBuffer.computeSAD(bufferA: refStrip, bufferB: searchSlice)
            
            if sad < bestSAD {
                bestSAD = sad
                bestOffset = offset
            }
        }
        
        // 4. Calculate confidence: 0 difference -> 1.0 confidence, difference of 50 -> 0.0
        let confidence = max(0, 1.0 - bestSAD / 50.0)
        
        guard confidence >= 0.65 else {
            AppLogger.stitching.warning("Overlap confidence too low: \(confidence, privacy: .public), bestSAD: \(bestSAD, privacy: .public)")
            return nil
        }
        
        let overlapHeight = stripHeight + bestOffset
        return OverlapResult(offset: bestOffset, confidence: confidence, overlapHeight: overlapHeight)
    }
}
