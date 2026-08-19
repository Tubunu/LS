import UIKit
import CoreGraphics

/// Unified core stitching engine supporting both multi-screenshot alignment and video keyframe stitching
public actor ImageStitchingEngine {
    
    private let overlapDetector = OverlapDetector()
    private let imageBlender = ImageBlender()
    private let imagePreprocessor = ImagePreprocessor()
    
    public init() {}
    
    // MARK: - Mode A: Screenshot Stitching
    
    /// Stitches an array of overlapping screenshots into a seamless long screenshot
    public func stitchScreenshots(
        _ images: [UIImage],
        config: CropConfig = .standard,
        blendWidth: Int = 40,
        progressHandler: @Sendable (Double, String) -> Void
    ) async throws -> UIImage {
        guard images.count >= 2 else {
            throw RecordingError.insufficientFrames
        }
        
        let totalCount = images.count
        progressHandler(0.05, "正在预处理截图（共 \(totalCount) 张）...")
        
        // 1. Preprocess screenshots to remove repeated status bar / home bars
        let preprocessed = imagePreprocessor.preprocessBatch(images, config: config)
        
        guard let firstCG = preprocessed[0].cgImage else {
            throw RecordingError.stitchingFailed("无法解析首张截图的图像数据")
        }
        
        var currentCanvasCG: CGImage = firstCG
        
        // 2. Sequentially find overlap and blend
        for i in 1..<totalCount {
            guard let nextCG = preprocessed[i].cgImage else { continue }
            
            let pairProgress = 0.10 + (Double(i) / Double(totalCount)) * 0.75
            progressHandler(pairProgress, "正在匹配拼接第 \(i + 1)/\(totalCount) 张截图...")
            
            guard let overlap = await overlapDetector.findOverlap(bottomOf: currentCanvasCG, topOf: nextCG) else {
                // If overlap confidence is too low, fall back to direct stacking or error
                AppLogger.stitching.warning("Failed to find strong overlap between image \(i) and \(i + 1). Falling back to direct concatenation.")
                guard let fallbackBlend = await imageBlender.blendTwoImages(
                    image1: currentCanvasCG,
                    image2: nextCG,
                    overlapOffset: 0,
                    overlapHeight: 0,
                    blendTransitionWidth: 0
                ) else {
                    throw RecordingError.stitchingFailed("拼接第 \(i + 1) 张截图失败，重叠度不足")
                }
                currentCanvasCG = fallbackBlend
                continue
            }
            
            guard let blendedCG = await imageBlender.blendTwoImages(
                image1: currentCanvasCG,
                image2: nextCG,
                overlapOffset: overlap.offset,
                overlapHeight: overlap.overlapHeight,
                blendTransitionWidth: blendWidth
            ) else {
                throw RecordingError.stitchingFailed("图像融合渲染失败")
            }
            
            currentCanvasCG = blendedCG
        }
        
        progressHandler(0.95, "正在生成高分辨率长图...")
        let resultImage = UIImage(cgImage: currentCanvasCG, scale: images[0].scale, orientation: .up)
        progressHandler(1.0, "拼接完成！")
        return resultImage
    }
    
    // MARK: - Mode B: Screen Recording Stitching
    
    /// Stitches keyframes extracted from video using known translation offsets
    public func stitchFromRecording(
        keyFrames: [KeyFrame],
        fixedRegions: FixedUIDetector.FixedRegions,
        blendWidth: Int = 40,
        progressHandler: @Sendable (Double, String) -> Void
    ) async throws -> UIImage {
        guard keyFrames.count >= 2 else {
            throw RecordingError.insufficientKeyFrames
        }
        
        progressHandler(0.86, "正在裁剪固定状态栏与导航栏...")
        
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
        var totalCanvasHeight = effectiveContentHeight
        
        for i in 1..<keyFrames.count {
            let frameDelta = keyFrames[i].cumulativeOffset - keyFrames[i - 1].cumulativeOffset
            let adjustedDelta = Int(frameDelta)
            let step = max(1, adjustedDelta)
            let nextOffset = offsets[i - 1] + step
            offsets.append(nextOffset)
            totalCanvasHeight = nextOffset + effectiveContentHeight
        }
        
        progressHandler(0.90, "正在合成长截图画布（\(width)×\(totalCanvasHeight)px）...")
        
        // 3. Render into canvas
        let canvasSize = CGSize(width: cgWidth, height: CGFloat(totalCanvasHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let stitchedBody = renderer.image { context in
            let ctx = context.cgContext
            
            for (index, frame) in croppedFrames.enumerated() {
                let yOffset = CGFloat(offsets[index])
                
                if index == 0 {
                    // First frame rendered completely
                    ctx.draw(frame, in: CGRect(x: 0, y: yOffset, width: cgWidth, height: cgEffectiveHeight))
                } else {
                    let stepDelta = offsets[index] - offsets[index - 1]
                    let overlap = max(0, effectiveContentHeight - stepDelta)
                    let transitionHeight = min(overlap, blendWidth)
                    
                    // Blend transition band if overlapping
                    if transitionHeight > 0 {
                        let blendStartY = yOffset
                        for row in 0..<transitionHeight {
                            let alpha = CGFloat(row) / CGFloat(transitionHeight)
                            let sliceRect = CGRect(x: 0, y: CGFloat(row), width: cgWidth, height: 1.0)
                            if let rowImg = frame.safeCropping(to: sliceRect) {
                                ctx.saveGState()
                                ctx.setAlpha(alpha)
                                ctx.draw(rowImg, in: CGRect(x: 0, y: blendStartY + CGFloat(row), width: cgWidth, height: 1.0))
                                ctx.restoreGState()
                            }
                        }
                    }
                    
                    // Draw non-overlapping new content
                    let newContentY = transitionHeight
                    let newContentHeight = effectiveContentHeight - newContentY
                    if newContentHeight > 0 {
                        let contentRect = CGRect(x: 0, y: CGFloat(newContentY), width: cgWidth, height: CGFloat(newContentHeight))
                        if let newPart = frame.safeCropping(to: contentRect) {
                            ctx.draw(newPart, in: CGRect(x: 0, y: yOffset + CGFloat(newContentY), width: cgWidth, height: CGFloat(newContentHeight)))
                        }
                    }
                }
            }
        }
        
        // 4. Attach original top status bar and bottom bar if present
        progressHandler(0.96, "正在拼接顶部状态栏与底部安全区...")
        let finalImage: UIImage
        if topCrop > 0 || bottomCrop > 0, let firstFull = keyFrames.first?.image, let lastFull = keyFrames.last?.image {
            finalImage = addFixedUI(
                to: stitchedBody,
                statusBar: firstFull,
                bottomBar: lastFull,
                fixedRegions: fixedRegions
            )
        } else {
            finalImage = stitchedBody
        }
        
        progressHandler(1.0, "长截图生成完毕！")
        return finalImage
    }
    
    private func addFixedUI(
        to mainImage: UIImage,
        statusBar sourceTop: CGImage,
        bottomBar sourceBottom: CGImage,
        fixedRegions: FixedUIDetector.FixedRegions
    ) -> UIImage {
        let width = Int(mainImage.size.width)
        let mainHeight = Int(mainImage.size.height)
        let totalHeight = fixedRegions.topHeight + mainHeight + fixedRegions.bottomHeight
        let cgWidth = CGFloat(width)
        let cgTopHeight = CGFloat(fixedRegions.topHeight)
        let cgBottomHeight = CGFloat(fixedRegions.bottomHeight)
        let cgMainHeight = CGFloat(mainHeight)
        
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: cgWidth, height: CGFloat(totalHeight)),
            format: {
                let f = UIGraphicsImageRendererFormat()
                f.scale = 1.0
                f.opaque = true
                return f
            }()
        )
        
        return renderer.image { context in
            let ctx = context.cgContext
            
            // 1. Status bar
            if fixedRegions.topHeight > 0,
               let top = sourceTop.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: cgTopHeight)) {
                ctx.draw(top, in: CGRect(x: 0, y: 0, width: cgWidth, height: cgTopHeight))
            }
            
            // 2. Main stitched content
            if let mainCG = mainImage.cgImage {
                ctx.draw(mainCG, in: CGRect(x: 0, y: cgTopHeight, width: cgWidth, height: cgMainHeight))
            }
            
            // 3. Bottom bar
            if fixedRegions.bottomHeight > 0 {
                let bottomY = sourceBottom.height - fixedRegions.bottomHeight
                if let bottom = sourceBottom.safeCropping(to: CGRect(x: 0, y: CGFloat(bottomY), width: cgWidth, height: cgBottomHeight)) {
                    ctx.draw(bottom, in: CGRect(x: 0, y: cgTopHeight + cgMainHeight, width: cgWidth, height: cgBottomHeight))
                }
            }
        }
    }
}
