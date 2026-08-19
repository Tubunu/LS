import Foundation
import CoreGraphics
import Vision

/// Service responsible for calculating translational displacement between adjacent video frames using Apple Vision
public actor ScrollDetector {
    
    public init() {}
    
    /// Computes translation vectors between consecutive video frames
    /// - Parameters:
    ///   - frames: Array of extracted FrameData
    ///   - progressHandler: Progress callback (0.40 ... 0.70 range)
    /// - Returns: Array of FrameDisplacement
    public func detectDisplacements(
        frames: [FrameData],
        progressHandler: @Sendable @MainActor (Double, String) -> Void
    ) async throws -> [FrameDisplacement] {
        guard frames.count >= 2 else {
            throw RecordingError.insufficientFrames
        }
        
        var displacements: [FrameDisplacement] = []
        
        // Initial frame has 0 displacement
        displacements.append(FrameDisplacement(
            frame: frames[0],
            dy: 0,
            dx: 0,
            isScrolling: false
        ))
        
        let count = frames.count
        let sequenceHandler = VNSequenceRequestHandler()
        
        for i in 1..<count {
            if Task.isCancelled {
                throw RecordingError.processingCancelled
            }
            
            let previousImage = frames[i - 1].image
            let currentImage = frames[i].image
            
            let h = CGFloat(previousImage.height)
            let w = CGFloat(previousImage.width)
            let contentROI = CGRect(x: 0, y: (h * 0.12).rounded(), width: w, height: (h * 0.76).rounded()).integral
            let prevContent = previousImage.safeCropping(to: contentROI) ?? previousImage
            let currContent = currentImage.safeCropping(to: contentROI) ?? currentImage
            
            let request = VNTranslationalImageRegistrationRequest(
                targetedCGImage: currContent
            )
            
            do {
                try sequenceHandler.perform([request], on: prevContent, orientation: .up)
            } catch {
                AppLogger.vision.warning("Vision registration failed at frame \(i): \(error.localizedDescription)")
            }
            
            var dy: CGFloat = 0
            var dx: CGFloat = 0
            
            if let result = request.results?.first as? VNImageTranslationAlignmentObservation {
                let transform = result.alignmentTransform
                dx = transform.tx
                dy = -transform.ty
            }
            
            // Criteria for active vertical scroll:
            // 1. Vertical displacement > 2.0px (ignores subtle jitter)
            // 2. Horizontal drift < 20.0px (avoids side swiping / page transitions)
            let isScrolling = abs(dy) > 2.0 && abs(dx) < 20.0
            
            displacements.append(FrameDisplacement(
                frame: frames[i],
                dy: dy,
                dx: dx,
                isScrolling: isScrolling
            ))
            
            let currentProgress = 0.40 + (Double(i) / Double(count)) * 0.30
            await progressHandler(currentProgress, "正在分析滚动位移（\(i)/\(count - 1)）...")
        }
        
        return displacements
    }
}
