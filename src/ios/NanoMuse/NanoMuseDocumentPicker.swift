import SwiftUI
import UniformTypeIdentifiers

// [T-ios154-fileimporter] UIKit UIDocumentPickerViewController wrapper.
// SwiftUI .fileImporter does not call its completion on iOS 15.4 when attached
// to a view with multiple sheet/fullScreenCover modifiers (presentation bug).
// This bypasses SwiftUI's presentation and uses UIKit directly.
// Ported from the Minis line's MinisDocumentPicker (device-verified on
// iOS 15.4); `asCopy` and `allowsMultipleSelection` are parameters here
// because the provider-import and backup-restore call sites hand the picked
// URL to handlers that open a security scope on it, which the copied temp
// URL produced by asCopy: true cannot satisfy.
struct NanoMuseDocumentPicker: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection: Bool
    var asCopy: Bool
    var onComplete: ([URL]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: asCopy)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: ([URL]) -> Void
        let onCancel: () -> Void

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

extension View {
    /// [T-ios154-fileimporter] Multi-selection file import: `.fileImporter`
    /// on iOS 16+, the UIKit document picker in a sheet on iOS 15, where the
    /// SwiftUI completion never fires. On iOS 15 a cancel dismisses silently
    /// (no `.failure` is delivered), matching the Minis line's behaviour.
    @ViewBuilder
    func nmFileImporter(isPresented: Binding<Bool>,
                        allowedContentTypes: [UTType],
                        allowsMultipleSelection: Bool,
                        asCopy: Bool,
                        onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View {
        if #available(iOS 16.0, *) {
            self.fileImporter(isPresented: isPresented,
                              allowedContentTypes: allowedContentTypes,
                              allowsMultipleSelection: allowsMultipleSelection,
                              onCompletion: onCompletion)
        } else {
            self.sheet(isPresented: isPresented) {
                NanoMuseDocumentPicker(
                    allowedContentTypes: allowedContentTypes,
                    allowsMultipleSelection: allowsMultipleSelection,
                    asCopy: asCopy,
                    onComplete: { urls in
                        isPresented.wrappedValue = false
                        onCompletion(.success(urls))
                    },
                    onCancel: {
                        isPresented.wrappedValue = false
                    }
                )
            }
        }
    }

    /// [T-ios154-fileimporter] Single-selection form of `nmFileImporter`;
    /// same availability split and silent-cancel behaviour on iOS 15.
    @ViewBuilder
    func nmFileImporter(isPresented: Binding<Bool>,
                        allowedContentTypes: [UTType],
                        asCopy: Bool,
                        onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        if #available(iOS 16.0, *) {
            self.fileImporter(isPresented: isPresented,
                              allowedContentTypes: allowedContentTypes,
                              onCompletion: onCompletion)
        } else {
            self.sheet(isPresented: isPresented) {
                NanoMuseDocumentPicker(
                    allowedContentTypes: allowedContentTypes,
                    allowsMultipleSelection: false,
                    asCopy: asCopy,
                    onComplete: { urls in
                        isPresented.wrappedValue = false
                        if let url = urls.first {
                            onCompletion(.success(url))
                        }
                    },
                    onCancel: {
                        isPresented.wrappedValue = false
                    }
                )
            }
        }
    }
}
