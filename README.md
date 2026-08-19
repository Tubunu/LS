# iPhone 长截图 App (LongScreenshot)

[![Build & Test](https://github.com/your-username/LongScreenshot/actions/workflows/build.yml/badge.svg)](https://github.com/your-username/LongScreenshot/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20iOS%2026-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%2F%206.0-orange.svg)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20Liquid%20Glass-purple.svg)](https://developer.apple.com/xcode/swiftui/)

> 一款基于 **SwiftUI** 原生打造的 iPhone 高性能长截图 App，支持**多张截图无缝拼接**与**滚动录屏自动生成长图**双模式，全面适配 **iOS 26 Liquid Glass** 液态玻璃设计语言。

---

## ✨ 核心特性

- 📸 **截图拼接模式**：从相册多选连续截图，基于 **Accelerate vDSP** 矩阵级 SAD（Sum of Absolute Differences）算法与亚像素级梯度对齐，实现零接缝、无色差融合。
- 🎬 **录屏转长图模式**：从相册选择滚动录屏视频，基于 **AVAssetReader** 零拷贝逐帧解码 + **Apple Vision** `VNTranslationalImageRegistrationRequest` 帧间平移配准 + 智能关键帧筛选，自动剔除静止/抖动/回弹帧，一键合成高清长截图。
- 🔍 **智能固定 UI 识别**：多帧方差分析自动剔除顶部状态栏/灵动岛与底部 Home Indicator，并在合成完成后无损拼接回首尾固定区域。
- 💎 **Liquid Glass 液态玻璃 UI**：高通透材质、镜面高光描边、动态渐变光晕与灵动微交互，打造沉浸式视觉体验。
- 🚀 **完全无 Mac 环境支持**：基于 GitHub Actions / Codemagic + Fastlane 提供完备的云端打包与 TestFlight 一键分发配置。

---

## 🛠️ 技术栈

| 层次 | 选型与核心技术 |
|:---|:---|
| **UI 视图层** | SwiftUI + Liquid Glass API + MeshGradient |
| **架构模式** | MVVM (Model-View-ViewModel) + Swift Concurrency (`async/await`, `actor`, `@MainActor`) |
| **媒体选择** | PhotosUI (`PhotosPicker`, `Transferable`) |
| **视频解码** | AVFoundation (`AVURLAsset`, `AVAssetReader`, `kCVPixelFormatType_32BGRA`) |
| **位移配准** | Vision (`VNSequenceRequestHandler`, `VNTranslationalImageRegistrationRequest`) |
| **图像计算** | Accelerate (`vDSP_vsub`, `vDSP_vabs`, `vDSP_sve`, `vDSP_meanv`, `vDSP_dotpr`) |
| **图像合成** | Core Graphics (`UIGraphicsImageRenderer`, `CGContext`, `CIImage`, `CGImage`) |
| **CI / CD** | GitHub Actions (macOS Runner) + Fastlane + Codemagic |

---

## 📂 项目结构

```
LongScreenshot/
├── LongScreenshot.xcodeproj/        # Xcode 工程文件
│   └── project.pbxproj
├── LongScreenshot/
│   ├── App/
│   │   ├── LongScreenshotApp.swift  # App 入口
│   │   └── ContentView.swift        # 根视图
│   ├── Views/
│   │   ├── HomeView.swift           # 双模式选择主页
│   │   ├── ScreenshotPickerView.swift # 截图挑选与排序
│   │   ├── RecordingPickerView.swift  # 录屏挑选与引导
│   │   ├── ProcessingView.swift     # 统一圆形进度展示
│   │   ├── PreviewView.swift        # 长图缩放、保存与分享
│   │   ├── SettingsView.swift       # 参数调优与设置
│   │   └── Components/
│   │       ├── ModeCard.swift       # 模式选择卡片
│   │       ├── StepBadge.swift      # 步骤指示徽章
│   │       ├── ImageThumbnail.swift # 缩略图列表单元
│   │       ├── ProgressRing.swift   # 渐变圆环进度条
│   │       └── ShareSheet.swift     # 系统原生分享页
│   ├── ViewModels/
│   │   ├── ScreenshotViewModel.swift
│   │   ├── ScreenshotStitchingViewModel.swift
│   │   ├── RecordingViewModel.swift
│   │   └── PreviewViewModel.swift
│   ├── Services/
│   │   ├── ImageStitchingEngine.swift # 核心多模式拼接引擎
│   │   ├── OverlapDetector.swift      # vDSP 加速重叠区域匹配
│   │   ├── ImageBlender.swift         # 线性渐变交叉混合渲染
│   │   ├── ImagePreprocessor.swift    # 状态栏/安全区预裁剪
│   │   ├── VideoFrameExtractor.swift  # 高性能视频帧提取
│   │   ├── ScrollDetector.swift       # Vision 平移位移分析
│   │   ├── KeyFrameSelector.swift     # 关键帧智能抽取与降采样
│   │   ├── FixedUIDetector.swift      # 固定 UI 元素方差检测
│   │   └── ImageExporter.swift        # 相册写入与临时文件导出
│   ├── Models/
│   │   ├── ProcessingMode.swift
│   │   ├── Movie.swift
│   │   ├── CropConfig.swift
│   │   ├── OverlapInfo.swift
│   │   ├── KeyFrame.swift
│   │   ├── FrameDisplacement.swift
│   │   ├── RecordingError.swift
│   │   ├── StitchingResult.swift
│   │   └── AppSettings.swift
│   ├── Extensions/
│   │   ├── CGImage+Crop.swift
│   │   ├── UIImage+Resize.swift
│   │   └── View+GlassStyle.swift
│   ├── Utilities/
│   │   ├── PixelBuffer.swift
│   │   └── Logger.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── LongScreenshotTests/             # 单元测试与算法基准套件
│   ├── OverlapDetectorTests.swift
│   ├── ImageBlenderTests.swift
│   ├── ScrollDetectorTests.swift
│   ├── KeyFrameSelectorTests.swift
│   └── StitchingPipelineTests.swift
├── .github/workflows/
│   ├── build.yml                    # CI 编译与自动化测试
│   └── release.yml                  # TestFlight 云端自动发版
├── fastlane/
│   ├── Fastfile
│   ├── Appfile
│   └── Matchfile
├── Package.swift                    # Swift Package Manager 支持
├── codemagic.yaml
└── Gemfile
```

---

## 🚀 云端打包与发布（无 Mac 环境）

### 1. 配置 GitHub Actions Secrets

在 GitHub 仓库中进入 **Settings -> Secrets and variables -> Actions**，添加以下密钥：

- `APPSTORE_KEY_ID`: App Store Connect API Key ID
- `APPSTORE_ISSUER_ID`: App Store Connect Issuer ID
- `APPSTORE_PRIVATE_KEY`: App Store Connect API Key 私钥内容 (`.p8`)
- `MATCH_PASSWORD`: Fastlane Match 证书加密密码
- `MATCH_GIT_URL`: 存放证书的私有 Git 仓库地址

### 2. 触发编译与测试

提交代码或发起 Pull Request 至 `main` 分支，GitHub Actions 将自动在 macOS 虚拟环境中拉取代码、编译并执行单元测试。

### 3. 发布到 TestFlight

打 Tag 并推送即可触发发布流：

```bash
git tag v2.0.0
git push origin v2.0.0
```

---

## 📄 开源许可证

本项目基于 [MIT 许可证](LICENSE) 发布。
