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
        let adaptive = CropConfig.adaptive(for: CGSize(width: width, height: height))
        let topHeaderHeight = Int((adaptive.statusBarHeight * baselineScale).rounded())
        let bottomFooterHeight = Int((adaptive.bottomSafeArea * baselineScale).rounded())
        let effectiveContentHeight = max(20, height - topHeaderHeight - bottomFooterHeight)
        
        // 2. Sequentially find displacements between adjacent screenshot pairs
        var displacements: [Int] = []
        for i in 0..<(totalCount - 1) {
            if Task.isCancelled { throw RecordingError.processingCancelled }
            
            let pairProgress = 0.10 + (Double(i) / Double(totalCount - 1)) * 0.70
            await progressHandler(pairProgress, "正在匹配拼接第 \(i + 1)/\(totalCount) 张截图...")
            
            let img1 = cgImages[i]
            let img2 = cgImages[i + 1]
            
            if let overlap = await overlapDetector.findOverlap(bottomOf: img1, topOf: img2) {
                let deltaY = overlap.refY - overlap.matchY
                let validDelta = max(10, min(deltaY, effectiveContentHeight))
                displacements.append(validDelta)
            } else {
                AppLogger.stitching.warning("Failed to find strong overlap between image \(i) and \(i + 1). Using default safe cut.")
                displacements.append(effectiveContentHeight)
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        // 3. Compute seamless slices using Consistent Cumulative Displacement Geometry
        struct ImageSlice {
            let image: CGImage
            let srcRect: CGRect
            let destY: CGFloat
            let height: CGFloat
        }
        
        var slices: [ImageSlice] = []
        var currentCanvasY: CGFloat = 0
        let anchorCutY = height - bottomFooterHeight
        
        // Image 0: From 0 down to anchorCutY
        let firstSliceHeight = anchorCutY
        let firstRect = CGRect(x: 0, y: 0, width: width, height: firstSliceHeight)
        slices.append(ImageSlice(
            image: cgImages[0],
            srcRect: firstRect,
            destY: 0,
            height: CGFloat(firstSliceHeight)
        ))
        currentCanvasY += CGFloat(firstSliceHeight)
        
        // Middle Images: Slices with height = displacements[i - 1] starting at (anchorCutY - displacements[i - 1])
        for i in 1..<(totalCount - 1) {
            let delta = displacements[i - 1]
            let startY = max(0, anchorCutY - delta)
            let sliceH = max(1, delta)
            let srcRect = CGRect(x: 0, y: startY, width: width, height: sliceH)
            
            slices.append(ImageSlice(
                image: cgImages[i],
                srcRect: srcRect,
                destY: currentCanvasY,
                height: CGFloat(sliceH)
            ))
            currentCanvasY += CGFloat(sliceH)
        }
        
        // Last Image: From (anchorCutY - displacements.last) to height
        let lastIndex = totalCount - 1
        let lastDelta = displacements[lastIndex - 1]
        let lastStartY = max(0, anchorCutY - lastDelta)
        let lastSliceH = max(1, height - lastStartY)
        let lastRect = CGRect(x: 0, y: lastStartY, width: width, height: lastSliceH)
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
                        let drawRect = CGRect(x: 0, y: slice.destY, width: cgWidth, height: slice.height)
                        UIImage(cgImage: cropped).draw(in: drawRect)
                    }
                }
            }
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.98, "截图拼接完成！")
        
        if let cgResult = stitchedImage.cgImage {
            return UIImage(cgImage: cgResult, scale: baselineScale, orientation: .up)
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
        
        let adaptive = CropConfig.adaptive(for: CGSize(width: width, height: height))
        let adaptiveTop = Int((adaptive.statusBarHeight * baselineScale).rounded())
        let adaptiveBottom = Int((adaptive.bottomSafeArea * baselineScale).rounded())
        
        let topCrop = max(fixedRegions.topHeight, adaptiveTop)
        let bottomCrop = max(fixedRegions.bottomHeight, adaptiveBottom)
        
        let contentTop = topCrop
        let contentBottom = max(contentTop + 20, height - bottomCrop)
        let effectiveContentHeight = contentBottom - contentTop
        let cgWidth = CGFloat(width)
        
        // 1. Compute pixel-accurate displacement between consecutive keyframes
        //    Prioritizes refined search guided by Vision tracking displacement within the
        //    active scroll content ROI (excluding fixed top & bottom UI), then falls back to full overlap search.
        var displacements: [Int] = []
        let totalPairs = keyFrames.count - 1
        
        // Pre-crop content area for fallback matching
        let contentRect = CGRect(x: 0, y: CGFloat(contentTop), width: cgWidth, height: CGFloat(effectiveContentHeight))
        
        for i in 0..<totalPairs {
            if Task.isCancelled { throw RecordingError.processingCancelled }
            
            let pairProgress = 0.86 + (Double(i) / Double(totalPairs)) * 0.05
            await progressHandler(pairProgress, "正在像素级对齐关键帧（\(i + 1)/\(totalPairs)）...")
            
            let img1 = keyFrames[i].image
            let img2 = keyFrames[i + 1].image
            let expectedDelta = keyFrames[i + 1].cumulativeOffset - keyFrames[i].cumulativeOffset
            
            let (refinedDelta, confidence) = await overlapDetector.findRefinedDisplacement(
                from: img1,
                to: img2,
                expectedDeltaY: expectedDelta,
                topCrop: topCrop,
                bottomCrop: bottomCrop,
                referenceStripHeight: 140
            )
            
            let finalDelta: Int
            if confidence >= 0.50 {
                finalDelta = max(1, min(refinedDelta, effectiveContentHeight - 5))
                AppLogger.stitching.info("Recording overlap: keyframe \(i)→\(i+1) refined deltaY=\(finalDelta), confidence=\(confidence)")
            } else {
                let croppedImg1 = img1.safeCropping(to: contentRect) ?? img1
                let croppedImg2 = img2.safeCropping(to: contentRect) ?? img2
                
                if let overlap = await overlapDetector.findOverlap(
                    bottomOf: croppedImg1,
                    topOf: croppedImg2,
                    referenceStripHeight: 160
                ) {
                    let deltaY = overlap.refY - overlap.matchY
                    finalDelta = max(1, min(deltaY, effectiveContentHeight - 5))
                    AppLogger.stitching.info("Recording overlap: keyframe \(i)→\(i+1) fallback search deltaY=\(finalDelta), confidence=\(overlap.confidence)")
                } else {
                    let fallbackDelta = max(1, min(Int(expectedDelta.rounded()), effectiveContentHeight - 5))
                    finalDelta = fallbackDelta
                    AppLogger.stitching.warning("Recording overlap detection failed between keyframe \(i) and \(i+1), using Vision prior: \(fallbackDelta)")
                }
            }
            displacements.append(finalDelta)
        }
        
        // 2. Build seamless slices using Consistent Cumulative Displacement Geometry
        struct VideoSlice {
            let frame: CGImage
            let srcRect: CGRect
            let destY: CGFloat
            let height: CGFloat
        }
        
        var slices: [VideoSlice] = []
        var currentCanvasY: CGFloat = CGFloat(topCrop)
        let anchorCutY = contentBottom
        
        // Keyframe 0: From contentTop down to anchorCutY
        let firstH = anchorCutY - contentTop
        let firstRect = CGRect(x: 0, y: CGFloat(contentTop), width: cgWidth, height: CGFloat(firstH)).integral
        slices.append(VideoSlice(
            frame: keyFrames[0].image,
            srcRect: firstRect,
            destY: currentCanvasY,
            height: CGFloat(firstH)
        ))
        currentCanvasY += CGFloat(firstH)
        
        // Intermediate Keyframes: Slices of height = displacements[i - 1] starting at (anchorCutY - displacements[i - 1])
        for i in 1..<totalPairs {
            let delta = displacements[i - 1]
            let startY = anchorCutY - delta
            let sliceH = delta
            let srcRect = CGRect(x: 0, y: CGFloat(startY), width: cgWidth, height: CGFloat(sliceH)).integral
            
            slices.append(VideoSlice(
                frame: keyFrames[i].image,
                srcRect: srcRect,
                destY: currentCanvasY,
                height: CGFloat(sliceH)
            ))
            currentCanvasY += CGFloat(sliceH)
        }
        
        // Last Keyframe: From (anchorCutY - displacements.last) to contentBottom
        let lastIndex = keyFrames.count - 1
        let lastDelta = displacements[lastIndex - 1]
        let lastStartY = anchorCutY - lastDelta
        let lastH = contentBottom - lastStartY
        let lastRect = CGRect(x: 0, y: CGFloat(lastStartY), width: cgWidth, height: CGFloat(lastH)).integral
        slices.append(VideoSlice(
            frame: keyFrames[lastIndex].image,
            srcRect: lastRect,
            destY: currentCanvasY,
            height: CGFloat(lastH)
        ))
        currentCanvasY += CGFloat(lastH)
        
        let totalCanvasHeight = Int(currentCanvasY) + bottomCrop
        guard totalCanvasHeight <= 32768 else {
            throw RecordingError.stitchingFailed("长截图高度超出系统单图上限（\(totalCanvasHeight)px > 32768px），请适当缩短录屏长度")
        }
        
        if Task.isCancelled { throw RecordingError.processingCancelled }
        
        await progressHandler(0.92, "正在合成无缝长截图画布（\(width)×\(totalCanvasHeight)px）...")
        
        // 3. Single-pass high-efficiency rendering (Top Fixed UI + Sequential Content Slices + Bottom Fixed UI)
        let canvasSize = CGSize(width: cgWidth, height: CGFloat(totalCanvasHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let stitchedImage = renderer.image { _ in
            // 3.1 Draw Status Bar & Header once from first frame
            if topCrop > 0, let firstFull = keyFrames.first?.image,
               let topPart = firstFull.safeCropping(to: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop))) {
                UIImage(cgImage: topPart).draw(in: CGRect(x: 0, y: 0, width: cgWidth, height: CGFloat(topCrop)))
            }
            
            // 3.2 Draw Sequential Body Slices with pixel-precise alignment
            for slice in slices {
                autoreleasepool {
                    if let cropped = slice.frame.safeCropping(to: slice.srcRect) {
                        let renderRect = CGRect(x: 0, y: slice.destY, width: cgWidth, height: slice.height)
                        UIImage(cgImage: cropped).draw(in: renderRect)
                    }
                }
            }
            
            // 3.3 Draw Bottom Bar once from last frame
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
        
        let finalImage: UIImage
        if let cgResult = stitchedImage.cgImage {
            finalImage = UIImage(cgImage: cgResult, scale: baselineScale, orientation: .up)
        } else {
            finalImage = stitchedImage
        }
        
        await progressHandler(1.0, "长截图生成完毕！")
        return finalImage
    }
}
