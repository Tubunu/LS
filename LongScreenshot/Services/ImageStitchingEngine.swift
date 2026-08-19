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
        
        // 1. Preprocess screenshots to remove repeated status bar / home bars
        let preprocessed = imagePreprocessor.preprocessBatch(images, config: config)
        let cgImages = preprocessed.compactMap { $0.cgImage }
        
        guard cgImages.count == totalCount else {
            throw RecordingError.stitchingFailed("无法解析截图的图像数据")
        }
        
        let width = cgImages[0].width
        guard width > 0 else {
            throw RecordingError.stitchingFailed("截图宽度异常")
        }
        
        // 2. Sequentially find overlap between adjacent pairs
        var overlaps: [Int] = []
        for i in 0..<(totalCount - 1) {
            if Task.isCancelled { throw RecordingError.processingCancelled }
            
            let pairProgress = 0.10 + (Double(i) / Double(totalCount - 1)) * 0.70
            await progressHandler(pairProgress, "正在匹配拼接第 \(i + 1)/\(totalCount) 张截图...")
            
            let img1 = cgImages[i]
            let img2 = cgImages[i + 1]
            
            if let overlap = await overlapDetector.findOverlap(bottomOf: img1, topOf: img2) {
                let validOverlap = min(overlap.overlapHeight, min(img1.height, img2.height))
                overlaps.append(validOverlap)
            } else {
                AppLogger.stitching.warning("Failed to find strong overlap between image \(i) and \(i + 1). Falling back to direct concatenation.")
                overlaps.append(0)
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        // 3. Compute slice cut points and canvas placements
        struct ImageSlice {
            let image: CGImage
            let srcRect: CGRect
            let destY: CGFloat
            let transitionHeight: Int
            let addedCanvasHeight: Int
        }
        
        var slices: [ImageSlice] = []
        var totalCanvasHeight = cgImages[0].height
        
        // Image 0: entire image
        slices.append(ImageSlice(
            image: cgImages[0],
            srcRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(cgImages[0].height)),
            destY: 0,
            transitionHeight: 0,
            addedCanvasHeight: cgImages[0].height
        ))
        
        for i in 1..<totalCount {
            let imgPrev = cgImages[i - 1]
            let imgCurr = cgImages[i]
            let overlap = overlaps[i - 1]
            let currHeight = imgCurr.height
            
            if overlap > 0 {
                let cutY = overlap // In imgCurr, rows 0..<cutY overlap with imgPrev (or are static header UI)
                let transitionHeight = min(cutY, min(40, blendWidth))
                let srcY = cutY - transitionHeight
                let sliceHeight = max(0, currHeight - srcY)
                let addedHeight = max(0, currHeight - cutY)
                let destY = CGFloat(totalCanvasHeight - transitionHeight)
                
                let srcRect = CGRect(x: 0, y: CGFloat(srcY), width: CGFloat(width), height: CGFloat(sliceHeight)).integral
                slices.append(ImageSlice(
                    image: imgCurr,
                    srcRect: srcRect,
                    destY: destY,
                    transitionHeight: transitionHeight,
                    addedCanvasHeight: addedHeight
                ))
                totalCanvasHeight += addedHeight
            } else {
                // Fallback: direct concatenation
                let destY = CGFloat(totalCanvasHeight)
                let srcRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(currHeight))
                slices.append(ImageSlice(
                    image: imgCurr,
                    srcRect: srcRect,
                    destY: destY,
                    transitionHeight: 0,
                    addedCanvasHeight: currHeight
                ))
                totalCanvasHeight += currHeight
            }
        }
        
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
        let stitchedImage = renderer.image { context in
            let ctx = context.cgContext
            
            for (index, slice) in slices.enumerated() {
                autoreleasepool {
                    guard let cropped = slice.image.safeCropping(to: slice.srcRect) else { return }
                    let sliceH = slice.srcRect.height
                    
                    if index == 0 || slice.transitionHeight == 0 {
                        UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: slice.destY, width: cgWidth, height: sliceH))
                    } else {
                        let transH = slice.transitionHeight
                        // 1. Blend transition band with previous canvas
                        self.drawBlendedSlice(
                            ctx: ctx,
                            frame: cropped,
                            blendStartY: slice.destY,
                            transitionHeight: transH,
                            cgWidth: cgWidth
                        )
                        
                        // 2. Draw non-overlapping new content
                        let newContentY = CGFloat(transH)
                        let newContentH = sliceH - newContentY
                        if newContentH > 0 {
                            let newRect = CGRect(x: 0, y: newContentY, width: cgWidth, height: newContentH).integral
                            if let newPart = cropped.safeCropping(to: newRect) {
                                UIImage(cgImage: newPart).draw(in: CGRect(x: 0, y: slice.destY + newContentY, width: cgWidth, height: newContentH))
                            }
                        }
                    }
                }
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.95, "正在导出高清长图...")
        let originalScale = images.first?.scale ?? 1.0
        let effectiveScale: CGFloat
        if originalScale > 1.0 {
            effectiveScale = originalScale
        } else if width >= 1000 {
            effectiveScale = 3.0
        } else if width >= 640 {
            effectiveScale = 2.0
        } else {
            effectiveScale = 1.0
        }
        
        let finalImage: UIImage
        if let cgResult = stitchedImage.cgImage {
            finalImage = UIImage(cgImage: cgResult, scale: effectiveScale, orientation: .up)
        } else {
            finalImage = stitchedImage
        }
        
        await progressHandler(1.0, "拼接完成！")
        return finalImage
    }
    
    // MARK: - Mode B: Screen Recording Stitching
    
    /// Stitches keyframes extracted from video using known translation offsets in a single high-efficiency render pass
    public func stitchFromRecording(
        keyFrames: [KeyFrame],
        fixedRegions: FixedUIDetector.FixedRegions,
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
        let topCrop = fixedRegions.topHeight
        let bottomCrop = fixedRegions.bottomHeight
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
        
        // First keyframe contributes the initial viewport body
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
            // 2.1 Draw Status Bar once from first frame
            if topCrop > 0, let firstFull = keyFrames.first?.image,
               let topPart = firstFull.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop))) {
                UIImage(cgImage: topPart).draw(in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop)))
            }
            
            // 2.2 Draw Sequential Body Slices
            for slice in slices {
                autoreleasepool {
                    if let cropped = slice.frame.safeCropping(to: slice.srcRect) {
                        UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: slice.destY, width: cgWidth, height: slice.height))
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
