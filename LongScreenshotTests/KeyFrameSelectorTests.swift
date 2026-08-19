import XCTest
import CoreGraphics
import CoreMedia
@testable import LongScreenshotCore

final class KeyFrameSelectorTests: XCTestCase {
    
    private func createDummyCGImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 50,
            height: 50,
            bitsPerComponent: 8,
            bytesPerRow: 200,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.1, green: 0.8, blue: 0.3, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        return context.makeImage()!
    }
    
    func testKeyFrameSelectionThresholding() async {
        let selector = KeyFrameSelector()
        let dummyImage = createDummyCGImage()
        
        var displacements: [FrameDisplacement] = []
        
        // Initial frame
        let initialFrame = FrameData(image: dummyImage, timestamp: CMTime(seconds: 0.0, preferredTimescale: 600), index: 0)
        displacements.append(FrameDisplacement(frame: initialFrame, dy: 0, dx: 0, isScrolling: false))
        
        // Add 10 scrolling frames of 40px each (Total = 400px)
        for i in 1...10 {
            let frame = FrameData(image: dummyImage, timestamp: CMTime(seconds: Double(i) * 0.2, preferredTimescale: 600), index: i)
            displacements.append(FrameDisplacement(frame: frame, dy: 40.0, dx: 0.0, isScrolling: true))
        }
        
        // Add 3 static frames
        for i in 11...13 {
            let frame = FrameData(image: dummyImage, timestamp: CMTime(seconds: Double(i) * 0.2, preferredTimescale: 600), index: i)
            displacements.append(FrameDisplacement(frame: frame, dy: 0.0, dx: 0.0, isScrolling: false))
        }
        
        let config = KeyFrameSelector.Config(captureThreshold: 150.0, minScrollSpeed: 2.0, maxScrollSpeed: 200.0)
        let keyFrames = await selector.selectKeyFrames(from: displacements, config: config) { _, _ in }
        
        // Frame 0 (start), Frame at 160px (i=4), Frame at 320px (i=8), and last scrolling frame (i=10)
        XCTAssertGreaterThanOrEqual(keyFrames.count, 3)
        XCTAssertEqual(keyFrames.first?.cumulativeOffset, 0)
    }
}
