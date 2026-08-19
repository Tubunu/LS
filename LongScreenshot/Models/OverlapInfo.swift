import Foundation
import CoreGraphics

/// Result of overlap detection between two consecutive images
public struct OverlapResult: Sendable, Equatable {
    /// Vertical offset from the top of the second image where the matching begins
    public let offset: Int
    /// Matching confidence score (0.0 to 1.0)
    public let confidence: Float
    /// Total calculated overlapping height in pixels
    public let overlapHeight: Int
    
    public init(offset: Int, confidence: Float, overlapHeight: Int) {
        self.offset = offset
        self.confidence = confidence
        self.overlapHeight = overlapHeight
    }
}
