import SwiftUI
import PhotosUI

@MainActor
public final class ScreenshotViewModel: ObservableObject {
    @Published public var photoItems: [PhotosPickerItem] = [] {
        didSet {
            loadSelectedPhotos()
        }
    }
    @Published public var selectedImages: [UIImage] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    
    public init() {}
    
    /// Loads UIImage instances from selected PhotosPickerItems
    public func loadSelectedPhotos() {
        guard !photoItems.isEmpty else {
            selectedImages = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            var loadedImages: [UIImage] = []
            
            for item in photoItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loadedImages.append(image)
                }
            }
            
            self.selectedImages = loadedImages
            self.isLoading = false
        }
    }
    
    /// Removes an image from the selection
    public func removeImage(at index: Int) {
        guard index >= 0, index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        if index < photoItems.count {
            photoItems.remove(at: index)
        }
    }
    
    /// Reorders images in the sequence
    public func moveImage(from source: IndexSet, to destination: Int) {
        selectedImages.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Clears all selections
    public func clearAll() {
        photoItems = []
        selectedImages = []
    }
}
