import XCTest
import UIKit
@testable import LongScreenshot

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
    
    func testImagePreprocessorRetinaEffectiveScale() {
        let preprocessor = ImagePreprocessor()
        // Simulate a 3x Retina screenshot loaded via data stream (width: 1179, height: 2556, scale: 1.0)
        let image = createTestUIImage(width: 1179, height: 2556, color: .systemGreen)
        let config = CropConfig(statusBarHeight: 59, bottomSafeArea: 34, navBarHeight: 0, tabBarHeight: 0)
        
        let intermediate = preprocessor.preprocessImage(image, at: 1, total: 3, config: config)
        guard let cg = intermediate.cgImage else {
            XCTFail("Should have CGImage")
            return
        }
        
        XCTAssertEqual(cg.width, 1179)
        // 3x scale: topCrop = 59 * 3 = 177, bottomCrop = 34 * 3 = 102
        XCTAssertEqual(cg.height, 2556 - (59 * 3) - (34 * 3))
        XCTAssertEqual(intermediate.scale, 3.0)
    }
    
    func testUIImageScaleDown() {
        let original = createTestUIImage(width: 400, height: 800, color: .purple)
        let scaled = original.scaled(by: 0.5)
        
        XCTAssertEqual(scaled.size.width, 200)
        XCTAssertEqual(scaled.size.height, 400)
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
        
        XCTAssertNotNil(result.cgImage)
        if let cg = result.cgImage {
            XCTAssertGreaterThan(cg.height, 300)
            XCTAssertEqual(cg.width, img1.width)
        }
        XCTAssertGreaterThanOrEqual(result.scale, 1.0)
    }
    
    func testCropConfigAdaptive() {
        // Dynamic Island
        let diConfig = CropConfig.adaptive(for: CGSize(width: 1179, height: 2556))
        XCTAssertEqual(diConfig.statusBarHeight, 59.0)
        XCTAssertEqual(diConfig.bottomSafeArea, 34.0)
        
        // Standard Notch (iPhone 13)
        let notchConfig = CropConfig.adaptive(for: CGSize(width: 1170, height: 2532))
        XCTAssertEqual(notchConfig.statusBarHeight, 47.0)
        XCTAssertEqual(notchConfig.bottomSafeArea, 34.0)
        
        // Classic 16:9 (iPhone SE)
        let seConfig = CropConfig.adaptive(for: CGSize(width: 750, height: 1334))
        XCTAssertEqual(seConfig.statusBarHeight, 20.0)
        XCTAssertEqual(seConfig.bottomSafeArea, 0.0)
        
        // iPad
        let ipadConfig = CropConfig.adaptive(for: CGSize(width: 2048, height: 2732))
        XCTAssertEqual(ipadConfig.statusBarHeight, 24.0)
        XCTAssertEqual(ipadConfig.bottomSafeArea, 20.0)
    }
    
    func testImagePreprocessorWidthNormalization() {
        let preprocessor = ImagePreprocessor()
        let img1 = createTestUIImage(width: 400, height: 600, color: .red)
        let img2 = createTestUIImage(width: 500, height: 800, color: .blue) // Different width
        
        let batch = preprocessor.preprocessBatch([img1, img2], config: .zero)
        XCTAssertEqual(batch.count, 2)
        
        guard let cg1 = batch[0].cgImage, let cg2 = batch[1].cgImage else {
            XCTFail("Should have valid CGImages")
            return
        }
        
        // Both images should be normalized to the first image's width (400px)
        XCTAssertEqual(cg1.width, 400)
        XCTAssertEqual(cg2.width, 400)
        // Aspect ratio maintained: 800 * (400/500) = 640
        XCTAssertEqual(cg2.height, 640)
    }
    
    func testStitchScreenshotsWorkflow() async throws {
        let engine = ImageStitchingEngine()
        let img1 = createTestUIImage(width: 300, height: 400, color: .orange)
        let img2 = createTestUIImage(width: 300, height: 400, color: .cyan)
        
        let result = try await engine.stitchScreenshots(
            [img1, img2],
            config: .zero,
            blendWidth: 20
        ) { _, _ in }
        
        XCTAssertNotNil(result.cgImage)
        if let cg = result.cgImage {
            XCTAssertEqual(cg.width, 300)
            XCTAssertGreaterThanOrEqual(cg.height, 400)
        }
    }
    
    func testImagePreprocessorWidthNormalizationWithExtremeAspectRatios() {
        let preprocessor = ImagePreprocessor()
        // Base image: 300x500
        let base = createTestUIImage(width: 300, height: 500, color: .red)
        // Ultra-wide image: 1200x200 (6:1)
        let ultraWide = createTestUIImage(width: 1200, height: 200, color: .green)
        // Ultra-tall image: 100x1000 (1:10)
        let ultraTall = createTestUIImage(width: 100, height: 1000, color: .blue)
        
        let batch = preprocessor.preprocessBatch([base, ultraWide, ultraTall], config: .zero)
        XCTAssertEqual(batch.count, 3)
        
        for (i, img) in batch.enumerated() {
            guard let cg = img.cgImage else {
                XCTFail("Frame \(i) must have valid CGImage")
                continue
            }
            XCTAssertEqual(cg.width, 300, "Frame \(i) width should normalize to base width 300")
            XCTAssertGreaterThan(cg.height, 0, "Frame \(i) height should be positive")
        }
    }
}
