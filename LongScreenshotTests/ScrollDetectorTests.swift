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
    
    func testDisplacementsForShiftedFrames() async throws {
        let detector = ScrollDetector()
        let width = 100
        let height = 200
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context1 = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let context2 = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        
        // Draw distinct high-contrast horizontal bars
        for y in 0..<height {
            let c: CGFloat = (y % 20 < 10) ? 1.0 : 0.0
            context1.setFillColor(red: c, green: c, blue: c, alpha: 1.0)
            context1.fill(CGRect(x: 0, y: y, width: width, height: 1))
            
            let c2: CGFloat = ((y + 10) % 20 < 10) ? 1.0 : 0.0
            context2.setFillColor(red: c2, green: c2, blue: c2, alpha: 1.0)
            context2.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        
        let img1 = context1.makeImage()!
        let img2 = context2.makeImage()!
        
        let frame1 = FrameData(image: img1, timestamp: CMTime(seconds: 0.0, preferredTimescale: 600), index: 0)
        let frame2 = FrameData(image: img2, timestamp: CMTime(seconds: 0.2, preferredTimescale: 600), index: 1)
        
        let displacements = try await detector.detectDisplacements(frames: [frame1, frame2]) { _, _ in }
        XCTAssertEqual(displacements.count, 2)
    }
}
