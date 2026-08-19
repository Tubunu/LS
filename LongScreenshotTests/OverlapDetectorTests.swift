import XCTest
import CoreGraphics
@testable import LongScreenshot

final class OverlapDetectorTests: XCTestCase {
    
    /// Helper to generate a test CGImage filled with vertical color bands / patterned lines
    private func createTestImage(width: Int, height: Int, startPattern: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        for y in 0..<height {
            let patternVal = CGFloat((startPattern + y * 7) % 255) / 255.0
            context.setFillColor(red: patternVal, green: 1.0 - patternVal, blue: 0.5, alpha: 1.0)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        
        return context.makeImage()!
    }
    
    func testOverlapDetectorFindsKnownOffset() async {
        let detector = OverlapDetector()
        let width = 200
        let fullHeight = 400
        let overlap = 120
        
        // Image 1 spans pattern 0..<400
        let fullImage = createTestImage(width: width, height: fullHeight, startPattern: 0)
        
        // Split into two images with 120px overlap
        let image1 = fullImage.safeCropping(to: CGRect(x: 0, y: 0, width: width, height: 250))!
        let image2 = fullImage.safeCropping(to: CGRect(x: 0, y: 250 - overlap, width: width, height: 250))!
        
        let result = await detector.findOverlap(
            bottomOf: image1,
            topOf: image2,
            referenceStripHeight: 80,
            searchRange: 200
        )
        
        XCTAssertNotNil(result, "Overlap result should not be nil")
        if let result {
            XCTAssertGreaterThanOrEqual(result.confidence, 0.70, "Confidence should be high for exact pattern")
        }
    }
}
