import Foundation
import CoreGraphics

public struct OverlapResult: Sendable, Equatable {
    /// Vertical row in image1 where the reference strip center was taken
    public let refY: Int
    /// Vertical row in image2 where the reference strip center was matched
    public let matchY: Int
    /// Vertical offset from the top of the second image where the matching begins
    public var offset: Int { matchY }
    /// Matching confidence score (0.0 to 1.0)
    public let confidence: Float
    /// Total calculated overlapping height in pixels
    public let overlapHeight: Int
    
    public init(refY: Int = 0, matchY: Int = 0, confidence: Float, overlapHeight: Int) {
        self.refY = refY
        self.matchY = matchY
        self.confidence = confidence
        self.overlapHeight = overlapHeight
    }
    
    public init(offset: Int, confidence: Float, overlapHeight: Int) {
        self.refY = overlapHeight - offset
        self.matchY = offset
        self.confidence = confidence
        self.overlapHeight = overlapHeight
    }
}
