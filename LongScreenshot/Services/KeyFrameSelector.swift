import Foundation
import CoreGraphics
import CoreMedia

/// Service responsible for intelligently selecting keyframes from video displacement streams
public actor KeyFrameSelector {
    
    public struct Config: Sendable {
        /// Distance in pixels before triggering a keyframe capture (typically 30%~50% of screen height)
        public var captureThreshold: CGFloat
        /// Minimum displacement speed to consider active scroll
        public var minScrollSpeed: CGFloat
        /// Maximum displacement speed to prevent motion-blurred frames
        public var maxScrollSpeed: CGFloat
        
        public init(
            captureThreshold: CGFloat = 300.0,
            minScrollSpeed: CGFloat = 2.0,
            maxScrollSpeed: CGFloat = 300.0
        ) {
            self.captureThreshold = captureThreshold
            self.minScrollSpeed = minScrollSpeed
            self.maxScrollSpeed = maxScrollSpeed
        }
    }
    
    public init() {}
    
    /// Selects keyframes based on cumulative displacement
    /// - Parameters:
    ///   - displacements: Stream of frame displacements from ScrollDetector
    ///   - config: Configuration settings
    ///   - progressHandler: Progress callback (0.70 ... 0.85 range)
    /// - Returns: Array of KeyFrame
    public func selectKeyFrames(
        from displacements: [FrameDisplacement],
        config: Config = Config(),
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async -> [KeyFrame] {
        guard !displacements.isEmpty else { return [] }
        
        var keyFrames: [KeyFrame] = []
        var cumulativeOffset: CGFloat = 0
        var sinceLastCapture: CGFloat = 0
        var dirAccumulator: CGFloat = 0
        var primaryScrollDirection: CGFloat = 0
        
        // The first frame is always the starting keyframe
        keyFrames.append(KeyFrame(
            image: displacements[0].frame.image,
            cumulativeOffset: 0,
            timestamp: displacements[0].frame.timestamp,
            index: 0
        ))
        
        let total = displacements.count
        
        for (index, disp) in displacements.enumerated() {
            if Task.isCancelled { return [] }
            guard index > 0 else { continue }
            
            let absDy = abs(disp.dy)
            
            // 1. Filter out static or non-scrolling frames
            if !disp.isScrolling || absDy < config.minScrollSpeed {
                continue
            }
            
            // 2. Filter out extreme sudden jumps (probable blur)
            if absDy > config.maxScrollSpeed {
                continue
            }
            
            // 3. Establish & verify scroll direction consistency (downward vs upward)
            let currentDirection: CGFloat = disp.dy > 0 ? 1 : -1
            if primaryScrollDirection == 0 {
                dirAccumulator += disp.dy
                if abs(dirAccumulator) >= 15.0 {
                    primaryScrollDirection = dirAccumulator > 0 ? 1 : -1
                } else {
                    // Suppress initial minor jitter until meaningful movement is established
                    continue
                }
            } else if currentDirection != primaryScrollDirection {
                // Ignore bouncing or reversed scroll jitter
                continue
            }
            
            // 4. Accumulate displacement
            cumulativeOffset += absDy
            sinceLastCapture += absDy
            
            // 5. Trigger keyframe capture if threshold reached
            if sinceLastCapture >= config.captureThreshold {
                keyFrames.append(KeyFrame(
                    image: disp.frame.image,
                    cumulativeOffset: cumulativeOffset,
                    timestamp: disp.frame.timestamp,
                    index: keyFrames.count
                ))
                sinceLastCapture = 0
                
                let progress = 0.70 + (Double(index) / Double(total)) * 0.15
                await progressHandler(progress, "已筛选 \(keyFrames.count) 个关键帧...")
            }
        }
        
        // 6. Guarantee the last scrolling frame is captured only if it adds meaningful new content
        if let lastScrollingDisp = displacements.last(where: { $0.isScrolling }),
           sinceLastCapture > 10.0 {
            let lastCapturedTimestamp = keyFrames.last?.timestamp
            if lastCapturedTimestamp != lastScrollingDisp.frame.timestamp {
                keyFrames.append(KeyFrame(
                    image: lastScrollingDisp.frame.image,
                    cumulativeOffset: cumulativeOffset,
                    timestamp: lastScrollingDisp.frame.timestamp,
                    index: keyFrames.count
                ))
            }
        }
        
        await progressHandler(0.85, "关键帧筛选完成，共 \(keyFrames.count) 个关键帧")
        return keyFrames
    }
}
