import Foundation
import CoreGraphics
import Accelerate

/// Service responsible for detecting pixel-accurate overlapping regions between consecutive screenshots
public actor OverlapDetector {
    
    private static let maxSADConfidenceScale: Float = 60.0
    private static let minAmbiguitySADThreshold: Float = 2.0
    private static let minConfidenceThreshold: Float = 0.50
    
    public init() {}
    
    /// Refines the vertical displacement between consecutive keyframes within the active scrolling ROI.
    /// Uses prior displacement knowledge, excludes static headers/footers, and clips right-edge scrollbars.
    /// - Parameters:
    ///   - image1: The upper/previous keyframe (CGImage)
    ///   - image2: The lower/subsequent keyframe (CGImage)
    ///   - expectedDeltaY: Approximate displacement from motion tracking
    ///   - topCrop: Top fixed UI height to exclude (Status bar, Nav bar)
    ///   - bottomCrop: Bottom fixed UI height to exclude (Home bar, Tab bar)
    ///   - referenceStripHeight: Height of the sample strip in pixels
    /// - Returns: Verified pixel-accurate vertical displacement (in pixels) and confidence score
    public func findRefinedDisplacement(
        from image1: CGImage,
        to image2: CGImage,
        expectedDeltaY: CGFloat,
        topCrop: Int = 0,
        bottomCrop: Int = 0,
        referenceStripHeight: Int = 140
    ) -> (deltaY: Int, confidence: Float) {
        let width = image1.width
        let height1 = image1.height
        let height2 = image2.height
        
        guard width == image2.width, width > 100, height1 > 100, height2 > 100 else {
            return (deltaY: max(1, Int(expectedDeltaY.rounded())), confidence: 0.0)
        }
        
        let roiTop = max(0, min(topCrop, height1 / 3))
        let roiBottom = max(roiTop + 60, height1 - max(0, min(bottomCrop, height1 / 3)))
        let roiHeight = roiBottom - roiTop
        
        // Exclude left 3% and right 7% margins to avoid iOS scroll indicators / dynamic icons
        let leftMargin = max(8, Int(Double(width) * 0.03))
        let rightMargin = max(16, Int(Double(width) * 0.07))
        let cropWidth = width - leftMargin - rightMargin
        guard cropWidth > 40, roiHeight > 60 else {
            return (deltaY: max(1, Int(expectedDeltaY.rounded())), confidence: 0.0)
        }
        
        let stripH = min(referenceStripHeight, max(30, roiHeight / 4))
        let stripPixelCount = stripH * cropWidth
        
        let priorDelta = max(1, Int(expectedDeltaY.rounded()))
        // Determine physical overlap zone in image1:
        // Since content moved UP by priorDelta, the portion of image1 still visible in image2 is:
        // [roiTop + priorDelta, roiBottom]
        let minRefY = roiTop + priorDelta
        let maxRefY = roiBottom - stripH
        
        let candidateYPositions: [Int]
        if maxRefY >= minRefY {
            let range = maxRefY - minRefY
            // Generate 5 candidate positions across the physical overlap zone
            candidateYPositions = (1...5).map { step in
                minRefY + (range * step) / 6
            }
        } else {
            // Fallback if displacement approaches or exceeds effective content height
            candidateYPositions = [max(roiTop, roiBottom - stripH - 5)]
        }
        
        var diffBuffer = [Float](repeating: 0, count: stripPixelCount)
        
        // Search radius around expected displacement (+/- 200px or 45% of prior)
        let searchRadius = max(200, Int(Double(priorDelta) * 0.45))
        
        struct CandidateObservation {
            let deltaY: Int
            let confidence: Float
            let sad: Float
            let stdDev: Float
        }
        var observations: [CandidateObservation] = []
        
        for refY in candidateYPositions {
            guard refY >= roiTop, refY + stripH <= roiBottom else { continue }
            
            let refRect = CGRect(x: CGFloat(leftMargin), y: CGFloat(refY), width: CGFloat(cropWidth), height: CGFloat(stripH))
            let refStrip = PixelBuffer.extractGrayscalePixels(from: image1, rect: refRect)
            guard refStrip.count == stripPixelCount else { continue }
            
            // Texture check: avoid completely flat untextured blank white or solid black strips (< 0.5)
            let refStdDev = PixelBuffer.computeStdDev(buffer: refStrip)
            if refStdDev < 0.5 && !observations.isEmpty {
                continue
            }
            
            // Expected match position in image2
            let expectedMatchY = refY - priorDelta
            let minMatchY = max(roiTop, expectedMatchY - searchRadius)
            let maxMatchY = min(roiBottom - stripH, expectedMatchY + searchRadius)
            
            guard maxMatchY >= minMatchY else { continue }
            
            let searchHeight = (maxMatchY - minMatchY) + stripH
            let maxSearchOffset = searchHeight - stripH
            guard maxSearchOffset >= 0 else { continue }
            
            let searchRect = CGRect(x: CGFloat(leftMargin), y: CGFloat(minMatchY), width: CGFloat(cropWidth), height: CGFloat(searchHeight))
            let searchArea = PixelBuffer.extractGrayscalePixels(from: image2, rect: searchRect)
            guard searchArea.count >= searchHeight * cropWidth else { continue }
            
            var coarseBestOffset = 0
            var coarseBestSAD: Float = Float.infinity
            
            // Stage 1: Coarse search (stride: 2px)
            let coarseFound = refStrip.withUnsafeBufferPointer { refPtr -> Bool in
                guard let refBase = refPtr.baseAddress else { return false }
                return searchArea.withUnsafeBufferPointer { searchPtr -> Bool in
                    guard let searchBase = searchPtr.baseAddress else { return false }
                    return diffBuffer.withUnsafeMutableBufferPointer { diffPtr -> Bool in
                        guard let diffBase = diffPtr.baseAddress else { return false }
                        
                        for offset in stride(from: 0, through: maxSearchOffset, by: 2) {
                            let currentSearchPtr = searchBase.advanced(by: offset * cropWidth)
                            let sad = PixelBuffer.computeSADDirect(
                                ptrA: refBase,
                                ptrB: currentSearchPtr,
                                count: stripPixelCount,
                                diffBuffer: diffBase
                            )
                            if sad < coarseBestSAD {
                                coarseBestSAD = sad
                                coarseBestOffset = offset
                            }
                        }
                        return true
                    }
                }
            }
            guard coarseFound else { continue }
            
            // Stage 2: Fine search (stride: 1px) in +/- 4px window around coarse optimum
            let fineMinOffset = max(0, coarseBestOffset - 4)
            let fineMaxOffset = min(maxSearchOffset, coarseBestOffset + 4)
            var localBestOffset = coarseBestOffset
            var localBestSAD = coarseBestSAD
            var minSADCount = 0
            
            let fineFound = refStrip.withUnsafeBufferPointer { refPtr -> Bool in
                guard let refBase = refPtr.baseAddress else { return false }
                return searchArea.withUnsafeBufferPointer { searchPtr -> Bool in
                    guard let searchBase = searchPtr.baseAddress else { return false }
                    return diffBuffer.withUnsafeMutableBufferPointer { diffPtr -> Bool in
                        guard let diffBase = diffPtr.baseAddress else { return false }
                        
                        for offset in fineMinOffset...fineMaxOffset {
                            let currentSearchPtr = searchBase.advanced(by: offset * cropWidth)
                            let sad = PixelBuffer.computeSADDirect(
                                ptrA: refBase,
                                ptrB: currentSearchPtr,
                                count: stripPixelCount,
                                diffBuffer: diffBase
                            )
                            if sad < localBestSAD - 0.05 {
                                localBestSAD = sad
                                localBestOffset = offset
                                minSADCount = 1
                            } else if abs(sad - localBestSAD) <= 0.05 {
                                minSADCount += 1
                            }
                        }
                        return true
                    }
                }
            }
            guard fineFound else { continue }
            
            let matchedYInImg2 = minMatchY + localBestOffset
            let calculatedDeltaY = refY - matchedYInImg2
            
            guard calculatedDeltaY > 0, calculatedDeltaY < height1 else { continue }
            
            var confidence = max(0, 1.0 - localBestSAD / Self.maxSADConfidenceScale)
            // Ambiguity penalty for repeating/low textures unless NCC verifies alignment
            if minSADCount > 3 && localBestSAD < Self.minAmbiguitySADThreshold {
                let testStrip = Array(searchArea[(localBestOffset * cropWidth)..<(localBestOffset * cropWidth + stripPixelCount)])
                let ncc = PixelBuffer.computeNCC(bufferA: refStrip, bufferB: testStrip)
                if ncc >= 0.95 {
                    confidence = max(confidence, 0.80)
                } else {
                    confidence = max(0, confidence - 0.3)
                }
            }
            
            observations.append(CandidateObservation(
                deltaY: calculatedDeltaY,
                confidence: confidence,
                sad: localBestSAD,
                stdDev: refStdDev
            ))
        }
        
        // Multi-strip Consensus & Outlier Filtering
        if !observations.isEmpty {
            // Sort by deltaY to find median
            let sortedByDelta = observations.sorted { $0.deltaY < $1.deltaY }
            let medianDelta = sortedByDelta[sortedByDelta.count / 2].deltaY
            
            // Inliers within +/- 4px of median
            let inliers = observations.filter { abs($0.deltaY - medianDelta) <= 4 }
            let confidentInliers = inliers.filter { $0.confidence >= Self.minConfidenceThreshold }
            let targetGroup = !confidentInliers.isEmpty ? confidentInliers : inliers
            
            // Weighted average by inverse SAD squared (giving overwhelming weight to sharp, ultra-low SAD matches)
            var totalWeight: Float = 0
            var weightedSum: Float = 0
            var maxConfidence: Float = 0
            
            for item in targetGroup {
                let weight = 1.0 / pow(max(0.1, item.sad + 0.05), 2)
                totalWeight += weight
                weightedSum += Float(item.deltaY) * weight
                maxConfidence = max(maxConfidence, item.confidence)
            }
            
            let consensusDelta = totalWeight > 0 ? Int((weightedSum / totalWeight).rounded()) : medianDelta
            
            if maxConfidence >= Self.minConfidenceThreshold {
                AppLogger.stitching.info("Consensus displacement found: deltaY=\(consensusDelta), confidence=\(maxConfidence) (median=\(medianDelta), prior=\(priorDelta))")
                return (deltaY: consensusDelta, confidence: maxConfidence)
            } else {
                AppLogger.stitching.warning("Consensus displacement confidence low (\(maxConfidence)), fallback to prior: \(priorDelta)")
                return (deltaY: priorDelta, confidence: maxConfidence)
            }
        }
        
        AppLogger.stitching.warning("Refined displacement fallback to prior: deltaY=\(priorDelta)")
        return (deltaY: priorDelta, confidence: 0.0)
    }
    
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
        
        // Safe horizontal crop excluding potential scrollbars
        let leftMargin = max(4, Int(Double(width) * 0.03))
        let rightMargin = max(10, Int(Double(width) * 0.07))
        let cropWidth = width - leftMargin - rightMargin
        guard cropWidth > 40 else { return nil }
        
        let stripHeight = min(referenceStripHeight, min(height1 / 4, height2 / 4))
        guard stripHeight >= 20 else { return nil }
        
        let searchAreaHeight = searchRange > 0 ? min(searchRange, height2) : height2
        let maxSearchOffset = searchAreaHeight - stripHeight
        guard maxSearchOffset > 0 else { return nil }
        
        // Extract full search area from image2 once
        let searchRect = CGRect(x: CGFloat(leftMargin), y: 0, width: CGFloat(cropWidth), height: CGFloat(searchAreaHeight))
        let searchArea = PixelBuffer.extractGrayscalePixels(from: image2, rect: searchRect)
        let stripPixelCount = stripHeight * cropWidth
        guard searchArea.count >= searchAreaHeight * cropWidth else { return nil }
        
        // Multi-depth candidate sampling ratios in image1 (65%, 55%, 75%, 45%, 82%)
        let candidateRatios: [Double] = [0.65, 0.55, 0.75, 0.45, 0.82]
        
        var bestOverallResult: OverlapResult? = nil
        var bestOverallConfidence: Float = 0.0
        var diffBuffer = [Float](repeating: 0, count: stripPixelCount)
        
        for ratio in candidateRatios {
            let refCenterY = Int(Double(height1) * ratio)
            let refY = max(0, min(height1 - stripHeight, refCenterY - stripHeight / 2))
            
            let refRect = CGRect(x: CGFloat(leftMargin), y: CGFloat(refY), width: CGFloat(cropWidth), height: CGFloat(stripHeight))
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
                            let currentSearchPtr = searchBase.advanced(by: offset * cropWidth)
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
