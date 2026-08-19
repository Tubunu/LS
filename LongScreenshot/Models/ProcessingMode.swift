import UIKit
import SwiftUI

/// Represents the active stitching mode of the application
public enum ProcessingMode: Identifiable {
    case screenshot([UIImage])
    case recording(URL)
    
    public var id: String {
        switch self {
        case .screenshot:
            return "screenshot"
        case .recording(let url):
            return "recording-\(url.absoluteString)"
        }
    }
    
    public var label: String {
        switch self {
        case .screenshot:
            return "截图拼接模式"
        case .recording:
            return "录屏转长图模式"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .screenshot:
            return "photo.on.rectangle.angled"
        case .recording:
            return "record.circle"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .screenshot:
            return .blue
        case .recording:
            return .purple
        }
    }
}
