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

    init(item: URL) where Label == Text {
        self.url = item
        self.label = Text(item.lastPathComponent)
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

struct NanoMuseDefaultShareLink: View {
    private let url: URL

    init(item: URL) { self.url = item }

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: url)
        } else {
            Button { share() } label: {
                Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
            }
        }
    }

    private func share() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(activity, animated: true)
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
