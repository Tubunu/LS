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
    
    public init(resultImage: UIImage) {
        self.resultImage = resultImage
    }
    
    /// Saves the result image to the user's photo library
    public func saveToPhotos() {
        guard !isSaved, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                try await exporter.saveToPhotos(image: resultImage)
                self.isSaved = true
                self.isSaving = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isSaving = false
            }
        }
    }
    
    /// Prepares a temporary file URL for sharing
    public func prepareSharing() {
        do {
            let url = try exporter.exportTemporaryFile(image: resultImage, format: .png)
            self.shareableURL = url
            self.showShareSheet = true
        } catch {
            self.errorMessage = "无法生成分享文件：\(error.localizedDescription)"
        }
    }
}
