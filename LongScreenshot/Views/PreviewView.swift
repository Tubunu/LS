import SwiftUI

/// View for inspecting, zooming, saving, and sharing the generated long screenshot
public struct PreviewView: View {
    @StateObject private var viewModel: PreviewViewModel
    @AppStorage(AppSettings.outputQualityKey) private var outputQuality: Double = AppSettings.defaultOutputQuality
    @Environment(\.dismiss) private var dismiss
    
    public var onDismissToRoot: (() -> Void)?
    
    @State private var baseScale: CGFloat = 1.0
    @State private var pinchScale: CGFloat = 1.0
    
    public init(resultImage: UIImage, onDismissToRoot: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PreviewViewModel(resultImage: resultImage))
        self.onDismissToRoot = onDismissToRoot
    }
    
    private var currentZoomScale: CGFloat {
        max(1.0, min(baseScale * pinchScale, 5.0))
    }
    
    public var body: some View {
        ZStack {
            // Apple Music Ambient Background
            MusicAmbientBackground()
            
            // Scrollable & zoomable long image viewer
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Image(uiImage: viewModel.resultImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(currentZoomScale)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                pinchScale = value
                            }
                            .onEnded { value in
                                withAnimation(.spring(duration: 0.25)) {
                                    baseScale = max(1.0, min(baseScale * value, 5.0))
                                    pinchScale = 1.0
                                }
                            }
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 70)
            }
            
            // Top dimensions info badge
            VStack {
                HStack {
                    Spacer()
                    
                    let width = viewModel.resultImage.cgImage?.width ?? Int(viewModel.resultImage.size.width * viewModel.resultImage.scale)
                    let height = viewModel.resultImage.cgImage?.height ?? Int(viewModel.resultImage.size.height * viewModel.resultImage.scale)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "aspectratio")
                            .font(.caption2)
                        Text("\(width) × \(height) px")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Bottom floating action dock (Apple Music Now Playing dock style)
                HStack(spacing: 14) {
                    // Back to Home
                    Button {
                        if let onDismissToRoot {
                            onDismissToRoot()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive, in: .circle)
                    
                    // Save to Album
                    Button {
                        viewModel.saveToPhotos(quality: outputQuality)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.isSaved ? "checkmark" : (viewModel.isSaving ? "hourglass" : "square.and.arrow.down.fill"))
                            Text(viewModel.isSaved ? "已保存至相册" : (viewModel.isSaving ? "正在保存..." : "保存长截图"))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            viewModel.isSaved ?
                                AnyShapeStyle(Color.green) :
                                AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.14, blue: 0.24),
                                            Color(red: 0.66, green: 0.13, blue: 0.84)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.pink.opacity(0.35), radius: 10, x: 0, y: 4)
                    }
                    .disabled(viewModel.isSaved || viewModel.isSaving)
                    
                    // Share Sheet
                    Button {
                        viewModel.prepareSharing(quality: outputQuality)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive, in: .circle)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let shareURL = viewModel.shareableURL {
                ShareSheet(items: [shareURL])
            } else {
                ShareSheet(items: [viewModel.resultImage])
            }
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }
}
