import SwiftUI
import UIKit

@MainActor
public final class PreviewViewModel: ObservableObject {
    @Published public var resultImage: UIImage
    @Published public var isSaved: Bool = false
    @Published public var isSaving: Bool = false
    @Published public var showShareSheet: Bool = false
    @Published public var shareableURL: URL?
    @Published public var errorMessage: String?
    @Published public var zoomScale: CGFloat = 1.0
    
    private let exporter = ImageExporter()
    private var saveTask: Task<Void, Never>?
    
    public init(resultImage: UIImage) {
        self.resultImage = resultImage
    }
    
    /// Saves the result image to the user's photo library
    public func saveToPhotos(quality: Double = 1.0) {
        guard !isSaved, !isSaving else { return }
        saveTask?.cancel()
        isSaving = true
        errorMessage = nil
        
        let imageToSave: UIImage
        if quality < 0.99 {
            imageToSave = resultImage.scaled(by: CGFloat(quality))
        } else {
            imageToSave = resultImage
        }
        
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.exporter.saveToPhotos(image: imageToSave)
                if !Task.isCancelled {
                    self.isSaved = true
                    self.isSaving = false
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }
    
    /// Prepares a temporary file URL for sharing
    public func prepareSharing(quality: Double = 1.0) {
        do {
            let imageToExport: UIImage
            if quality < 0.99 {
                imageToExport = resultImage.scaled(by: CGFloat(quality))
            } else {
                imageToExport = resultImage
            }
            let format: ImageExporter.OutputFormat = quality < 0.99 ? .jpeg(quality: CGFloat(quality)) : .png
            let url = try exporter.exportTemporaryFile(image: imageToExport, format: format)
            self.shareableURL = url
            self.showShareSheet = true
        } catch {
            self.errorMessage = "无法生成分享文件：\(error.localizedDescription)"
        }
    }
}
