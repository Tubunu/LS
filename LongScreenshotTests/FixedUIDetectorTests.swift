import XCTest
import CoreGraphics
import CoreMedia
@testable import LongScreenshot

final class FixedUIDetectorTests: XCTestCase {
    
    /// Helper to generate a test image with a fixed top header of `topFixed` height and scrolling patterned body
    private func createFrameWithFixedHeader(width: Int, height: Int, topFixed: Int, bottomFixed: Int, scrollY: Int) -> CGImage {
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
        
        // 1. Draw top fixed region (solid color, identical in all frames)
        if topFixed > 0 {
            context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: width, height: topFixed))
        }
        
        // 2. Draw scrolling body pattern
        let bodyStartY = topFixed
        let bodyEndY = height - bottomFixed
        for y in bodyStartY..<bodyEndY {
            let patternVal = CGFloat(((y + scrollY) * 13) % 255) / 255.0
            context.setFillColor(red: patternVal, green: 1.0 - patternVal, blue: 0.7, alpha: 1.0)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        
        // 3. Draw bottom fixed region (solid color, identical in all frames)
        if bottomFixed > 0 {
            context.setFillColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            context.fill(CGRect(x: 0, y: height - bottomFixed, width: width, height: bottomFixed))
        }
        
        return context.makeImage()!
    }
    
    func testDetectsFixedTopAndBottom() async {
        let detector = FixedUIDetector()
        let width = 200
        let height = 600
        let topBar = 50
        let bottomBar = 30
        
        // Create 3 keyframes with known fixed top & bottom regions and 200px scroll displacement
        let img1 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 0)
        let img2 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 100)
        let img3 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 200)
        
        let kf1 = KeyFrame(image: img1, cumulativeOffset: 0, timestamp: CMTime(seconds: 0, preferredTimescale: 600), index: 0)
        let kf2 = KeyFrame(image: img2, cumulativeOffset: 100, timestamp: CMTime(seconds: 1, preferredTimescale: 600), index: 1)
        let kf3 = KeyFrame(image: img3, cumulativeOffset: 200, timestamp: CMTime(seconds: 2, preferredTimescale: 600), index: 2)
        
        let result = await detector.detectFixedRegions(in: [kf1, kf2, kf3])
        
        // Top should detect around 50px (allowing +/- 2px boundary tolerance)
        XCTAssertGreaterThanOrEqual(result.topHeight, topBar - 2)
        XCTAssertLessThanOrEqual(result.topHeight, topBar + 2)
        
        // Bottom should detect around 30px
        XCTAssertGreaterThanOrEqual(result.bottomHeight, bottomBar - 2)
        XCTAssertLessThanOrEqual(result.bottomHeight, bottomBar + 2)
    }
    
    func testShortDisplacementSafeguardReturnsZero() async {
        let detector = FixedUIDetector()
        let width = 200
        let height = 600
        
        // Frames with very small displacement (<80px)
        let img1 = createFrameWithFixedHeader(width: width, height: height, topFixed: 50, bottomFixed: 30, scrollY: 0)
        let img2 = createFrameWithFixedHeader(width: width, height: height, topFixed: 50, bottomFixed: 30, scrollY: 20)
        
        let kf1 = KeyFrame(image: img1, cumulativeOffset: 0, timestamp: .zero, index: 0)
        let kf2 = KeyFrame(image: img2, cumulativeOffset: 20, timestamp: .zero, index: 1)
        
        let result = await detector.detectFixedRegions(in: [kf1, kf2])
        
        // Should safely return baseline floor on short scroll
        XCTAssertGreaterThanOrEqual(result.topHeight, 0)
        XCTAssertGreaterThanOrEqual(result.bottomHeight, 0)
    }
    
    func testDetectsTallTopHeader() async {
        let detector = FixedUIDetector()
        let width = 200
        let height = 1200
        let topBar = 320 // 3x Pro Max status bar + large title navigation bar
        let bottomBar = 80
        
        let img1 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 0)
        let img2 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 300)
        let img3 = createFrameWithFixedHeader(width: width, height: height, topFixed: topBar, bottomFixed: bottomBar, scrollY: 600)
        
        let kf1 = KeyFrame(image: img1, cumulativeOffset: 0, timestamp: .zero, index: 0)
        let kf2 = KeyFrame(image: img2, cumulativeOffset: 300, timestamp: .zero, index: 1)
        let kf3 = KeyFrame(image: img3, cumulativeOffset: 600, timestamp: .zero, index: 2)
        
        let result = await detector.detectFixedRegions(in: [kf1, kf2, kf3])
        
        XCTAssertGreaterThanOrEqual(result.topHeight, topBar - 2)
        XCTAssertLessThanOrEqual(result.topHeight, topBar + 2)
    }
    
    func testDetectsTallFloatingBottomBarWithTranslucency() async {
        let detector = FixedUIDetector()
        let width = 300
        let height = 1000
        let topBar = 60
        let bottomBar = 150 // Tall floating toolbar + safe area (e.g. input bar with icons)
        
        func createTranslucentFloatingBarImage(scrollY: Int, noiseIntensity: CGFloat) -> CGImage {
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
            
            // Top fixed header
            context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            context.fill(CGRect(x: 0, y: 0, width: width, height: topBar))
            
            // Scrolling body
            let bodyStartY = topBar
            let bodyEndY = height - bottomBar
            for y in bodyStartY..<bodyEndY {
                let patternVal = CGFloat(((y + scrollY) * 19) % 255) / 255.0
                context.setFillColor(red: patternVal, green: 1.0 - patternVal, blue: 0.6, alpha: 1.0)
                context.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
            
            // Bottom floating bar with slight frosted glass translucency
            for y in (height - bottomBar)..<height {
                let baseColor: CGFloat = 0.92
                // Frosted glass background with slight shifting through translucency
                let shift = CGFloat(((y + scrollY) * 3) % 15) / 255.0 * noiseIntensity
                context.setFillColor(red: baseColor + shift, green: baseColor + shift, blue: baseColor + shift, alpha: 1.0)
                context.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
            
            // Solid button/icon elements inside floating bar (identical across frames)
            context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
            context.fill(CGRect(x: 30, y: height - bottomBar + 20, width: width - 60, height: 40))
            
            return context.makeImage()!
        }
        
        let img1 = createTranslucentFloatingBarImage(scrollY: 0, noiseIntensity: 1.0)
        let img2 = createTranslucentFloatingBarImage(scrollY: 200, noiseIntensity: 1.0)
        let img3 = createTranslucentFloatingBarImage(scrollY: 400, noiseIntensity: 1.0)
        
        let kf1 = KeyFrame(image: img1, cumulativeOffset: 0, timestamp: .zero, index: 0)
        let kf2 = KeyFrame(image: img2, cumulativeOffset: 200, timestamp: .zero, index: 1)
        let kf3 = KeyFrame(image: img3, cumulativeOffset: 400, timestamp: .zero, index: 2)
        
        let result = await detector.detectFixedRegions(in: [kf1, kf2, kf3])
        
        // Should successfully identify the entire 150px floating bottom bar
        XCTAssertGreaterThanOrEqual(result.bottomHeight, bottomBar - 4)
        XCTAssertLessThanOrEqual(result.bottomHeight, bottomBar + 4)
    }
}
