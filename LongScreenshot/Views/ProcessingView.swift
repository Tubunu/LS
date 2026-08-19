import SwiftUI

/// Unified processing screen that visualizes real-time progress for both screenshot and recording stitching
public struct ProcessingView: View {
    public let mode: ProcessingMode
    
    @StateObject private var screenshotVM = ScreenshotStitchingViewModel()
    @StateObject private var recordingVM = RecordingViewModel()
    @State private var navigateToPreview = false
    @Environment(\.dismiss) private var dismiss
    
    // User configuration bindings
    @AppStorage(AppSettings.autoDetectFixedUIKey) private var autoDetectFixedUI: Bool = AppSettings.defaultAutoDetectFixedUI
    @AppStorage(AppSettings.blendingWidthKey) private var blendingWidth: Double = AppSettings.defaultBlendingWidth
    @AppStorage(AppSettings.recordingSamplingFPSKey) private var samplingFPS: Double = AppSettings.defaultRecordingSamplingFPS
    @AppStorage(AppSettings.keyFrameThresholdKey) private var keyFrameThreshold: Double = AppSettings.defaultKeyFrameThreshold
    
    public init(mode: ProcessingMode) {
        self.mode = mode
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
                            dismiss()
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
            startProcessing()
        }
        .onChange(of: finalResultImage) { _, newImage in
            if newImage != nil {
                navigateToPreview = true
            }
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            if let image = finalResultImage {
                PreviewView(resultImage: image)
            }
        }
    }
    
    private func startProcessing() {
        Task {
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
                    autoDetectFixedUI: autoDetectFixedUI
                )
            }
        }
    }
}
