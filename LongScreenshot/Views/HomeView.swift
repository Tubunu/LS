import SwiftUI

/// Main home screen allowing users to choose between Screenshot Stitching and Screen Recording modes
public struct HomeView: View {
    @State private var selectedMode: HomeAppMode?
    @AppStorage(AppSettings.appThemeKey) private var appThemeRaw: String = AppSettings.defaultTheme.rawValue
    
    public enum HomeAppMode: String, Identifiable, Hashable {
        case screenshot = "screenshot"
        case recording = "recording"
        
        public var id: String { rawValue }
    }
    
    public init() {}
    
    private var currentTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Apple Music Dynamic Ambient Fluid Aurora Background
                MusicAmbientBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header area with Apple Music editorial typography & Settings avatar
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LONG SCREENSHOT PRO")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(.secondary)
                                
                                Text("长截图")
                                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                            
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .glassEffect(.regular.interactive, in: .circle)
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        
                        // Dual hero mode cards
                        VStack(spacing: 16) {
                            // Mode 1: Screenshot Stitching
                            NavigationLink(value: HomeAppMode.screenshot) {
                                ModeCard(
                                    modeNumber: "MODE 01",
                                    icon: "photo.on.rectangle.angled",
                                    title: "截图无痕拼接",
                                    subtitle: "从相册挑选多张重叠截图，Accelerate 算法毫秒级定位重叠接缝并无缝融合。",
                                    actionText: "开始拼接",
                                    gradientColors: [
                                        Color(red: 0.35, green: 0.34, blue: 0.84),
                                        Color(red: 0.66, green: 0.13, blue: 0.84)
                                    ]
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Mode 2: Screen Recording to Long Image
                            NavigationLink(value: HomeAppMode.recording) {
                                ModeCard(
                                    modeNumber: "MODE 02",
                                    icon: "record.circle",
                                    title: "录屏智能转长图",
                                    subtitle: "选择滚动录屏视频，Vision 帧间位移检测，自动剔除静止/抖动帧并直接生成长图。",
                                    actionText: "选择录屏",
                                    gradientColors: [
                                        Color(red: 0.98, green: 0.14, blue: 0.24),
                                        Color(red: 0.66, green: 0.13, blue: 0.84)
                                    ]
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        
                        // Apple Music Feature Shelf: "精选小贴士"
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("精选小贴士")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    shelfItem(
                                        icon: "lightbulb.fill",
                                        iconColor: .blue,
                                        title: "30% 重叠准则",
                                        subtitle: "相邻截图保留适度重叠"
                                    )
                                    
                                    shelfItem(
                                        icon: "bolt.fill",
                                        iconColor: .red,
                                        title: "匀速滑动录屏",
                                        subtitle: "录屏时平稳滑动效果最佳"
                                    )
                                    
                                    shelfItem(
                                        icon: "sparkles",
                                        iconColor: .cyan,
                                        title: "状态栏自动保护",
                                        subtitle: "智能剔除并还原灵动岛"
                                    )
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationDestination(for: HomeAppMode.self) { mode in
                switch mode {
                case .screenshot:
                    ScreenshotPickerView()
                case .recording:
                    RecordingPickerView()
                }
            }
            .preferredColorScheme(currentTheme.colorScheme)
        }
    }
    
    private func shelfItem(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.18))
                
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 145, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
