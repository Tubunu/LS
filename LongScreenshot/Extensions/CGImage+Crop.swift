import CoreGraphics
import UIKit

public extension CGImage {
    /// Safely crops a CGImage to a sub-rectangle within bounds
    func safeCropping(to rect: CGRect) -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: self.width, height: self.height)
        let intersection = imageBounds.intersection(rect)
        
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return nil
        }
        
        return self.cropping(to: intersection)
    }
}
