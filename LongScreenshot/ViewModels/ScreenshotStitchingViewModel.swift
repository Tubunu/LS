import SwiftUI

@MainActor
public final class ScreenshotStitchingViewModel: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "准备就绪"
    @Published public var resultImage: UIImage?
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String?
    
    private let stitchingEngine = ImageStitchingEngine()
    
    private var isCancelledManually: Bool = false
    private var processingTask: Task<Void, Never>?
    
    public init() {}
    
    /// Cancels active stitching task
    public func cancelProcessing() {
        processingTask?.cancel()
        isCancelledManually = true
        isProcessing = false
        statusMessage = "处理已取消"
    }
    
    /// Processes and stitches the given array of screenshots
    public func processScreenshots(
        _ images: [UIImage],
        config: CropConfig = .standard,
        blendWidth: Int = 40
    ) async {
        guard images.count >= 2 else {
            errorMessage = "至少需要两张截图才能进行拼接"
            return
        }
        
        isCancelledManually = false
        isProcessing = true
        progress = 0.0
        statusMessage = "正在初始化拼接引擎..."
        errorMessage = nil
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                let result = try await self.stitchingEngine.stitchScreenshots(
                    images,
                    config: config,
                    blendWidth: blendWidth
                ) { [weak self] currentProgress, message in
                    guard let self, !self.isCancelledManually, !Task.isCancelled else { return }
                    self.progress = currentProgress
                    self.statusMessage = message
                }
                
                if Task.isCancelled || self.isCancelledManually { throw RecordingError.processingCancelled }
                
                self.resultImage = result
                self.progress = 1.0
                self.statusMessage = "拼接完成！"
            } catch let recError as RecordingError {
                if recError == .processingCancelled || Task.isCancelled || self.isCancelledManually {
                    self.statusMessage = "处理已取消"
                } else {
                    self.errorMessage = recError.localizedDescription
                    self.statusMessage = "处理失败"
                }
            } catch {
                if Task.isCancelled || self.isCancelledManually {
                    self.statusMessage = "处理已取消"
                } else {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "处理失败"
                }
            }
            
            self.isProcessing = false
        }
        
        self.processingTask = task
        await task.value
    }
}
