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
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            let bounds = controller.view.bounds
            let midX = bounds.width > 0 ? bounds.midX : UIScreen.main.bounds.midX
            let midY = bounds.height > 0 ? bounds.midY : UIScreen.main.bounds.midY
            popover.sourceRect = CGRect(x: midX, y: midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
