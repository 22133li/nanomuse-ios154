import SwiftUI

// iOS 15 backport: `NavigationStack` is iOS 16+.
//
// On iOS 16 and later this renders the official `NavigationStack` unchanged,
// so supported systems keep the exact upstream navigation behaviour. On iOS 15
// it falls back to `NavigationView` in stack style, which is the closest
// system equivalent available there.
struct NanoMuseCompatNavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NanoMuseCompatNavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
        }
    }
}

// iOS 15 backport: `presentationDetents` / `presentationDragIndicator` are
// iOS 16+. Applying them only on iOS 16+ leaves the iOS 15 sheet at the
// system default height instead of silently changing the sheet's content.
extension View {
    @ViewBuilder
    func nanoMusePresentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(detents)
        } else {
            self
        }
    }
}
