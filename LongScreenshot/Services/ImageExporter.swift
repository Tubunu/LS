import UIKit
import Photos

/// Service responsible for photo library saving and file sharing exports
public actor ImageExporter {
    
    public init() {}
    
    /// Requests Photo Library authorization and saves the given image
    public func saveToPhotos(image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw RecordingError.unknown("需要相册保存权限才能保存长截图")
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    
    /// Writes the image to a temporary file for external activity sharing
    nonisolated public func exportTemporaryFile(image: UIImage, format: OutputFormat = .png) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "LongScreenshot_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).\(format.fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        let data: Data?
        switch format {
        case .png:
            data = image.pngData()
        case .jpeg(let quality):
            data = image.jpegData(compressionQuality: quality)
        }
        
        guard let validData = data else {
            throw RecordingError.unknown("无法将图片编码为数据流")
        }
        
        try validData.write(to: fileURL)
        return fileURL
    }
    
    /// Cleans up old temporary long screenshot exports and video files in the tmp directory
    nonisolated public static func cleanupTemporaryFiles() {
        DispatchQueue.global(qos: .utility).async {
            let tempDir = FileManager.default.temporaryDirectory
            guard let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            
            let now = Date()
            for file in files {
                let name = file.lastPathComponent
                if name.hasPrefix("LongScreenshot_") || name.hasSuffix(".mp4") || name.hasSuffix(".mov") {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                       let modDate = attrs[.modificationDate] as? Date,
                       now.timeIntervalSince(modDate) > 3600 {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        }
    }
    
    public enum OutputFormat: Sendable {
        case png
        case jpeg(quality: CGFloat)
        
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }
}
