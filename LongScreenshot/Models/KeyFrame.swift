import CoreGraphics
import CoreMedia

/// Represents a selected keyframe from a screen recording with its temporal and spatial metadata
public struct KeyFrame: @unchecked Sendable {
    public let image: CGImage
    public let cumulativeOffset: CGFloat
    public let timestamp: CMTime
    public let index: Int
    
    public init(image: CGImage, cumulativeOffset: CGFloat, timestamp: CMTime, index: Int = 0) {
        self.image = image
        self.cumulativeOffset = cumulativeOffset
        self.timestamp = timestamp
        self.index = index
    }
}
