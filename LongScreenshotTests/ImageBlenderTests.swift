import XCTest
import CoreGraphics
@testable import LongScreenshot

final class ImageBlenderTests: XCTestCase {
    
    private func createColorImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
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
        
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
    
    func testBlenderOutputDimensions() async {
        let blender = ImageBlender()
        let width = 300
        let h1 = 400
        let h2 = 500
        let overlap = 100
        
        let img1 = createColorImage(width: width, height: h1, red: 1.0, green: 0.0, blue: 0.0)
        let img2 = createColorImage(width: width, height: h2, red: 0.0, green: 0.0, blue: 1.0)
        
        let blended = await blender.blendTwoImages(
            image1: img1,
            image2: img2,
            overlapOffset: 0,
            overlapHeight: overlap,
            blendTransitionWidth: 30
        )
        
        XCTAssertNotNil(blended)
        if let blended {
            XCTAssertEqual(blended.width, width)
            XCTAssertEqual(blended.height, h1 + h2 - overlap)
        }
    }
}
