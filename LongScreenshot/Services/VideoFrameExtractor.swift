import Foundation
import AVFoundation
import CoreVideo
import CoreImage

/// Service responsible for high-performance frame extraction from screen recording video assets
public actor VideoFrameExtractor {
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    public init() {}
    
    /// Extracts sampled video frames with optional downsampling for low-memory motion tracking
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - samplingFPS: Target frames per second to extract (default: 5.0 fps)
    ///   - maxTrackingWidth: Maximum pixel width for motion tracking (0 = unconstrained, default: 360px)
    ///   - progressHandler: Progress callback (0.0 ... 0.40 range for frame extraction)
    /// - Returns: Tuple of extracted FrameData and coordinateScale factor to convert to full resolution
    public func extractTrackingFrames(
        from url: URL,
        samplingFPS: Double = 5.0,
        maxTrackingWidth: CGFloat = 360.0,
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> (frames: [FrameData], trackingScale: CGFloat) {
        let asset = AVURLAsset(url: url)
        
        // 1. Load video track
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw RecordingError.noVideoTrack
        }
        
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        guard let naturalSize = try? await videoTrack.load(.naturalSize),
              naturalSize.width > 0, naturalSize.height > 0 else {
            throw RecordingError.readerConfigFailed
        }
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0.1 else {
            throw RecordingError.insufficientFrames
        }
        
        await progressHandler(0.05, "正在分析视频（\(String(format: "%.1f", totalSeconds))秒）...")
        
        // Determine coordinate scale
        let originalWidth = naturalSize.width
        let trackingScale: CGFloat
        if maxTrackingWidth > 0 && originalWidth > maxTrackingWidth {
            trackingScale = originalWidth / maxTrackingWidth
        } else {
            trackingScale = 1.0
        }
        
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
            if Task.isCancelled {
                reader.cancelReading()
                throw RecordingError.processingCancelled
            }
            
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let currentTime = CMTimeGetSeconds(presentationTime)
            
            // Check if frame satisfies sampling interval
            guard currentTime - lastSampledTime >= frameInterval else { continue }
            lastSampledTime = currentTime
            
            var extractedCGImage: CGImage?
            autoreleasepool {
                // Extract downsampled CGImage from pixel buffer
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    if !transform.isIdentity {
                        ciImage = ciImage.transformed(by: transform)
                    }
                    if maxTrackingWidth > 0 && ciImage.extent.width > maxTrackingWidth {
                        let scale = maxTrackingWidth / ciImage.extent.width
                        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    }
                    extractedCGImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
                }
            }
            
            guard let cgImage = extractedCGImage else { continue }
            
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
        return (frames: frames, trackingScale: trackingScale)
    }
    
    /// Extracts full-resolution keyframes on demand only for the selected timestamps
    public func extractFullResolutionKeyFrames(
        from url: URL,
        keyFrames: [KeyFrame],
        coordinateScale: CGFloat = 1.0,
        progressHandler: (@Sendable @MainActor (Double, String) -> Void)? = nil
    ) async throws -> [KeyFrame] {
        guard !keyFrames.isEmpty else { return [] }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        var fullResKeyFrames: [KeyFrame] = []
        let count = keyFrames.count
        
        for (idx, kf) in keyFrames.enumerated() {
            if Task.isCancelled { throw RecordingError.processingCancelled }
            
            let highResImage: CGImage
            if let imageResult = try? await generator.image(at: kf.timestamp).image {
                highResImage = imageResult
            } else {
                highResImage = kf.image
            }
            
            let realCumulativeOffset = kf.cumulativeOffset * coordinateScale
            fullResKeyFrames.append(KeyFrame(
                image: highResImage,
                cumulativeOffset: realCumulativeOffset,
                timestamp: kf.timestamp,
                index: idx
            ))
            
            if let progressHandler {
                let progress = 0.82 + (Double(idx + 1) / Double(count)) * 0.03
                await progressHandler(progress, "正在提取高清原图关键帧 (\(idx + 1)/\(count))...")
            }
        }
        
        return fullResKeyFrames
    }
    
    /// Backward-compatible extraction method
    public func extractFrames(
        from url: URL,
        samplingFPS: Double = 5.0,
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> [FrameData] {
        let result = try await extractTrackingFrames(
            from: url,
            samplingFPS: samplingFPS,
            maxTrackingWidth: 0,
            progressHandler: progressHandler
        )
        return result.frames
    }
}
