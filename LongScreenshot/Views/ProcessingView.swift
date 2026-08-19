import SwiftUI

/// Unified processing screen that visualizes real-time progress for both screenshot and recording stitching
public struct ProcessingView: View {
    public let mode: ProcessingMode
    public var onComplete: ((UIImage) -> Void)?
    public var onCancel: (() -> Void)?
    
    @StateObject private var screenshotVM = ScreenshotStitchingViewModel()
    @StateObject private var recordingVM = RecordingViewModel()
    @Environment(\.dismiss) private var dismiss
    
    // User configuration bindings
    @AppStorage(AppSettings.autoDetectFixedUIKey) private var autoDetectFixedUI: Bool = AppSettings.defaultAutoDetectFixedUI
    @AppStorage(AppSettings.blendingWidthKey) private var blendingWidth: Double = AppSettings.defaultBlendingWidth
    @AppStorage(AppSettings.recordingSamplingFPSKey) private var samplingFPS: Double = AppSettings.defaultRecordingSamplingFPS
    @AppStorage(AppSettings.keyFrameThresholdKey) private var keyFrameThreshold: Double = AppSettings.defaultKeyFrameThreshold
    
    public init(
        mode: ProcessingMode,
        onComplete: ((UIImage) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onComplete = onComplete
        self.onCancel = onCancel
    }
    
    private var currentProgress: Double {
        switch mode {
        case .screenshot: return screenshotVM.progress
        case .recording: return recordingVM.progress
        }
    }
    
    private var currentStatusMessage: String {
        switch mode {
        case .screenshot: return screenshotVM.statusMessage
        case .recording: return recordingVM.statusMessage
        }
    }
    
    private var finalResultImage: UIImage? {
        switch mode {
        case .screenshot: return screenshotVM.resultImage
        case .recording: return recordingVM.resultImage
        }
    }
    
    private var currentErrorMessage: String? {
        switch mode {
        case .screenshot: return screenshotVM.errorMessage
        case .recording: return recordingVM.error?.localizedDescription
        }
    }
    
    private var isCurrentlyProcessing: Bool {
        switch mode {
        case .screenshot: return screenshotVM.isProcessing
        case .recording: return recordingVM.isProcessing
        }
    }
    
    public var body: some View {
        ZStack {
            // Apple Music Ambient Background
            MusicAmbientBackground()
            
            VStack(spacing: 36) {
                Spacer()
                
                // Circular animated spatial progress ring
                ProgressRing(
                    progress: currentProgress,
                    iconName: mode.systemIcon,
                    tintColor: mode.themeColor
                )
                
                // Status description
                VStack(spacing: 12) {
                    Text(currentStatusMessage)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    
                    // Mode identification tag
                    Text(mode.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(mode.themeColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(mode.themeColor.opacity(0.15))
                        .clipShape(Capsule())
                    
                    // Cancel action button when processing
                    if isCurrentlyProcessing && currentErrorMessage == nil {
                        Button {
                            cancelCurrentProcessing()
                            if let onCancel {
                                onCancel()
                            } else {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                Text("取消处理")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .padding(.top, 6)
                    }
                    
                    // Finished state fallback
                    if !isCurrentlyProcessing && finalResultImage != nil {
                        Button {
                            if let onCancel {
                                onCancel()
                            } else {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "house.fill")
                                Text("返回主页")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                        }
                        .glassEffect(.regular.interactive, in: .capsule)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 40)
                
                // Error card if processing failed
                if let errorMessage = currentErrorMessage {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("处理未成功")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            if let onCancel {
                                onCancel()
                            } else {
                                dismiss()
                            }
                        } label: {
                            Text("返回重新选择")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .padding(.horizontal, 30)
                }
                
                Spacer()
            }
        }
        .navigationTitle("自动处理")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            await startProcessing()
        }
        .onChange(of: finalResultImage) { _, image in
            guard let image else { return }
            ImageExporter.cleanupTemporaryFiles()
            if let onComplete {
                onComplete(image)
            }
        }
    }
    
    private func cancelCurrentProcessing() {
        switch mode {
        case .screenshot:
            screenshotVM.cancelProcessing()
        case .recording:
            recordingVM.cancelProcessing()
        }
    }
    
    private func startProcessing() async {
        switch mode {
        case .screenshot(let images):
            await screenshotVM.processScreenshots(
                images,
                config: autoDetectFixedUI ? .standard : .zero,
                blendWidth: Int(blendingWidth)
            )
        case .recording(let url):
            await recordingVM.processRecording(
                url: url,
                samplingFPS: samplingFPS,
                keyFrameThreshold: CGFloat(keyFrameThreshold),
                autoDetectFixedUI: autoDetectFixedUI,
                blendWidth: Int(blendingWidth)
            )
        }
    }
}
