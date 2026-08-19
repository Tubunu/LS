import Foundation

/// Errors that can occur during video recording frame extraction, tracking, or stitching
public enum RecordingError: LocalizedError, Equatable, Sendable {
    case noVideoTrack
    case readerConfigFailed
    case readingFailed(String)
    case insufficientFrames
    case insufficientKeyFrames
    case processingCancelled
    case stitchingFailed(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "该文件不包含有效的视频轨道"
        case .readerConfigFailed:
            return "视频解码配置失败，无法读取视频帧"
        case .readingFailed(let message):
            return "视频读取失败：\(message)"
        case .insufficientFrames:
            return "有效图像或视频帧不足，至少需要两张截图或包含平稳滚动的录屏"
        case .insufficientKeyFrames:
            return "未检测到足够的滚动内容。请确保录屏中包含平稳的页面滚动操作。"
        case .processingCancelled:
            return "处理已取消"
        case .stitchingFailed(let message):
            return "图像拼接失败：\(message)"
        case .unknown(let message):
            return "发生未知错误：\(message)"
        }
    }
}
