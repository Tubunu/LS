import SwiftUI

/// Thumbnail preview item with badge and delete button
public struct ImageThumbnail: View {
    public let image: UIImage
    public let index: Int
    public var onDelete: (() -> Void)?
    
    public init(image: UIImage, index: Int, onDelete: (() -> Void)? = nil) {
        self.image = image
        self.index = index
        self.onDelete = onDelete
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 85, height: 145)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
            
            // Order index pill (top-left)
            HStack {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 2)
                    .offset(x: 6, y: 6)
                
                Spacer()
                
                // Delete button (top-right)
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                    }
                    .offset(x: -4, y: 4)
                }
            }
        }
        .frame(width: 85, height: 145)
    }
}
