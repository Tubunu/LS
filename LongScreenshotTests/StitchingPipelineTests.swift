import XCTest
import UIKit
@testable import LongScreenshotCore

final class StitchingPipelineTests: XCTestCase {
    
    private func createTestUIImage(width: Int, height: Int, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    
    func testImagePreprocessorCrop() {
        let preprocessor = ImagePreprocessor()
        let image = createTestUIImage(width: 300, height: 600, color: .systemBlue)
        let config = CropConfig(statusBarHeight: 50, bottomSafeArea: 30, navBarHeight: 0, tabBarHeight: 0)
        
        // Intermediate image (index 1 of 3) crops both top and bottom
        let intermediate = preprocessor.preprocessImage(image, at: 1, total: 3, config: config)
        
        guard let cg = intermediate.cgImage else {
            XCTFail("Should have CGImage")
            return
        }
        
        XCTAssertEqual(cg.width, 300)
        XCTAssertEqual(cg.height, 600 - 50 - 30)
    }
    
    func testStitchingEngineRecordingStitch() async throws {
        let engine = ImageStitchingEngine()
        let img1 = createTestUIImage(width: 200, height: 300, color: .red).cgImage!
        let img2 = createTestUIImage(width: 200, height: 300, color: .blue).cgImage!
        
        let kf1 = KeyFrame(image: img1, cumulativeOffset: 0, timestamp: .zero, index: 0)
        let kf2 = KeyFrame(image: img2, cumulativeOffset: 150, timestamp: .zero, index: 1)
        
        let result = try await engine.stitchFromRecording(
            keyFrames: [kf1, kf2],
            fixedRegions: FixedUIDetector.FixedRegions.zero,
            blendWidth: 20
        ) { _, _ in }
        
        XCTAssertGreaterThan(result.size.height, 300)
        XCTAssertEqual(Int(result.size.width), 200)
    }
}
