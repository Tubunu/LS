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
        public static let standardFallback = FixedRegions(topHeight: 120, bottomHeight: 80) // retina px fallback
    }
    
    public init() {}
    
    /// Detects fixed top and bottom regions by analyzing pixel variance across multiple keyframes
    public func detectFixedRegions(in keyFrames: [KeyFrame]) async -> FixedRegions {
        guard keyFrames.count >= 2 else {
            return FixedRegions.zero
        }
        
        // Sample up to 3 spaced keyframes
        let sampleCount = min(3, keyFrames.count)
        let sampledFrames = Array(keyFrames.prefix(sampleCount))
        
        let width = sampledFrames[0].image.width
        let height = sampledFrames[0].image.height
        
        guard width > 0, height > 0 else { return FixedRegions.zero }
        
        // Extract grayscale buffers for the sample frames
        let pixelArrays: [[Float]] = sampledFrames.map { kf in
            PixelBuffer.extractGrayscalePixels(
                from: kf.image,
                rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            )
        }
        
        // 1. Check top rows
        var topFixed = 0
        let maxTopCheck = min(height / 4, 300) // Don't check more than top 25%
        
        for row in 0..<maxTopCheck {
            if isRowIdentical(row: row, width: width, height: height, pixelArrays: pixelArrays) {
                topFixed = row + 1
            } else {
                break
            }
        }
        
        // 2. Check bottom rows
        var bottomFixed = 0
        let maxBottomCheck = min(height / 4, 200)
        
        for row in stride(from: height - 1, through: max(0, height - maxBottomCheck), by: -1) {
            if isRowIdentical(row: row, width: width, height: height, pixelArrays: pixelArrays) {
                bottomFixed = height - row
            } else {
                break
            }
        }
        
        // If detection found 0 or anomalous values, apply reasonable minimum bounds if needed
        return FixedRegions(topHeight: topFixed, bottomHeight: bottomFixed)
    }
    
    private func isRowIdentical(row: Int, width: Int, height: Int, pixelArrays: [[Float]]) -> Bool {
        let rowStart = row * width
        let rowEnd = rowStart + width
        
        guard let firstArray = pixelArrays.first, rowEnd <= firstArray.count else { return false }
        let referenceRow = Array(firstArray[rowStart..<rowEnd])
        
        for array in pixelArrays.dropFirst() {
            guard rowEnd <= array.count else { return false }
            let compareRow = Array(array[rowStart..<rowEnd])
            
            let sad = PixelBuffer.computeSAD(bufferA: referenceRow, bufferB: compareRow)
            // Allow minimal sensor / compression noise
            if sad > 2.0 {
                return false
            }
        }
        
        return true
    }
}
