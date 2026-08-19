import Foundation
import CoreGraphics

/// Service responsible for automatically detecting stationary UI elements (Status Bar, Tab Bar, Home Indicator)
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
    
    private static let rowIdenticalSADThreshold: Float = 3.5
    
    public init() {}
    
    /// Detects fixed top and bottom regions by analyzing pixel variance across multiple spaced keyframes
    public func detectFixedRegions(in keyFrames: [KeyFrame]) async -> FixedRegions {
        guard keyFrames.count >= 2 else {
            return FixedRegions.zero
        }
        
        let totalDisplacement = (keyFrames.last?.cumulativeOffset ?? 0) - (keyFrames.first?.cumulativeOffset ?? 0)
        // Ensure there has been sufficient scrolling motion to distinguish static UI from un-scrolled page content
        guard totalDisplacement >= 80.0 else {
            return FixedRegions.zero
        }
        
        // Sample spaced keyframes (first, middle, last) to ensure substantial content motion
        let indices: [Int]
        if keyFrames.count == 2 {
            indices = [0, 1]
        } else {
            indices = [0, keyFrames.count / 2, keyFrames.count - 1]
        }
        let sampledFrames = indices.map { keyFrames[$0] }
        
        let width = sampledFrames[0].image.width
        let height = sampledFrames[0].image.height
        
        let maxTopCheck = min(Int(totalDisplacement * 0.7), min(height / 3, 400))
        let maxBottomCheck = min(height / 4, 260)
        guard maxTopCheck > 0 || maxBottomCheck > 0 else { return FixedRegions.zero }
        
        var rowDiffBuffer = [Float](repeating: 0, count: width)
        var topFixed = 0
        var bottomFixed = 0
        
        // 1. Check top rows (Status bar / Navigation bar) using ROI crop
        if maxTopCheck > 0 {
            let topRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(maxTopCheck))
            let topPixelArrays = sampledFrames.map { kf in
                PixelBuffer.extractGrayscalePixels(from: kf.image, rect: topRect)
            }
            
            if topPixelArrays.allSatisfy({ $0.count == width * maxTopCheck }) {
                var consecutiveMismatchesTop = 0
                for row in 0..<maxTopCheck {
                    if Task.isCancelled { return FixedRegions.zero }
                    
                    if isRowIdentical(row: row, width: width, pixelArrays: topPixelArrays, diffBuffer: &rowDiffBuffer) {
                        topFixed = row + 1
                        consecutiveMismatchesTop = 0
                    } else {
                        consecutiveMismatchesTop += 1
                        if consecutiveMismatchesTop > 2 {
                            break
                        }
                    }
                }
            }
        }
        
        // 2. Check bottom rows (Home indicator / Tab bar) using ROI crop
        if maxBottomCheck > 0 {
            let bottomRect = CGRect(x: 0, y: CGFloat(height - maxBottomCheck), width: CGFloat(width), height: CGFloat(maxBottomCheck))
            let bottomPixelArrays = sampledFrames.map { kf in
                PixelBuffer.extractGrayscalePixels(from: kf.image, rect: bottomRect)
            }
            
            if bottomPixelArrays.allSatisfy({ $0.count == width * maxBottomCheck }) {
                var consecutiveMismatchesBottom = 0
                for localRow in stride(from: maxBottomCheck - 1, through: 0, by: -1) {
                    if Task.isCancelled { return FixedRegions.zero }
                    
                    if isRowIdentical(row: localRow, width: width, pixelArrays: bottomPixelArrays, diffBuffer: &rowDiffBuffer) {
                        bottomFixed = maxBottomCheck - localRow
                        consecutiveMismatchesBottom = 0
                    } else {
                        consecutiveMismatchesBottom += 1
                        if consecutiveMismatchesBottom > 2 {
                            break
                        }
                    }
                }
            }
        }
        
        return FixedRegions(topHeight: topFixed, bottomHeight: bottomFixed)
    }
    
    private func isRowIdentical(
        row: Int,
        width: Int,
        pixelArrays: [[Float]],
        diffBuffer: inout [Float]
    ) -> Bool {
        let rowStart = row * width
        guard let firstArray = pixelArrays.first, rowStart + width <= firstArray.count else { return false }
        
        return firstArray.withUnsafeBufferPointer { refPtr in
            guard let refBase = refPtr.baseAddress else { return false }
            let refRowPtr = refBase.advanced(by: rowStart)
            
            return diffBuffer.withUnsafeMutableBufferPointer { diffPtr in
                guard let diffBase = diffPtr.baseAddress else { return false }
                
                for array in pixelArrays.dropFirst() {
                    let matched = array.withUnsafeBufferPointer { compPtr -> Bool in
                        guard let compBase = compPtr.baseAddress else { return false }
                        let compRowPtr = compBase.advanced(by: rowStart)
                        
                        let sad = PixelBuffer.computeSADDirect(
                            ptrA: refRowPtr,
                            ptrB: compRowPtr,
                            count: width,
                            diffBuffer: diffBase
                        )
                        // Allow slight sensor / compression noise (SAD <= rowIdenticalSADThreshold)
                        return sad <= Self.rowIdenticalSADThreshold
                    }
                    if !matched { return false }
                }
                return true
            }
        }
    }
}
