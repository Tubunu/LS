import Foundation
import CoreGraphics
import CoreMedia

/// Represents the raw frame data extracted from a video asset
public struct FrameData: @unchecked Sendable {
    public let image: CGImage
    public let timestamp: CMTime
    public let index: Int
    
    public init(image: CGImage, timestamp: CMTime, index: Int) {
        self.image = image
        self.timestamp = timestamp
        self.index = index
    }
}

/// Represents the translational displacement between adjacent video frames
public struct FrameDisplacement: @unchecked Sendable {
    public let frame: FrameData
    /// Vertical displacement relative to previous frame (dy > 0: scrolling down / content moves up)
    public let dy: CGFloat
    /// Horizontal displacement relative to previous frame
    public let dx: CGFloat
    /// Whether the frame is classified as an active vertical scrolling state
    public let isScrolling: Bool
    
    public init(frame: FrameData, dy: CGFloat, dx: CGFloat, isScrolling: Bool) {
        self.frame = frame
        self.dy = dy
        self.dx = dx
        self.isScrolling = isScrolling
    }
}
