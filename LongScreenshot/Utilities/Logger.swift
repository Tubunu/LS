import Foundation
import os

/// Centralized logger for the LongScreenshot application
public enum AppLogger {
    private static let subsystem = "com.longscreenshot.app"
    
    public static let general = Logger(subsystem: subsystem, category: "General")
    public static let stitching = Logger(subsystem: subsystem, category: "Stitching")
    public static let recording = Logger(subsystem: subsystem, category: "Recording")
    public static let vision = Logger(subsystem: subsystem, category: "Vision")
    public static let ui = Logger(subsystem: subsystem, category: "UI")
}
