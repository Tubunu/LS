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
    
    public init() {}
    
    /// Processes a screen recording video from the given file URL
    public func processRecording(
        url: URL,
        samplingFPS: Double = 5.0,
        keyFrameThreshold: CGFloat = 300.0,
        autoDetectFixedUI: Bool = true
    ) async {
        isProcessing = true
        progress = 0.0
        statusMessage = "正在准备视频..."
        resultImage = nil
        error = nil
        
        do {
            // Stage 1: Video Frame Extraction (0% ~ 40%)
            let frames = try await frameExtractor.extractFrames(
                from: url,
                samplingFPS: samplingFPS
            ) { [weak self] currentProgress, message in
                Task { @MainActor in
                    self?.progress = currentProgress
                    self?.statusMessage = message
                }
            }
            
            guard frames.count >= 2 else {
                throw RecordingError.insufficientFrames
            }
            
            // Stage 2: Scroll Displacement Detection (40% ~ 70%)
            let displacements = try await scrollDetector.detectDisplacements(
                frames: frames
            ) { [weak self] currentProgress, message in
                Task { @MainActor in
                    self?.progress = currentProgress
                    self?.statusMessage = message
                }
            }
            
            // Stage 3: Keyframe Decimation & Filtering (70% ~ 85%)
            let config = KeyFrameSelector.Config(captureThreshold: keyFrameThreshold)
            let keyFrames = await keyFrameSelector.selectKeyFrames(
                from: displacements,
                config: config
            ) { [weak self] currentProgress, message in
                Task { @MainActor in
                    self?.progress = currentProgress
                    self?.statusMessage = message
                }
            }
            
            guard keyFrames.count >= 2 else {
                throw RecordingError.insufficientKeyFrames
            }
            
            // Stage 4: Stationary UI Detection (Status Bar & Home Indicator)
            let fixedRegions: FixedUIDetector.FixedRegions
            if autoDetectFixedUI {
                self.statusMessage = "正在分析固定导航栏与状态栏..."
                fixedRegions = await fixedUIDetector.detectFixedRegions(in: keyFrames)
            } else {
                fixedRegions = FixedUIDetector.FixedRegions.zero
            }
            
            // Stage 5: Precise Canvas Synthesis (85% ~ 100%)
            let result = try await stitchingEngine.stitchFromRecording(
                keyFrames: keyFrames,
                fixedRegions: fixedRegions
            ) { [weak self] currentProgress, message in
                Task { @MainActor in
                    self?.progress = currentProgress
                    self?.statusMessage = message
                }
            }
            
            self.resultImage = result
            self.progress = 1.0
            self.statusMessage = "长截图生成完毕！"
            
        } catch let recError as RecordingError {
            self.error = recError
            self.statusMessage = "处理失败"
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.statusMessage = "处理失败"
        }
        
        self.isProcessing = false
    }
}
