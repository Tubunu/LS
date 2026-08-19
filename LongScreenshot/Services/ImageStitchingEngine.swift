import UIKit
import CoreGraphics

/// Unified core stitching engine supporting both multi-screenshot alignment and video keyframe stitching
public actor ImageStitchingEngine {
    
    private let overlapDetector = OverlapDetector()
    private let imageBlender = ImageBlender()
    private let imagePreprocessor = ImagePreprocessor()
    
    public init() {}
    
    // MARK: - Mode A: Screenshot Stitching
    
    /// Stitches an array of overlapping screenshots into a seamless long screenshot in a single high-efficiency render pass
    public func stitchScreenshots(
        _ images: [UIImage],
        config: CropConfig = .standard,
        blendWidth: Int = 40,
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> UIImage {
        guard images.count >= 2 else {
            throw RecordingError.insufficientFrames
        }
        
        let totalCount = images.count
        await progressHandler(0.05, "正在预处理截图（共 \(totalCount) 张）...")
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        // 1. Load normalized CGImages
        let widthNormalized = imagePreprocessor.preprocessBatch(images, config: .zero)
        let cgImages = widthNormalized.compactMap { $0.cgImage }
        
        guard cgImages.count == totalCount else {
            throw RecordingError.stitchingFailed("无法解析截图的图像数据")
        }
        
        let width = cgImages[0].width
        let height = cgImages[0].height
        guard width > 0, height > 0 else {
            throw RecordingError.stitchingFailed("截图尺寸异常")
        }
        
        let baselineScale: CGFloat = (width >= 1000 ? 3.0 : (width >= 640 ? 2.0 : 1.0))
        let topHeaderHeight = Int((105.0 * baselineScale).rounded())
        let bottomFooterHeight = Int((85.0 * baselineScale).rounded())
        
        // 2. Sequentially find scroll displacement deltaY between adjacent pairs
        var deltaYs: [Int] = []
        for i in 0..<(totalCount - 1) {
            if Task.isCancelled { throw RecordingError.processingCancelled }
            
            let pairProgress = 0.10 + (Double(i) / Double(totalCount - 1)) * 0.70
            await progressHandler(pairProgress, "正在匹配拼接第 \(i + 1)/\(totalCount) 张截图...")
            
            let img1 = cgImages[i]
            let img2 = cgImages[i + 1]
            
            if let overlap = await overlapDetector.findOverlap(bottomOf: img1, topOf: img2) {
                let dy = max(10, min(height, height - overlap.overlapHeight))
                deltaYs.append(dy)
            } else {
                AppLogger.stitching.warning("Failed to find strong overlap between image \(i) and \(i + 1). Using default viewport scroll distance.")
                let defaultScroll = max(100, height - topHeaderHeight - bottomFooterHeight)
                deltaYs.append(defaultScroll)
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        // 3. Compute clean 3-zone slices (Header once, Pure Scrolling Body, Footer once)
        struct ImageSlice {
            let image: CGImage
            let srcRect: CGRect
            let destY: CGFloat
            let height: CGFloat
        }
        
        var slices: [ImageSlice] = []
        var currentCanvasY: CGFloat = 0
        
        // Image 0: Top Header + First Screen Body (omits Image 0's bottom toolbar)
        let firstSliceHeight = min(height - bottomFooterHeight, topHeaderHeight + deltaYs[0])
        let firstRect = CGRect(x: 0, y: 0, width: width, height: firstSliceHeight)
        slices.append(ImageSlice(
            image: cgImages[0],
            srcRect: firstRect,
            destY: 0,
            height: CGFloat(firstSliceHeight)
        ))
        currentCanvasY += CGFloat(firstSliceHeight)
        
        // Middle Images: Only Pure Scrolling Body (omits top headers & bottom toolbars)
        for i in 1..<(totalCount - 1) {
            let dy = deltaYs[i]
            let srcY = topHeaderHeight
            let sliceH = min(dy, height - topHeaderHeight - bottomFooterHeight)
            let srcRect = CGRect(x: 0, y: srcY, width: width, height: sliceH)
            
            slices.append(ImageSlice(
                image: cgImages[i],
                srcRect: srcRect,
                destY: currentCanvasY,
                height: CGFloat(sliceH)
            ))
            currentCanvasY += CGFloat(sliceH)
        }
        
        // Last Image: Starts strictly below top header, draws all the way to bottom footer
        let lastIndex = totalCount - 1
        let lastSrcY = topHeaderHeight
        let lastSliceH = max(10, height - lastSrcY)
        let lastRect = CGRect(x: 0, y: lastSrcY, width: width, height: lastSliceH)
        slices.append(ImageSlice(
            image: cgImages[lastIndex],
            srcRect: lastRect,
            destY: currentCanvasY,
            height: CGFloat(lastSliceH)
        ))
        currentCanvasY += CGFloat(lastSliceH)
        
        let totalCanvasHeight = Int(currentCanvasY)
        guard totalCanvasHeight > 0 else {
            throw RecordingError.stitchingFailed("生成的画布高度异常")
        }
        guard totalCanvasHeight <= 32768 else {
            throw RecordingError.stitchingFailed("长截图高度超出系统单图上限（\(totalCanvasHeight)px > 32768px），请适当缩短拼接范围")
        }
        
        await progressHandler(0.85, "正在合成高分辨率长图画布（\(width)×\(totalCanvasHeight)px）...")
        
        // 4. Single-pass high-efficiency rendering
        let cgWidth = CGFloat(width)
        let canvasSize = CGSize(width: cgWidth, height: CGFloat(totalCanvasHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let stitchedImage = renderer.image { _ in
            for slice in slices {
                autoreleasepool {
                    if let cropped = slice.image.safeCropping(to: slice.srcRect) {
                        let drawRect = CGRect(x: 0, y: slice.destY, width: cgWidth, height: slice.height + 1.0)
                        UIImage(cgImage: cropped).draw(in: drawRect)
                    }
                }
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.98, "截图拼接完成！")
        let targetScale: CGFloat
        if width >= 1000 {
            targetScale = 3.0
        } else if width >= 640 {
            targetScale = 2.0
        } else {
            targetScale = 1.0
        }
        
        if let cgResult = stitchedImage.cgImage {
            return UIImage(cgImage: cgResult, scale: targetScale, orientation: .up)
        } else {
            return stitchedImage
        }
    }
    
    // MARK: - Mode B: Screen Recording Stitching
    
    /// Stitches sequential video keyframes into a seamless long screenshot
    /// - Parameters:
    ///   - keyFrames: Array of extracted keyframes with cumulative displacement offsets
    ///   - fixedRegions: Identified stationary UI regions (Status bar, Tab bar)
    ///   - blendWidth: Width in pixels for transition blending at stitch boundaries (default: 40px)
    ///   - progressHandler: Closure reporting progress (0.0 to 1.0) and status messages
    /// - Returns: Complete stitched UIImage
    public func stitchFromRecording(
        keyFrames: [KeyFrame],
        fixedRegions: FixedUIDetector.FixedRegions = .zero,
        blendWidth: Int = 40,
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> UIImage {
        guard keyFrames.count >= 2 else {
            throw RecordingError.insufficientKeyFrames
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.86, "正在分析固定状态栏与导航栏...")
        
        let width = keyFrames[0].image.width
        let height = keyFrames[0].image.height
        let baselineScale: CGFloat = (width >= 1000 ? 3.0 : (width >= 640 ? 2.0 : 1.0))
        
        let minTopCrop = Int((105.0 * baselineScale).rounded())
        let minBottomCrop = Int((85.0 * baselineScale).rounded())
        
        let topCrop = max(fixedRegions.topHeight, minTopCrop)
        let bottomCrop = max(fixedRegions.bottomHeight, minBottomCrop)
        let effectiveContentHeight = max(10, height - topCrop - bottomCrop)
        let cgWidth = CGFloat(width)
        let cgEffectiveHeight = CGFloat(effectiveContentHeight)
        
        // 1. Calculate slice steps from keyframe cumulative displacement
        struct VideoSlice {
            let frame: CGImage
            let srcRect: CGRect
            let destY: CGFloat
            let height: CGFloat
        }
        
        var slices: [VideoSlice] = []
        var currentCanvasY: CGFloat = CGFloat(topCrop)
        
        // First keyframe contributes the initial viewport body (omitting bottom toolbar)
        let firstBodyRect = CGRect(x: 0, y: CGFloat(topCrop), width: cgWidth, height: cgEffectiveHeight)
        slices.append(VideoSlice(
            frame: keyFrames[0].image,
            srcRect: firstBodyRect,
            destY: currentCanvasY,
            height: cgEffectiveHeight
        ))
        currentCanvasY += cgEffectiveHeight
        
        // Subsequent keyframes contribute only their bottom newly-revealed content slices
        for i in 1..<keyFrames.count {
            let frameDelta = keyFrames[i].cumulativeOffset - keyFrames[i - 1].cumulativeOffset
            let adjustedDelta = Int(frameDelta)
            let step = max(0, min(adjustedDelta, effectiveContentHeight))
            guard step > 0 else { continue }
            
            let sliceY = CGFloat(topCrop + effectiveContentHeight - step)
            let sliceRect = CGRect(x: 0, y: sliceY, width: cgWidth, height: CGFloat(step)).integral
            
            slices.append(VideoSlice(
                frame: keyFrames[i].image,
                srcRect: sliceRect,
                destY: currentCanvasY,
                height: CGFloat(step)
            ))
            currentCanvasY += CGFloat(step)
        }
        
        let totalCanvasHeight = Int(currentCanvasY) + bottomCrop
        guard totalCanvasHeight <= 32768 else {
            throw RecordingError.stitchingFailed("长截图高度超出系统单图上限（\(totalCanvasHeight)px > 32768px），请适当缩短录屏长度")
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.90, "正在合成长截图画布（\(width)×\(totalCanvasHeight)px）...")
        
        // 2. Render directly in a single pass (Top Fixed UI + Sequential Slices + Bottom Fixed UI)
        let canvasSize = CGSize(width: cgWidth, height: CGFloat(totalCanvasHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let stitchedImage = renderer.image { _ in
            // 2.1 Draw Status Bar & Header once from first frame
            if topCrop > 0, let firstFull = keyFrames.first?.image,
               let topPart = firstFull.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop))) {
                UIImage(cgImage: topPart).draw(in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop)))
            }
            
            // 2.2 Draw Sequential Body Slices
            for slice in slices {
                autoreleasepool {
                    if let cropped = slice.frame.safeCropping(to: slice.srcRect) {
                        // Add 1.0px vertical overlap bleed to eliminate subpixel white line gaps between slices
                        let renderRect = CGRect(x: 0, y: slice.destY, width: cgWidth, height: slice.height + 1.0)
                        UIImage(cgImage: cropped).draw(in: renderRect)
                    }
                }
            }
            
            // 2.3 Draw Bottom Bar once from last frame
            if bottomCrop > 0, let lastFull = keyFrames.last?.image {
                let bottomY = lastFull.height - bottomCrop
                let bottomRect = CGRect(x: 0, y: CGFloat(bottomY), width: cgWidth, height: CGFloat(bottomCrop)).integral
                if let bottomPart = lastFull.safeCropping(to: bottomRect) {
                    let destY = CGFloat(totalCanvasHeight - bottomCrop)
                    UIImage(cgImage: bottomPart).draw(in: CGRect(x: 0, y: destY, width: cgWidth, height: CGFloat(bottomCrop)))
                }
            }
        }
        
        await progressHandler(0.98, "长截图生成完毕！")
        let targetScale: CGFloat
        if width >= 1000 {
            targetScale = 3.0
        } else if width >= 640 {
            targetScale = 2.0
        } else {
            targetScale = 1.0
        }
        
        let finalImage: UIImage
        if let cgResult = stitchedImage.cgImage {
            finalImage = UIImage(cgImage: cgResult, scale: targetScale, orientation: .up)
        } else {
            finalImage = stitchedImage
        }
        
        await progressHandler(1.0, "长截图生成完毕！")
        return finalImage
    }
    
    // MARK: - Helper Methods
    
    /// Renders an alpha-blended transition strip for overlapping adjacent images
    private func drawBlendedSlice(
        ctx: CGContext,
        frame: CGImage,
        blendStartY: CGFloat,
        transitionHeight: Int,
        cgWidth: CGFloat
    ) {
        guard transitionHeight > 0 else { return }
        let steps = min(transitionHeight, 20)
        
        for step in 0..<steps {
            autoreleasepool {
                let startY = (CGFloat(step) * CGFloat(transitionHeight) / CGFloat(steps)).rounded()
                let endY = (CGFloat(step + 1) * CGFloat(transitionHeight) / CGFloat(steps)).rounded()
                let sliceHeight = endY - startY
                guard sliceHeight > 0 else { return }
                
                let alpha = CGFloat(step + 1) / CGFloat(steps + 1)
                let destY = blendStartY + startY
                
                let sliceRect = CGRect(x: 0, y: startY, width: cgWidth, height: sliceHeight).integral
                if let slice = frame.safeCropping(to: sliceRect) {
                    ctx.saveGState()
                    ctx.setAlpha(alpha)
                    UIImage(cgImage: slice).draw(in: CGRect(x: 0, y: destY, width: cgWidth, height: sliceHeight))
                    ctx.restoreGState()
                }
            }
        }
    }
}
