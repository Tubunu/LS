import SwiftUI

@MainActor
public final class RecordingViewModel: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "准备就绪"
    @Published public var resultImage: UIImage?
    @Published public var isProcessing: Bool = false
    @Published public var error: RecordingError?
    
    private let frameExtractor = VideoFrameExtractor()
    private let scrollDetector = ScrollDetector()
    private let keyFrameSelector = KeyFrameSelector()
    private let fixedUIDetector = FixedUIDetector()
    private let stitchingEngine = ImageStitchingEngine()
    
    private var isCancelledManually: Bool = false
    private var processingTask: Task<Void, Never>?
    
    public init() {}
    
    /// Cancels active recording processing task
    public func cancelProcessing() {
        processingTask?.cancel()
        isCancelledManually = true
        isProcessing = false
        statusMessage = "处理已取消"
    }
    
    /// Processes a screen recording video from the given file URL
    public func processRecording(
        url: URL,
        samplingFPS: Double = 5.0,
        keyFrameThreshold: CGFloat = 300.0,
        autoDetectFixedUI: Bool = true,
        blendWidth: Int = 40
    ) async {
        isCancelledManually = false
        isProcessing = true
        progress = 0.0
        statusMessage = "正在准备视频..."
        resultImage = nil
        error = nil
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                // Stage 1: Low-Memory Tracking Frame Extraction (0% ~ 40%)
                let (frames, trackingScale) = try await self.frameExtractor.extractTrackingFrames(
                    from: url,
                    samplingFPS: samplingFPS,
                    maxTrackingWidth: 360.0
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = currentProgress
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                guard frames.count >= 2 else {
                    throw RecordingError.insufficientFrames
                }
                
                // Stage 2: Scroll Displacement Detection (40% ~ 70%)
                let displacements = try await self.scrollDetector.detectDisplacements(
                    frames: frames
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = currentProgress
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                // Stage 3: Keyframe Decimation & Filtering (70% ~ 82%)
                let scaledThreshold = keyFrameThreshold / max(1.0, trackingScale)
                let config = KeyFrameSelector.Config(captureThreshold: scaledThreshold)
                let trackingKeyFrames = await self.keyFrameSelector.selectKeyFrames(
                    from: displacements,
                    config: config
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = min(0.82, currentProgress)
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                guard trackingKeyFrames.count >= 2 else {
                    throw RecordingError.insufficientKeyFrames
                }
                
                // Stage 3.5: On-demand Full-Resolution Keyframe Extraction (82% ~ 85%)
                let keyFrames = try await self.frameExtractor.extractFullResolutionKeyFrames(
                    from: url,
                    keyFrames: trackingKeyFrames,
                    coordinateScale: trackingScale
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = currentProgress
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                guard keyFrames.count >= 2 else {
                    throw RecordingError.insufficientKeyFrames
                }
                
                // Stage 4: Stationary UI Detection (Status Bar & Home Indicator)
                let fixedRegions: FixedUIDetector.FixedRegions
                if autoDetectFixedUI {
                    self.statusMessage = "正在分析固定导航栏与状态栏..."
                    fixedRegions = await self.fixedUIDetector.detectFixedRegions(in: keyFrames)
                } else {
                    fixedRegions = FixedUIDetector.FixedRegions.zero
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                // Stage 5: Precise Canvas Synthesis (85% ~ 100%)
                let result = try await self.stitchingEngine.stitchFromRecording(
                    keyFrames: keyFrames,
                    fixedRegions: fixedRegions,
                    blendWidth: blendWidth
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = currentProgress
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                self.resultImage = result
                self.progress = 1.0
                self.statusMessage = "长截图生成完毕！"
                
            } catch let recError as RecordingError {
                self.error = recError
                self.statusMessage = (recError == .processingCancelled || self.isCancelledManually || Task.isCancelled) ? "处理已取消" : "处理失败"
            } catch {
                if Task.isCancelled || self.isCancelledManually {
                    self.error = .processingCancelled
                    self.statusMessage = "处理已取消"
                } else {
                    self.error = .unknown(error.localizedDescription)
                    self.statusMessage = "处理失败"
                }
            }
            
            self.isProcessing = false
        }
        
        self.processingTask = task
        await task.value
    }
}
