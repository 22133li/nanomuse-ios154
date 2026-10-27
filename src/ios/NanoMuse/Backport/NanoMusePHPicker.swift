import PhotosUI
import SwiftUI

// MARK: - iOS 15.4 Photo Picker (PHPickerViewController fallback)

/// iOS 15.4 backport: PHPickerViewController wrapper (SwiftUI .photosPicker is iOS 16+).
/// Supports multi-select of images and videos, matching the original PhotosPicker behavior.
struct NanoMusePHPicker: UIViewControllerRepresentable {
    var onComplete: ([PHPickerResult]) -> Void
    var onCancel: () -> Void
    /// iOS 15 backport parity: callers that need single-image (e.g. SOUL
    /// avatar) override these; the chat attachment picker keeps the defaults.
    var selectionLimit: Int = 50
    var filter: PHPickerFilter = .any(of: [.images, .videos])

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = filter
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([PHPickerResult]) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping ([PHPickerResult]) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                onCancel()
            } else {
                onComplete(results)
            }
        }
    }
}
