import SwiftUI

/// iOS 15 backport: SwiftUI's ImageRenderer(content:) is iOS 16+.
/// Snapshots a SwiftUI view off-screen through a UIHostingController.
enum ViewSnapshot {
    @MainActor
    static func image<V: View>(of view: V, size: CGSize, scale: CGFloat = 1) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
