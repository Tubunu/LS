import UIKit

/// Final result information of a completed stitching operation
public struct StitchingResult: @unchecked Sendable {
    public let image: UIImage
    public let dimensions: CGSize
    public let executionDuration: TimeInterval
    public let sourceCount: Int
    public let mode: ProcessingMode
    
    public init(
        image: UIImage,
        dimensions: CGSize,
        executionDuration: TimeInterval,
        sourceCount: Int,
        mode: ProcessingMode
    ) {
        self.image = image
        self.dimensions = dimensions
        self.executionDuration = executionDuration
        self.sourceCount = sourceCount
        self.mode = mode
    }
}
