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
            NavigationStack {
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
