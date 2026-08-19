import Foundation
import CoreGraphics

/// Configuration parameters for fixed UI elements cropping (Status bar, Home indicator, etc.)
public struct CropConfig: Sendable, Equatable {
    public var statusBarHeight: CGFloat
    public var bottomSafeArea: CGFloat
    public var navBarHeight: CGFloat
    public var tabBarHeight: CGFloat
    
    public init(
        statusBarHeight: CGFloat = 59.0, // Standard iPhone 14/15/16 Pro Dynamic Island height
        bottomSafeArea: CGFloat = 34.0,  // Standard Home Indicator safe area inset
        navBarHeight: CGFloat = 44.0,
        tabBarHeight: CGFloat = 49.0
    ) {
        self.statusBarHeight = statusBarHeight
        self.bottomSafeArea = bottomSafeArea
        self.navBarHeight = navBarHeight
        self.tabBarHeight = tabBarHeight
    }
    
    public static let standard = CropConfig()
    public static let zero = CropConfig(statusBarHeight: 0, bottomSafeArea: 0, navBarHeight: 0, tabBarHeight: 0)
    
    /// Adaptively determines statusBar and home indicator height based on image aspect ratio and pixel dimensions.
    /// Assumes standard portrait layout where height > width; aspect ratio is derived from longer / shorter edge.
    public static func adaptive(for size: CGSize) -> CropConfig {
        guard size.width > 0, size.height > 0 else { return .standard }
        let portraitHeight = max(size.width, size.height)
        let portraitWidth = min(size.width, size.height)
        let aspect = portraitHeight / portraitWidth
        
        if aspect >= 2.14 {
            // Dynamic Island models (iPhone 14 Pro, 15 series, 16 series)
            return CropConfig(statusBarHeight: 59.0, bottomSafeArea: 34.0)
        } else if aspect >= 2.0 {
            // Notch models (iPhone X, XS, 11, 12, 13, 14 standard)
            return CropConfig(statusBarHeight: 47.0, bottomSafeArea: 34.0)
        } else if aspect >= 1.7 {
            // Classic 16:9 models (iPhone SE 2/3, iPhone 8/7/6)
            return CropConfig(statusBarHeight: 20.0, bottomSafeArea: 0.0)
        } else {
            // iPad or tablet aspect ratios (~4:3 / ~3:2)
            return CropConfig(statusBarHeight: 24.0, bottomSafeArea: 20.0)
        }
    }
}
