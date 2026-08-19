import SwiftUI

/// Application settings screen with theme switching, stitch quality tuning, and sampling parameters
public struct SettingsView: View {
    @AppStorage(AppSettings.appThemeKey) private var appThemeRaw: String = AppSettings.defaultTheme.rawValue
    @AppStorage(AppSettings.outputQualityKey) private var outputQuality: Double = AppSettings.defaultOutputQuality
    @AppStorage(AppSettings.autoDetectFixedUIKey) private var autoDetectFixedUI: Bool = AppSettings.defaultAutoDetectFixedUI
    @AppStorage(AppSettings.blendingWidthKey) private var blendingWidth: Double = AppSettings.defaultBlendingWidth
    @AppStorage(AppSettings.recordingSamplingFPSKey) private var samplingFPS: Double = AppSettings.defaultRecordingSamplingFPS
    @AppStorage(AppSettings.keyFrameThresholdKey) private var keyFrameThreshold: Double = AppSettings.defaultKeyFrameThreshold
    
    public init() {}
    
    private var selectedThemeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: appThemeRaw) ?? .system },
            set: { appThemeRaw = $0.rawValue }
        )
    }
    
    public var body: some View {
        Form {
            // Theme Mode Section
            Section("色彩主题") {
                Picker("外观模式", selection: selectedThemeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Output Quality Section
            Section("图像质量") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("输出分辨率比例", systemImage: "photo.badge.checkmark")
                        Spacer()
                        Text("\(Int(outputQuality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $outputQuality, in: 0.5...1.0, step: 0.1)
                }
            }
            
            // Screenshot Stitching Parameters
            Section("截图拼接设置") {
                Toggle(isOn: $autoDetectFixedUI) {
                    Label("自动剔除固定状态栏与导航栏", systemImage: "rectangle.dashed")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("接缝渐变过渡宽度", systemImage: "arrow.left.and.right")
                        Spacer()
                        Text("\(Int(blendingWidth)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $blendingWidth, in: 10...100, step: 5)
                }
            }
            
            // Screen Recording Parameters
            Section("录屏转长图设置") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("视频采样帧率", systemImage: "film")
                        Spacer()
                        Text("\(Int(samplingFPS)) fps")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $samplingFPS, in: 2...10, step: 1)
                    Text("帧率越高位移计算越平滑，但处理内存和耗时会相应增加。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("关键帧采样位移间距", systemImage: "ruler")
                        Spacer()
                        Text("\(Int(keyFrameThreshold)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $keyFrameThreshold, in: 100...600, step: 50)
                    Text("控制每累积滑动多少像素时捕获一次新的关键帧。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // App Information Section
            Section("关于应用") {
                HStack {
                    Label("应用版本", systemImage: "info.circle")
                    Spacer()
                    Text("2.0.0 (Build 2026.1)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("设计风格", systemImage: "paintbrush.fill")
                    Spacer()
                    Text("Apple Music + Liquid Glass")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("偏好设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
