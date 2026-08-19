import SwiftUI
import PhotosUI

@MainActor
public final class ScreenshotViewModel: ObservableObject {
    @Published public var photoItems: [PhotosPickerItem] = [] {
        didSet {
            if !isUpdatingInternally {
                loadSelectedPhotos()
            }
        }
    }
    @Published public var selectedImages: [UIImage] = []
    @Published public var thumbnails: [UIImage] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    
    private var itemImagePairs: [(item: PhotosPickerItem, image: UIImage, thumbnail: UIImage)] = []
    private var loadTask: Task<Void, Never>?
    private var isUpdatingInternally: Bool = false
    
    public init() {}
    
    /// Loads UIImage instances from selected PhotosPickerItems, reusing already loaded instances where possible
    public func loadSelectedPhotos() {
        loadTask?.cancel()
        
        guard !photoItems.isEmpty else {
            itemImagePairs = []
            selectedImages = []
            thumbnails = []
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let currentItems = photoItems
        let existingMap = Dictionary(itemImagePairs.map { ($0.item, ($0.image, $0.thumbnail)) }, uniquingKeysWith: { first, _ in first })
        
        loadTask = Task {
            var newPairs: [(item: PhotosPickerItem, image: UIImage, thumbnail: UIImage)] = []
            
            for item in currentItems {
                if Task.isCancelled { return }
                
                if let cached = existingMap[item] {
                    newPairs.append((item: item, image: cached.0, thumbnail: cached.1))
                } else {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            let thumbnail = image.resizedThumbnail(maxSize: 300)
                            newPairs.append((item: item, image: image, thumbnail: thumbnail))
                        } else {
                            self.errorMessage = "部分图片未能成功解析"
                        }
                    } catch {
                        self.errorMessage = "部分图片加载失败：\(error.localizedDescription)"
                    }
                }
            }
            
            if !Task.isCancelled {
                self.itemImagePairs = newPairs
                self.selectedImages = newPairs.map { $0.image }
                self.thumbnails = newPairs.map { $0.thumbnail }
                self.isUpdatingInternally = true
                self.photoItems = newPairs.map { $0.item }
                self.isUpdatingInternally = false
                self.isLoading = false
            }
        }
    }
    
    /// Removes an image from the selection without triggering a full reload
    public func removeImage(at index: Int) {
        guard index >= 0, index < itemImagePairs.count else { return }
        itemImagePairs.remove(at: index)
        selectedImages = itemImagePairs.map { $0.image }
        thumbnails = itemImagePairs.map { $0.thumbnail }
        
        isUpdatingInternally = true
        photoItems = itemImagePairs.map { $0.item }
        isUpdatingInternally = false
    }
    
    /// Reorders images in the sequence
    public func moveImage(from source: IndexSet, to destination: Int) {
        itemImagePairs.move(fromOffsets: source, toOffset: destination)
        selectedImages = itemImagePairs.map { $0.image }
        thumbnails = itemImagePairs.map { $0.thumbnail }
        
        isUpdatingInternally = true
        photoItems = itemImagePairs.map { $0.item }
        isUpdatingInternally = false
    }
    
    /// Clears all selections
    public func clearAll() {
        loadTask?.cancel()
        isUpdatingInternally = true
        itemImagePairs = []
        photoItems = []
        selectedImages = []
        thumbnails = []
        isLoading = false
        isUpdatingInternally = false
    }
}
