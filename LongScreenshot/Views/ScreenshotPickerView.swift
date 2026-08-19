import SwiftUI
import PhotosUI

/// View for selecting multiple screenshots from photo album and organizing them for stitching
public struct ScreenshotPickerView: View {
    @StateObject private var viewModel = ScreenshotViewModel()
    @State private var isProcessing = false
    @State private var processedResultImage: UIImage? = nil
    @State private var navigateToPreview = false
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Apple Music Ambient Background
            MusicAmbientBackground()
            
            VStack(spacing: 16) {
                // Workflow step indicator
                HStack(spacing: 8) {
                    StepBadge(number: 1, text: "选图", isActive: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    StepBadge(number: 2, text: "拼接", isActive: false)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    StepBadge(number: 3, text: "完成", isActive: false)
                }
                .padding(.top, 8)
                
                // Guidance title
                VStack(alignment: .leading, spacing: 2) {
                    Text("SELECTION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    
                    Text("挑选待拼接截图")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("已按时间顺序排列，相邻截图建议保留 30% 重叠")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Selected images preview strip (Apple Music Album Card Shelf)
                if !viewModel.selectedImages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已选 \(viewModel.selectedImages.count) 张")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Button("清空") {
                                withAnimation {
                                    viewModel.clearAll()
                                }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.98, green: 0.14, blue: 0.24))
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { index, thumb in
                                    ImageThumbnail(image: thumb, index: index) {
                                        withAnimation {
                                            viewModel.removeImage(at: index)
                                        }
                                    }
                                }
                                
                                // Add more button card
                                PhotosPicker(
                                    selection: $viewModel.photoItems,
                                    maxSelectionCount: 30,
                                    matching: .screenshots
                                ) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(Color(red: 0.98, green: 0.14, blue: 0.24))
                                        
                                        Text("添加更多")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 85, height: 145)
                                    .glassEffect(.thin, in: .rect(cornerRadius: 14))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                        }
                    }
                } else {
                    // Empty placeholder card
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 76, height: 76)
                            
                            Image(systemName: "photo.stack")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Color.blue)
                        }
                        
                        VStack(spacing: 4) {
                            Text("尚未选择任何截图")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("点击下方按钮从相册挑选多张重叠截图")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 20)
                }
                
                // Info callout card
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.blue)
                    
                    Text("系统将自动去除多余的状态栏与底部条，并利用 Accelerate vDSP 进行亚像素对齐。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.thin, in: .rect(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Bottom floating pill dock
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $viewModel.photoItems,
                        maxSelectionCount: 30,
                        matching: .screenshots
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("从相册选择")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .glassEffect(.regular.interactive, in: .capsule)
                    
                    if viewModel.selectedImages.count >= 2 {
                        Button {
                            isProcessing = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("开始拼接 (\(viewModel.selectedImages.count))")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.35, green: 0.34, blue: 0.84),
                                        Color(red: 0.66, green: 0.13, blue: 0.84)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.purple.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("截图拼接")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isProcessing) {
            ProcessingView(mode: .screenshot(viewModel.selectedImages), onComplete: { result in
                processedResultImage = result
                isProcessing = false
                navigateToPreview = true
            }, onCancel: {
                isProcessing = false
            })
        }
        .navigationDestination(isPresented: $navigateToPreview) {
            if let processedResultImage {
                PreviewView(resultImage: processedResultImage)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.selectedImages.count)
    }
}
