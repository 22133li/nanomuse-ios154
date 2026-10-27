import SwiftUI

// iOS 15 backport: `scrollContentBackground` and `toolbarBackground` are
// iOS 16+. On iOS 16 and later the official modifiers are applied unchanged;
// on iOS 15 they are a no-op, which leaves the system defaults of that SDK.
extension View {
    @ViewBuilder
    func nanoMuseHideScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func nanoMuseToolbarBackgroundVisible() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func nanoMuseToolbarBackground<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(style, for: .navigationBar)
        } else {
            self
        }
    }
}
