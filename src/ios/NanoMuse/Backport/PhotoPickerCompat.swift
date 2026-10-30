import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// iOS 15 backport: SwiftUI's PhotosPicker (`PhotosPickerItem`,
// `.photosPicker(selection:)`) is iOS 16+.
//
// `NanoMusePick` is the one value both OS paths produce, so the call sites keep
// the same downstream flow (placeholder chip, concurrent load, original bytes).
// On iOS 16+ it wraps the official `PhotosPickerItem` and loads through
// `loadTransferable`, exactly as upstream did. On iOS 15 it wraps a
// `PHPickerResult` and loads through `NSItemProvider`.
struct NanoMusePick {
    let isVideo: Bool
    let assetIdentifier: String?
    let fileExtension: String?

    // iOS 16+ payload.
    let photoItem: Any?
    // iOS 15 payload.
    let provider: NSItemProvider?

    @available(iOS 16.0, *)
    init(item: PhotosPickerItem) {
        self.isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        self.assetIdentifier = item.itemIdentifier
        self.fileExtension = item.supportedContentTypes
            .first { $0.conforms(to: .image) }?
            .preferredFilenameExtension
        self.photoItem = item
        self.provider = nil
    }

    init(result: PHPickerResult) {
        let p = result.itemProvider
        self.isVideo = p.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        self.assetIdentifier = result.assetIdentifier
        self.fileExtension = p.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { $0.conforms(to: .image) }?
            .preferredFilenameExtension
        self.photoItem = nil
        self.provider = p
    }

    /// The original encoded bytes of the picked image, or nil when the item
    /// cannot produce them (the caller marks that placeholder failed).
    func imageData() async -> Data? {
        if #available(iOS 16.0, *), let item = photoItem as? PhotosPickerItem {
            return try? await item.loadTransferable(type: Data.self)
        }
        guard let provider else { return nil }
        for typeId in provider.registeredTypeIdentifiers {
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data { return data }
        }
        return nil
    }

    /// A file URL for the picked movie. PHPicker owns its callback URL only
    /// for the duration of the callback, so the iOS 15 path copies it first.
    func videoFileURL() async -> URL? {
        if #available(iOS 16.0, *), let item = photoItem as? PhotosPickerItem {
            guard let movie = try? await item.loadTransferable(type: NanoMusePickedMovie.self) else { return nil }
            return movie.url
        }
        guard let provider else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let owned = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nanomuse-picked-\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: owned)
                    continuation.resume(returning: owned)
                } catch {
                    AppLogger(category: "PhotoPicker").error("could not retain the picked movie: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// The official video export type, kept for the iOS 16+ `loadTransferable` path.
@available(iOS 16.0, *)
struct NanoMusePickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("nanomuse-picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

// MARK: - Multi-select picker

/// Drops in for `.photosPicker(isPresented:selection:maxSelectionCount:matching:)`
/// plus its `onChange` handler. iOS 16+ runs the official PhotosPicker; iOS 15
/// presents the UIKit photo picker with the same filter and selection limit.
struct NanoMusePhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    var maxSelectionCount: Int = 50
    var allowsImages = true
    var allowsVideos = true
    let onPicked: ([NanoMusePick]) -> Void

    private var filter: PHPickerFilter {
        var set: [PHPickerFilter] = []
        if allowsImages { set.append(.images) }
        if allowsVideos { set.append(.videos) }
        return set.count == 1 ? set[0] : .any(of: set)
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.modifier(NanoMusePhotoPicker16(
                isPresented: $isPresented,
                maxSelectionCount: maxSelectionCount,
                filter: filter,
                onPicked: onPicked
            ))
        } else {
            content.sheet(isPresented: $isPresented) {
                NanoMusePHPicker(
                    onComplete: { results in
                        isPresented = false
                        onPicked(results.map { NanoMusePick(result: $0) })
                    },
                    onCancel: { isPresented = false },
                    selectionLimit: maxSelectionCount,
                    filter: filter
                )
            }
        }
    }
}

/// The official PhotosPicker path. Isolated behind availability because
/// `PhotosPickerItem` itself is iOS 16+.
@available(iOS 16.0, *)
private struct NanoMusePhotoPicker16: ViewModifier {
    @Binding var isPresented: Bool
    let maxSelectionCount: Int
    let filter: PHPickerFilter
    let onPicked: ([NanoMusePick]) -> Void

    @State private var items: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented,
                          selection: $items,
                          maxSelectionCount: maxSelectionCount,
                          matching: filter)
            .onChange(of: items) { picked in
                guard !picked.isEmpty else { return }
                let picks = picked.map { NanoMusePick(item: $0) }
                items = []
                onPicked(picks)
            }
    }
}

// MARK: - Single-select picker

/// Drops in for `.photosPicker(isPresented:selection:matching:)` with a single
/// optional item.
struct NanoMuseSinglePhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    var allowsImages = true
    var allowsVideos = false
    let onPicked: (NanoMusePick?) -> Void

    private var filter: PHPickerFilter {
        allowsVideos && allowsImages ? .any(of: [.images, .videos])
            : (allowsVideos ? .videos : .images)
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.modifier(NanoMuseSinglePhotoPicker16(
                isPresented: $isPresented,
                filter: filter,
                onPicked: onPicked
            ))
        } else {
            content.sheet(isPresented: $isPresented) {
                NanoMusePHPicker(
                    onComplete: { results in
                        isPresented = false
                        onPicked(results.first.map { NanoMusePick(result: $0) })
                    },
                    onCancel: { isPresented = false },
                    selectionLimit: 1,
                    filter: filter
                )
            }
        }
    }
}

@available(iOS 16.0, *)
private struct NanoMuseSinglePhotoPicker16: ViewModifier {
    @Binding var isPresented: Bool
    let filter: PHPickerFilter
    let onPicked: (NanoMusePick?) -> Void

    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented,
                          selection: $item,
                          matching: filter,
                          photoLibrary: .shared())
            .onChange(of: item) { picked in
                guard let picked else { return }
                item = nil
                onPicked(NanoMusePick(item: picked))
            }
    }
}
