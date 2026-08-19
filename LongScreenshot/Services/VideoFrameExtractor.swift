import Foundation
import AVFoundation
import CoreVideo
import CoreImage

/// Service responsible for high-performance frame extraction from screen recording video assets
public actor VideoFrameExtractor {
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    public init() {}
    
    /// Extracts sampled video frames from a local video file URL
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - samplingFPS: Target frames per second to extract (default: 5.0 fps)
    ///   - progressHandler: Progress callback (0.0 ... 0.40 range for frame extraction)
    /// - Returns: Array of FrameData
    public func extractFrames(
        from url: URL,
        samplingFPS: Double = 5.0,
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> [FrameData] {
        let asset = AVURLAsset(url: url)
        
        // 1. Load video track
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw RecordingError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0.1 else {
            throw RecordingError.insufficientFrames
        }
        
        await progressHandler(0.05, "正在分析视频（\(String(format: "%.1f", totalSeconds))秒）...")
        
        // 2. Setup AVAssetReader
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw RecordingError.readerConfigFailed
        }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false // High efficiency zero-copy where possible
        
        guard reader.canAdd(readerOutput) else {
            throw RecordingError.readerConfigFailed
        }
        reader.add(readerOutput)
        
        guard reader.startReading() else {
            throw RecordingError.readingFailed(reader.error?.localizedDescription ?? "无法开始读取")
        }
        
        // 3. Sample frames according to requested frame interval
        let effectiveFPS = max(1.0, min(samplingFPS, 30.0))
        let frameInterval = 1.0 / effectiveFPS
        var frames: [FrameData] = []
        var frameIndex = 0
        var lastSampledTime: Double = -frameInterval
        
        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let currentTime = CMTimeGetSeconds(presentationTime)
            
            // Check if frame satisfies sampling interval
            guard currentTime - lastSampledTime >= frameInterval else { continue }
            lastSampledTime = currentTime
            
            // Extract CGImage from pixel buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            
            frames.append(FrameData(image: cgImage, timestamp: presentationTime, index: frameIndex))
            frameIndex += 1
            
            let frameProgress = min(0.40, 0.05 + (currentTime / totalSeconds) * 0.35)
            await progressHandler(frameProgress, "正在提取视频帧（已提取 \(frameIndex) 帧）...")
        }
        
        if reader.status == .failed {
            throw RecordingError.readingFailed(reader.error?.localizedDescription ?? "读取中断")
        }
        
        guard !frames.isEmpty else {
            throw RecordingError.insufficientFrames
        }
        
        await progressHandler(0.40, "视频帧提取完成，共 \(frames.count) 帧")
        return frames
    }
}
