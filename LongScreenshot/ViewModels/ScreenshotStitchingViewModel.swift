import SwiftUI

@MainActor
public final class ScreenshotStitchingViewModel: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "准备就绪"
    @Published public var resultImage: UIImage?
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String?
    
    private let stitchingEngine = ImageStitchingEngine()
    
    public init() {}
    
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
        
        isProcessing = true
        progress = 0.0
        statusMessage = "正在初始化拼接引擎..."
        errorMessage = nil
        
        do {
            let result = try await stitchingEngine.stitchScreenshots(
                images,
                config: config,
                blendWidth: blendWidth
            ) { [weak self] currentProgress, message in
                guard let self else { return }
                self.progress = currentProgress
                self.statusMessage = message
            }
            
            self.resultImage = result
            self.progress = 1.0
            self.statusMessage = "拼接完成！"
        } catch {
            self.errorMessage = error.localizedDescription
            self.statusMessage = "处理失败"
        }
        
        self.isProcessing = false
    }
}
