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
        
        // 3. Compute canvas offsets for all images
        var offsets: [Int] = [0]
        for i in 1..<totalCount {
            let prevHeight = cgImages[i - 1].height
            let overlap = overlaps[i - 1]
            let nextOffset = offsets[i - 1] + (prevHeight - overlap)
            offsets.append(nextOffset)
        }
        
        let totalCanvasHeight = (offsets.last ?? 0) + (cgImages.last?.height ?? 0)
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
            
            for i in 0..<totalCount {
                autoreleasepool {
                    let frame = cgImages[i]
                    let yOffset = CGFloat(offsets[i])
                    let frameHeight = CGFloat(frame.height)
                    
                    if i == 0 {
                        UIImage(cgImage: frame).draw(in: CGRect(x: 0, y: yOffset, width: cgWidth, height: frameHeight))
                    } else {
                        let overlap = overlaps[i - 1]
                        let transitionHeight = max(0, min(overlap, blendWidth))
                        
                        // Blend transition band if overlapping
                        self.drawBlendedSlice(
                            ctx: ctx,
                            frame: frame,
                            blendStartY: yOffset,
                            transitionHeight: transitionHeight,
                            cgWidth: cgWidth
                        )
                        
                        // Draw non-overlapping body of frame
                        let newContentY = CGFloat(transitionHeight)
                        let newContentHeight = frameHeight - newContentY
                        if newContentHeight > 0 {
                            let contentRect = CGRect(x: 0, y: newContentY, width: cgWidth, height: newContentHeight).integral
                            if let newPart = frame.safeCropping(to: contentRect) {
                                UIImage(cgImage: newPart).draw(in: CGRect(x: 0, y: yOffset + newContentY, width: cgWidth, height: newContentHeight))
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
        
        await progressHandler(0.86, "正在裁剪固定状态栏与导航栏...")
        
        let width = keyFrames[0].image.width
        let height = keyFrames[0].image.height
        let topCrop = fixedRegions.topHeight
        let bottomCrop = fixedRegions.bottomHeight
        let effectiveContentHeight = max(10, height - topCrop - bottomCrop)
        let cgWidth = CGFloat(width)
        let cgEffectiveHeight = CGFloat(effectiveContentHeight)
        
        // 1. Crop fixed UI from each keyframe
        let croppedFrames: [CGImage] = keyFrames.compactMap { kf in
            let cropRect = CGRect(
                x: 0,
                y: CGFloat(topCrop),
                width: cgWidth,
                height: cgEffectiveHeight
            )
            return kf.image.safeCropping(to: cropRect)
        }
        
        guard croppedFrames.count >= 2 else {
            throw RecordingError.insufficientKeyFrames
        }
        
        // 2. Calculate offsets on final canvas
        var offsets: [Int] = [0]
        for i in 1..<keyFrames.count {
            let frameDelta = keyFrames[i].cumulativeOffset - keyFrames[i - 1].cumulativeOffset
            let adjustedDelta = Int(frameDelta)
            if adjustedDelta <= 0 {
                AppLogger.stitching.warning("Non-positive frame delta between keyframes \(i-1) and \(i): \(adjustedDelta)px")
            }
            let step = max(0, min(adjustedDelta, effectiveContentHeight))
            let nextOffset = offsets[i - 1] + step
            offsets.append(nextOffset)
        }
        
        let bodyTotalHeight = (offsets.last ?? 0) + effectiveContentHeight
        let totalCanvasHeight = topCrop + bodyTotalHeight + bottomCrop
        guard totalCanvasHeight <= 32768 else {
            throw RecordingError.stitchingFailed("长截图高度超出系统单图上限（\(totalCanvasHeight)px > 32768px），请适当缩短录屏长度")
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.90, "正在合成长截图画布（\(width)×\(totalCanvasHeight)px）...")
        
        // 3. Render directly in a single pass (Top Fixed UI + Keyframe Body + Bottom Fixed UI)
        let canvasSize = CGSize(width: cgWidth, height: CGFloat(totalCanvasHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let stitchedImage = renderer.image { context in
            let ctx = context.cgContext
            
            // 3.1 Draw Status Bar if present
            if topCrop > 0, let firstFull = keyFrames.first?.image,
               let topPart = firstFull.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop))) {
                UIImage(cgImage: topPart).draw(in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop)))
            }
            
            // 3.2 Draw Stitched Keyframe Segments
            let cgTopOffset = CGFloat(topCrop)
            for (index, frame) in croppedFrames.enumerated() {
                autoreleasepool {
                    let yOffset = cgTopOffset + CGFloat(offsets[index])
                    
                    if index == 0 {
                        // First frame rendered completely
                        UIImage(cgImage: frame).draw(in: CGRect(x: 0, y: yOffset, width: cgWidth, height: cgEffectiveHeight))
                    } else {
                        let stepDelta = offsets[index] - offsets[index - 1]
                        let overlap = max(0, effectiveContentHeight - stepDelta)
                        let transitionHeight = min(overlap, blendWidth)
                        
                        // Blend transition band if overlapping
                        self.drawBlendedSlice(
                            ctx: ctx,
                            frame: frame,
                            blendStartY: yOffset,
                            transitionHeight: transitionHeight,
                            cgWidth: cgWidth
                        )
                        
                        // Draw non-overlapping new content
                        let newContentY = CGFloat(transitionHeight)
                        let newContentHeight = cgEffectiveHeight - newContentY
                        if newContentHeight > 0 {
                            let contentRect = CGRect(x: 0, y: newContentY, width: cgWidth, height: newContentHeight).integral
                            if let newPart = frame.safeCropping(to: contentRect) {
                                UIImage(cgImage: newPart).draw(in: CGRect(x: 0, y: yOffset + newContentY, width: cgWidth, height: newContentHeight))
                            }
                        }
                    }
                }
            }
            
            // 3.3 Draw Bottom Bar if present
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
