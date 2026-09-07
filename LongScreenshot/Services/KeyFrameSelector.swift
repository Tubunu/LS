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
        var latestForwardFrame = displacements[0]
        
        // The first frame is always the starting keyframe
        keyFrames.append(KeyFrame(
            image: displacements[0].frame.image,
            cumulativeOffset: 0,
            timestamp: displacements[0].frame.timestamp,
            index: 0
        ))
        
        let total = displacements.count
        
        var index = 1
        while index < total {
            if Task.isCancelled { return [] }
            let disp = displacements[index]
            let absDy = abs(disp.dy)
            
            // 1. Filter out static or non-scrolling frames
            if !disp.isScrolling || absDy < config.minScrollSpeed {
                index += 1
                continue
            }
            
            // 2. Clamp extreme sudden jumps to maxScrollSpeed rather than discarding motion
            let effectiveDy = min(absDy, config.maxScrollSpeed)
            
            // 3. Establish & verify scroll direction consistency (downward vs upward)
            let currentDirection: CGFloat = disp.dy > 0 ? 1 : -1
            if primaryScrollDirection == 0 {
                dirAccumulator += disp.dy
                if abs(dirAccumulator) >= 10.0 {
                    primaryScrollDirection = dirAccumulator > 0 ? 1 : -1
                } else {
                    index += 1
                    continue
                }
            } else if currentDirection != primaryScrollDirection {
                // Ignore bouncing or reversed scroll jitter
                index += 1
                continue
            }
            
            // 4. Accumulate displacement
            cumulativeOffset += effectiveDy
            sinceLastCapture += effectiveDy
            latestForwardFrame = disp
            
            // 5. Trigger keyframe capture if threshold reached
            if sinceLastCapture >= config.captureThreshold {
                var captureTarget = disp
                var bestIndex = index
                
                // If currently in rapid motion (potential motion blur), look ahead for the next local deceleration / pause
                // Strict hard ceiling: lookahead must never exceed captureThreshold * 1.25 to prevent skipping content
                if absDy > 20.0 && index + 1 < total {
                    var minSpeed = absDy
                    let maxLookaheadDist = config.captureThreshold * 1.25
                    let lookEnd = min(total, index + 15)
                    var runningDist = sinceLastCapture
                    
                    for j in (index + 1)..<lookEnd {
                        let candDy = min(abs(displacements[j].dy), config.maxScrollSpeed)
                        runningDist += candDy
                        if runningDist > maxLookaheadDist {
                            break
                        }
                        let candSpeed = abs(displacements[j].dy)
                        if candSpeed < minSpeed {
                            minSpeed = candSpeed
                            captureTarget = displacements[j]
                            bestIndex = j
                        }
                        if candSpeed <= 3.0 { break }
                    }
                }
                
                // If we looked ahead and picked a frame ahead, advance cumulativeOffset and index accordingly
                if bestIndex > index {
                    for j in (index + 1)...bestIndex {
                        let candDy = min(abs(displacements[j].dy), config.maxScrollSpeed)
                        cumulativeOffset += candDy
                    }
                    latestForwardFrame = captureTarget
                    index = bestIndex
                }
                
                keyFrames.append(KeyFrame(
                    image: captureTarget.frame.image,
                    cumulativeOffset: cumulativeOffset,
                    timestamp: captureTarget.frame.timestamp,
                    index: keyFrames.count
                ))
                sinceLastCapture = 0
                
                let progress = 0.70 + (Double(index) / Double(total)) * 0.15
                await progressHandler(progress, "已筛选 \(keyFrames.count) 个关键帧...")
            }
            
            index += 1
        }
        
        // 6. Guarantee the final settled frame is captured if it adds meaningful new content (discarding terminal rebound)
        if sinceLastCapture > 10.0 {
            let targetFrame = latestForwardFrame
            let lastCapturedTimestamp = keyFrames.last?.timestamp
            if lastCapturedTimestamp != targetFrame.frame.timestamp {
                keyFrames.append(KeyFrame(
                    image: targetFrame.frame.image,
                    cumulativeOffset: cumulativeOffset,
                    timestamp: targetFrame.frame.timestamp,
                    index: keyFrames.count
                ))
            }
        }
        
        await progressHandler(0.85, "关键帧筛选完成，共 \(keyFrames.count) 个关键帧")
        return keyFrames
    }
}
