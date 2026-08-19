import SwiftUI
import PhotosUI
import AVKit

/// View for picking a screen recording video from photo library and launching the recording-to-long-screenshot flow
public struct RecordingPickerView: View {
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var videoDuration: String = ""
    @State private var videoThumbnail: UIImage?
    @State private var navigateToProcessing = false
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Apple Music Ambient Background
            MusicAmbientBackground()
            
            VStack(spacing: 16) {
                // Workflow step indicator
                HStack(spacing: 8) {
                    StepBadge(number: 1, text: "选录屏", isActive: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    StepBadge(number: 2, text: "提取", isActive: false)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    StepBadge(number: 3, text: "完成", isActive: false)
                }
                .padding(.top, 8)
                
                // Guidance title
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCREEN RECORDING")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    
                    Text("滚动录屏转长图")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("选择包含平稳滑动浏览的录屏视频，AI 自动提取关键帧")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Video artwork preview or guide card
                if let thumbnail = videoThumbnail {
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                }
                                .shadow(color: Color.purple.opacity(0.35), radius: 18, x: 0, y: 8)
                            
                            // Center play glyph
                            HStack {
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .glassEffect(.ultraThin, in: .circle)
                                    .shadow(radius: 10)
                                Spacer()
                            }
                            .frame(maxHeight: .infinity)
                            
                            // Duration pill
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                Text(videoDuration)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 20)
                } else if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("正在载入视频数据...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 20)
                } else {
                    // Apple Music Lyrics-card style tips container
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color(red: 0.98, green: 0.14, blue: 0.24))
                            Text("录屏生成小贴士")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            tipRow(number: "1", text: "打开 iOS 控制中心启动录屏，返回目标 App")
                            tipRow(number: "2", text: "匀速向下滑动浏览完整内容，结束后轻触停止")
                            tipRow(number: "3", text: "回到本 App 选择视频，AI 自动提取关键帧合成")
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Bottom floating pill dock
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .any(of: [.screenRecordings, .videos])
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle")
                            Text("选择录屏视频")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .glassEffect(.regular.interactive, in: .capsule)
                    
                    if videoURL != nil {
                        Button {
                            navigateToProcessing = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                Text("开始智能生成")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.14, blue: 0.24),
                                        Color(red: 0.66, green: 0.13, blue: 0.84)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.98, green: 0.14, blue: 0.24).opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("录屏转长图")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedVideoItem) { _, newItem in
            loadVideo(from: newItem)
        }
        .navigationDestination(isPresented: $navigateToProcessing) {
            if let url = videoURL {
                ProcessingView(mode: .recording(url))
            }
        }
        .animation(.spring(duration: 0.3), value: videoURL)
    }
    
    private func tipRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(red: 0.98, green: 0.14, blue: 0.24))
                .frame(width: 20, height: 20)
                .background(Color(red: 0.98, green: 0.14, blue: 0.24).opacity(0.15))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func loadVideo(from item: PhotosPickerItem?) {
        loadTask?.cancel()
        guard let item else { return }
        
        let previousURL = videoURL
        isLoading = true
        
        loadTask = Task {
            do {
                guard let movie = try await item.loadTransferable(type: Movie.self) else {
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.isLoading = false
                        }
                    }
                    return
                }
                
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: movie.url)
                    return
                }
                
                // Remove previous temporary file if it's different
                if let oldURL = previousURL, oldURL != movie.url {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                
                // Decode metadata & thumbnail off the main thread
                let (thumbnail, durationString) = await Task.detached(priority: .userInitiated) { () -> (UIImage?, String) in
                    let asset = AVURLAsset(url: movie.url)
                    let duration = try? await asset.load(.duration)
                    
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 400, height: 0)
                    
                    let thumbImage: UIImage?
                    if let cgImage = try? await generator.image(at: .zero).image {
                        thumbImage = UIImage(cgImage: cgImage)
                    } else {
                        thumbImage = nil
                    }
                    
                    let durStr: String
                    if let duration {
                        let seconds = CMTimeGetSeconds(duration)
                        durStr = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
                    } else {
                        durStr = ""
                    }
                    return (thumbImage, durStr)
                }.value
                
                let targetURL = movie.url
                
                await MainActor.run {
                    if !Task.isCancelled {
                        self.videoThumbnail = thumbnail
                        self.videoURL = targetURL
                        self.videoDuration = durationString
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.isLoading = false
                    }
                }
            }
        }
    }
}
