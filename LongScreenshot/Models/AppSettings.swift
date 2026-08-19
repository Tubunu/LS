import Foundation
import SwiftUI

/// App color theme preference options
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色明亮"
        case .dark: return "深色深邃"
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Centralized app settings keys and defaults
public enum AppSettings {
    public static let appThemeKey = "appTheme"
    public static let outputQualityKey = "outputQuality"
    public static let autoDetectFixedUIKey = "autoDetectFixedUI"
    public static let blendingWidthKey = "blendingWidth"
    public static let recordingSamplingFPSKey = "recordingSamplingFPS"
    public static let keyFrameThresholdKey = "keyFrameThreshold"
    
    public static let defaultTheme: AppTheme = .system
    public static let defaultOutputQuality: Double = 1.0
    public static let defaultAutoDetectFixedUI: Bool = true
    public static let defaultBlendingWidth: Double = 40.0
    public static let defaultRecordingSamplingFPS: Double = 5.0
    public static let defaultKeyFrameThreshold: Double = 300.0
}
