import SwiftUI
import UIKit

// iOS 15 backport: SwiftUI's `ShareLink` is iOS 16+. On iOS 16 and later the
// official ShareLink is used unchanged; on iOS 15 a Button presents the same
// UIActivityViewController that ShareLink itself wraps.
struct NanoMuseShareLink<Label: View>: View {
    private let url: URL
    private let label: Label
    @State private var showing = false

    init(item: URL, @ViewBuilder label: () -> Label) {
        self.url = item
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: url) { label }
        } else {
            Button { showing = true } label: { label }
                .sheet(isPresented: $showing) {
                    NanoMuseActivitySheet(items: [url])
                }
        }
    }
}

extension NanoMuseShareLink where Label == DefaultLabel {
    init(item: URL) {
        self.init(item: item) { DefaultLabel(title: item.lastPathComponent) }
    }

    struct DefaultLabel: View {
        let title: String
        var body: some View {
            Label(title, systemImage: "square.and.arrow.up")
        }
    }
}

/// The system share sheet, for the iOS 15 paths that cannot use ShareLink.
struct NanoMuseActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
