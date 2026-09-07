import Foundation
import CoreGraphics
import Accelerate

/// Service responsible for automatically detecting stationary UI elements (Status Bar, Navigation Bar, Tab Bar, Floating Action Bar, Home Indicator)
public actor FixedUIDetector {
    
    public struct FixedRegions: Sendable, Equatable {
        public let topHeight: Int
        public let bottomHeight: Int
        
        public init(topHeight: Int = 0, bottomHeight: Int = 0) {
            self.topHeight = topHeight
            self.bottomHeight = bottomHeight
        }
        
        public static let zero = FixedRegions(topHeight: 0, bottomHeight: 0)
    }
    
    /// Threshold for stationary row matching under sensor / compression / frosted-glass blur noise
    private static let singlePairRowSADThreshold: Float = 24.0
    private static let avgRowSADThreshold: Float = 22.0
    
    public init() {}
    
    /// Detects fixed top and bottom regions by analyzing temporal pixel variance across multiple keyframe pairs
    public func detectFixedRegions(in keyFrames: [KeyFrame]) async -> FixedRegions {
        guard keyFrames.count >= 2 else {
            return FixedRegions.zero
        }
        
        let width = keyFrames[0].image.width
        let height = keyFrames[0].image.height
        
        // Calculate device baseline safe area as guaranteed floor
        let adaptiveConfig = CropConfig.adaptive(for: CGSize(width: width, height: height))
        let baselineScale: CGFloat = (width >= 1000 ? 3.0 : (width >= 640 ? 2.0 : 1.0))
        let baselineTop = Int((adaptiveConfig.statusBarHeight * baselineScale).rounded())
        let baselineBottom = Int((adaptiveConfig.bottomSafeArea * baselineScale).rounded())
        
        let totalDisplacement = (keyFrames.last?.cumulativeOffset ?? 0) - (keyFrames.first?.cumulativeOffset ?? 0)
        // Ensure there has been sufficient scrolling motion to distinguish static UI from un-scrolled page content
        guard totalDisplacement >= 50.0 else {
            return FixedRegions(topHeight: baselineTop, bottomHeight: baselineBottom)
        }
        
        // Build informative keyframe comparison pairs with confirmed motion
        let pairs = selectKeyFramePairs(from: keyFrames)
        guard !pairs.isEmpty else {
            return FixedRegions(topHeight: baselineTop, bottomHeight: baselineBottom)
        }
        
        // Dynamic search boundaries (covers status bar + large nav bar / search bar / tab bar at top, and home indicator + floating toolbar / action button at bottom)
        let maxTopCheck = min(height / 3, max(baselineTop + 40, Int(max(340.0, 240.0 * baselineScale))))
        let maxBottomCheck = min(height / 3, max(baselineBottom + 40, Int(max(200.0, 160.0 * baselineScale))))
        
        var topFixed = baselineTop
        var bottomFixed = baselineBottom
        
        // 1. Analyze top candidate region (Status Bar / Navigation Bar / Large Title Header)
        if maxTopCheck > baselineTop {
            let topRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(maxTopCheck))
            let pairPixelBuffers = pairs.compactMap { pair -> (a: [Float], b: [Float])? in
                let a = PixelBuffer.extractGrayscalePixels(from: pair.0.image, rect: topRect)
                let b = PixelBuffer.extractGrayscalePixels(from: pair.1.image, rect: topRect)
                guard a.count == width * maxTopCheck, b.count == width * maxTopCheck else { return nil }
                return (a, b)
            }
            
            if !pairPixelBuffers.isEmpty {
                let stationaryTopRows = computeStationaryRowMask(
                    width: width,
                    rowCount: maxTopCheck,
                    pairBuffers: pairPixelBuffers
                )
                
                let maxTopTolerance = Int(40.0 * baselineScale)
                var bestTop = baselineTop
                var consecutiveNonStatic = 0
                for row in 0..<maxTopCheck {
                    if Task.isCancelled { return FixedRegions(topHeight: baselineTop, bottomHeight: baselineBottom) }
                    
                    if stationaryTopRows[row] {
                        bestTop = max(bestTop, row + 1)
                        consecutiveNonStatic = 0
                    } else {
                        consecutiveNonStatic += 1
                        // Window tolerance: if we encounter continuous non-stationary rows, scrolling content has started
                        if consecutiveNonStatic > maxTopTolerance {
                            break
                        }
                    }
                }
                topFixed = max(baselineTop, bestTop)
            }
        }
        
        // 2. Analyze bottom candidate region (Home Indicator / Tab Bar / Floating Input Bar / Floating Pills)
        if maxBottomCheck > baselineBottom {
            let bottomRect = CGRect(x: 0, y: CGFloat(height - maxBottomCheck), width: CGFloat(width), height: CGFloat(maxBottomCheck))
            let pairPixelBuffers = pairs.compactMap { pair -> (a: [Float], b: [Float])? in
                let a = PixelBuffer.extractGrayscalePixels(from: pair.0.image, rect: bottomRect)
                let b = PixelBuffer.extractGrayscalePixels(from: pair.1.image, rect: bottomRect)
                guard a.count == width * maxBottomCheck, b.count == width * maxBottomCheck else { return nil }
                return (a, b)
            }
            
            if !pairPixelBuffers.isEmpty {
                let stationaryBottomRows = computeStationaryRowMask(
                    width: width,
                    rowCount: maxBottomCheck,
                    pairBuffers: pairPixelBuffers
                )
                
                let maxBottomTolerance = Int(14.0 * baselineScale)
                var bestBottom = baselineBottom
                var consecutiveNonStatic = 0
                // Scan upward from the screen bottom (localRow = maxBottomCheck - 1)
                for localRow in stride(from: maxBottomCheck - 1, through: 0, by: -1) {
                    if Task.isCancelled { return FixedRegions(topHeight: baselineTop, bottomHeight: baselineBottom) }
                    
                    if stationaryBottomRows[localRow] {
                        bestBottom = max(bestBottom, maxBottomCheck - localRow)
                        consecutiveNonStatic = 0
                    } else {
                        consecutiveNonStatic += 1
                        // Window tolerance: allow gap/translucency between home bar and floating toolbar
                        if consecutiveNonStatic > maxBottomTolerance {
                            break
                        }
                    }
                }
                bottomFixed = max(baselineBottom, bestBottom)
            }
        }
        
        // 3. Detect Floating Pills / Action Buttons in bottom candidate band (dist 180..420px)
        if height > 1000, let firstFrame = keyFrames.first {
            let maxPillCheck = min(Int(CGFloat(height) * 0.20), Int(140.0 * baselineScale))
            let pillCheckTop = height - maxPillCheck
            let pillCheckBottom = height - bottomFixed
            
            if pillCheckBottom > pillCheckTop {
                let midX = Int(Double(width) * 0.30)
                let midW = Int(Double(width) * 0.40)
                let pillCheckH = pillCheckBottom - pillCheckTop
                let pillRect = CGRect(x: CGFloat(midX), y: CGFloat(pillCheckTop), width: CGFloat(midW), height: CGFloat(pillCheckH))
                
                let (detected, pillDistFromBottom) = PixelBuffer.detectFloatingPillRegion(in: firstFrame.image, searchRect: pillRect, threshold: 40)
                if detected {
                    let adjustedBottom = pillDistFromBottom + Int(8.0 * baselineScale)
                    bottomFixed = max(bottomFixed, adjustedBottom)
                    AppLogger.stitching.info("FixedUIDetector: Floating action pill detected in initial frame! Extended bottom crop to \(bottomFixed)px")
                }
            }
        }
        
        return FixedRegions(topHeight: topFixed, bottomHeight: bottomFixed)
    }
    
    /// Selects multiple informative keyframe comparison pairs with confirmed motion
    private func selectKeyFramePairs(from keyFrames: [KeyFrame]) -> [(KeyFrame, KeyFrame)] {
        var pairs: [(KeyFrame, KeyFrame)] = []
        let count = keyFrames.count
        guard count >= 2 else { return [] }
        
        // Adjacent pairs with motion
        for i in 0..<(count - 1) {
            let disp = abs(keyFrames[i + 1].cumulativeOffset - keyFrames[i].cumulativeOffset)
            if disp >= 40.0 {
                pairs.append((keyFrames[i], keyFrames[i + 1]))
            }
        }
        
        // Spanned pairs across the recording
        if count >= 3 {
            pairs.append((keyFrames[0], keyFrames[count / 2]))
            pairs.append((keyFrames[count / 2], keyFrames[count - 1]))
            pairs.append((keyFrames[0], keyFrames[count - 1]))
        }
        
        // Cap to at most 8 pairs for high performance
        if pairs.count > 8 {
            let strideStep = max(1, pairs.count / 8)
            pairs = stride(from: 0, to: pairs.count, by: strideStep).map { pairs[$0] }
        }
        
        return pairs.isEmpty ? [(keyFrames[0], keyFrames[count - 1])] : pairs
    }
    
    /// Computes a boolean mask indicating whether each row is stationary across pairs
    private func computeStationaryRowMask(
        width: Int,
        rowCount: Int,
        pairBuffers: [(a: [Float], b: [Float])]
    ) -> [Bool] {
        var mask = [Bool](repeating: false, count: rowCount)
        var diffBuffer = [Float](repeating: 0, count: width)
        let totalPairs = pairBuffers.count
        guard totalPairs > 0 else { return mask }
        
        diffBuffer.withUnsafeMutableBufferPointer { diffPtr in
            guard let diffBase = diffPtr.baseAddress else { return }
            
            let midStart = width / 4
            let midCount = width / 2
            let rightStart = Int(Float(width) * 0.80)
            let rightCount = max(10, Int(Float(width) * 0.16))
            
            for row in 0..<rowCount {
                let rowOffset = row * width
                var totalSAD: Float = 0.0
                var totalMidSAD: Float = 0.0
                var totalRightSAD: Float = 0.0
                var matchCount = 0
                
                for pair in pairBuffers {
                    pair.a.withUnsafeBufferPointer { aPtr in
                        guard let aBase = aPtr.baseAddress else { return }
                        let aRowPtr = aBase.advanced(by: rowOffset)
                        
                        pair.b.withUnsafeBufferPointer { bPtr in
                            guard let bBase = bPtr.baseAddress else { return }
                            let bRowPtr = bBase.advanced(by: rowOffset)
                            
                            let sad = PixelBuffer.computeSADDirect(
                                ptrA: aRowPtr,
                                ptrB: bRowPtr,
                                count: width,
                                diffBuffer: diffBase
                            )
                            totalSAD += sad
                            
                            var midDiffSum: Float = 0
                            vDSP_sve(diffBase.advanced(by: midStart), 1, &midDiffSum, vDSP_Length(midCount))
                            let midSAD = midDiffSum / Float(midCount)
                            totalMidSAD += midSAD
                            
                            var rightDiffSum: Float = 0
                            vDSP_sve(diffBase.advanced(by: rightStart), 1, &rightDiffSum, vDSP_Length(rightCount))
                            let rightSAD = rightDiffSum / Float(rightCount)
                            totalRightSAD += rightSAD
                            
                            if sad <= Self.singlePairRowSADThreshold || midSAD <= 16.0 || rightSAD <= 16.0 {
                                matchCount += 1
                            }
                        }
                    }
                }
                
                let avgSAD = totalSAD / Float(totalPairs)
                let avgMidSAD = totalMidSAD / Float(totalPairs)
                let avgRightSAD = totalRightSAD / Float(totalPairs)
                let matchRatio = Float(matchCount) / Float(totalPairs)
                
                // A row is stationary if:
                // 1. Full row has very low SAD across all pairs (e.g. solid background toolbar/navbar), or
                // 2. Average SAD is low AND matchRatio is high (>= 80% pairs agree, preventing scrolling white space from tricking the detector), or
                // 3. Center segment (floating pill) or right segment (back-to-top button) is persistently static (>= 75% pairs agree).
                let isSolidStatic = avgSAD <= 12.0
                let isWholeStatic = avgSAD <= Self.avgRowSADThreshold && matchRatio >= 0.80
                let isSegmentStatic = (avgMidSAD <= 16.0 || avgRightSAD <= 16.0) && matchRatio >= 0.75
                
                if isSolidStatic || isWholeStatic || isSegmentStatic {
                    mask[row] = true
                }
            }
        }
        
        return mask
    }
}
