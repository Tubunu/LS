import SwiftUI
import UIKit

/// UIViewControllerRepresentable wrapper for system UIActivityViewController
public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]
    public var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    public init(items: [Any], excludedActivityTypes: [UIActivity.ActivityType]? = nil) {
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
