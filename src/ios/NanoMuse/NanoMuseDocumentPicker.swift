import SwiftUI
import UniformTypeIdentifiers

/// UIKit-backed document picker for iOS 15.
///
/// SwiftUI's `.fileImporter` does not reliably deliver selection callbacks on
/// iOS 15.4 (tapping files does nothing). This wraps UIDocumentPickerViewController
/// directly with an explicit delegate.
struct NanoMuseDocumentPicker: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection: Bool = true
    var onComplete: ([URL]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onComplete: ([URL]) -> Void
        var onCancel: () -> Void

        init(onComplete: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
