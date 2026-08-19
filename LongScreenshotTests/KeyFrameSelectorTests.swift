import XCTest
import CoreGraphics
import CoreMedia
@testable import LongScreenshot

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
    
    func testInitialJitterDoesNotBlockDownwardScroll() async {
        let selector = KeyFrameSelector()
        let dummyImage = createDummyCGImage()
        
        var displacements: [FrameDisplacement] = []
        
        // Frame 0 (initial)
        let f0 = FrameData(image: dummyImage, timestamp: .zero, index: 0)
        displacements.append(FrameDisplacement(frame: f0, dy: 0, dx: 0, isScrolling: false))
        
        // Frame 1: Tiny micro-jitter upward (-3.0px)
        let f1 = FrameData(image: dummyImage, timestamp: CMTime(seconds: 0.1, preferredTimescale: 600), index: 1)
        displacements.append(FrameDisplacement(frame: f1, dy: -3.0, dx: 0, isScrolling: true))
        
        // Frames 2..10: Normal continuous downward scroll (+50.0px per frame)
        for i in 2...10 {
            let f = FrameData(image: dummyImage, timestamp: CMTime(seconds: Double(i) * 0.1, preferredTimescale: 600), index: i)
            displacements.append(FrameDisplacement(frame: f, dy: 50.0, dx: 0, isScrolling: true))
        }
        
        let config = KeyFrameSelector.Config(captureThreshold: 150.0)
        let keyFrames = await selector.selectKeyFrames(from: displacements, config: config) { _, _ in }
        
        // Should successfully extract keyframes despite initial upward jitter
        XCTAssertGreaterThanOrEqual(keyFrames.count, 3, "Keyframes should be extracted despite initial micro-jitter")
    }
}
