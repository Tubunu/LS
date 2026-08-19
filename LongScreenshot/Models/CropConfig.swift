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
}
