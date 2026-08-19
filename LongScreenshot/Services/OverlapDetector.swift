import Foundation
import CoreGraphics
import Accelerate

/// Service responsible for detecting pixel-accurate overlapping regions between consecutive screenshots
public actor OverlapDetector {
    
    private static let maxSADConfidenceScale: Float = 60.0
    private static let minAmbiguitySADThreshold: Float = 2.0
    private static let minConfidenceThreshold: Float = 0.50
    
    public init() {}
    
    /// Finds the optimal overlap offset and vertical displacement between image1 and image2
    /// using multi-band safe sampling to avoid floating buttons at bottom and sticky headers at top.
    /// - Parameters:
    ///   - image1: The upper image (CGImage)
    ///   - image2: The lower image (CGImage)
    ///   - referenceStripHeight: Height of sample strips (default: 160px)
    ///   - searchRange: Maximum search range (0 = full height)
    /// - Returns: OverlapResult with verified displacement and overlap height
    public func findOverlap(
        bottomOf image1: CGImage,
        topOf image2: CGImage,
        referenceStripHeight: Int = 160,
        searchRange: Int = 0
    ) -> OverlapResult? {
        let width1 = image1.width
        let width2 = image2.width
        
        // Ensure same width for alignment
        guard width1 == width2, width1 > 0 else { return nil }
        let width = width1
        
        let height1 = image1.height
        let height2 = image2.height
        
        let stripHeight = min(referenceStripHeight, min(height1 / 4, height2 / 4))
        guard stripHeight >= 20 else { return nil }
        
        let searchAreaHeight = searchRange > 0 ? min(searchRange, height2) : height2
        let maxSearchOffset = searchAreaHeight - stripHeight
        guard maxSearchOffset > 0 else { return nil }
        
        // Extract full search area from image2 once
        let searchRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(searchAreaHeight))
        let searchArea = PixelBuffer.extractGrayscalePixels(from: image2, rect: searchRect)
        let stripPixelCount = stripHeight * width
        guard searchArea.count >= searchAreaHeight * width else { return nil }
        
        // Multi-depth candidate sampling ratios in image1 (65%, 55%, 75%, 45%, 82%)
        // This avoids bottom floating buttons / toolbars and top sticky headers
        let candidateRatios: [Double] = [0.65, 0.55, 0.75, 0.45, 0.82]
        
        var bestOverallResult: OverlapResult? = nil
        var bestOverallConfidence: Float = 0.0
        var diffBuffer = [Float](repeating: 0, count: stripPixelCount)
        
        for ratio in candidateRatios {
            let refCenterY = Int(Double(height1) * ratio)
            let refY = max(0, min(height1 - stripHeight, refCenterY - stripHeight / 2))
            
            let refRect = CGRect(x: 0, y: CGFloat(refY), width: CGFloat(width), height: CGFloat(stripHeight))
            let refStrip = PixelBuffer.extractGrayscalePixels(from: image1, rect: refRect)
            guard refStrip.count == stripPixelCount else { continue }
            
            var bestOffset = 0
            var bestSAD: Float = Float.infinity
            var minSADCount = 0
            
            let found = refStrip.withUnsafeBufferPointer { refPtr -> Bool in
                guard let refBase = refPtr.baseAddress else { return false }
                return searchArea.withUnsafeBufferPointer { searchPtr -> Bool in
                    guard let searchBase = searchPtr.baseAddress else { return false }
                    return diffBuffer.withUnsafeMutableBufferPointer { diffPtr -> Bool in
                        guard let diffBase = diffPtr.baseAddress else { return false }
                        
                        for offset in 0..<maxSearchOffset {
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
            
            guard found else { continue }
            
            var confidence = max(0, 1.0 - bestSAD / Self.maxSADConfidenceScale)
            if minSADCount > 3 && bestSAD < Self.minAmbiguitySADThreshold {
                confidence = max(0, confidence - 0.4)
            }
            
            // Displacement between image1 and image2: deltaY = refY - bestOffset
            let deltaY = refY - bestOffset
            // Valid scroll motion: image2 is scrolled down relative to image1, so deltaY must be positive
            guard deltaY > 10, deltaY < height1 else { continue }
            
            let overlapHeight = height1 - deltaY
            
            if confidence >= Self.minConfidenceThreshold && confidence > bestOverallConfidence {
                bestOverallConfidence = confidence
                let centerRefY = refY + stripHeight / 2
                let centerMatchY = bestOffset + stripHeight / 2
                bestOverallResult = OverlapResult(
                    refY: centerRefY,
                    matchY: centerMatchY,
                    confidence: confidence,
                    overlapHeight: overlapHeight
                )
                // If confidence is exceptionally high, early return
                if confidence > 0.85 {
                    break
                }
            }
        }
        
        if let result = bestOverallResult {
            AppLogger.stitching.info("Overlap detected successfully: overlapHeight=\(result.overlapHeight), confidence=\(result.confidence)")
            return result
        }
        
        AppLogger.stitching.warning("Overlap confidence too low across all multi-band candidates")
        return nil
    }
}
