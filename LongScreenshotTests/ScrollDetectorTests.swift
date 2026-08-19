import XCTest
import CoreGraphics
import CoreMedia
@testable import LongScreenshot

final class ScrollDetectorTests: XCTestCase {
    
    private func createDummyCGImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return context.makeImage()!
    }
    
    func testDisplacementsForIdenticalFrames() async throws {
        let detector = ScrollDetector()
        let image = createDummyCGImage()
        
        let frame1 = FrameData(image: image, timestamp: CMTime(seconds: 0.0, preferredTimescale: 600), index: 0)
        let frame2 = FrameData(image: image, timestamp: CMTime(seconds: 0.2, preferredTimescale: 600), index: 1)
        
        let displacements = try await detector.detectDisplacements(frames: [frame1, frame2]) { _, _ in }
        
        XCTAssertEqual(displacements.count, 2)
        XCTAssertFalse(displacements[0].isScrolling)
        // Two identical static frames should have minimal displacement (not scrolling)
        XCTAssertFalse(displacements[1].isScrolling)
    }
}
