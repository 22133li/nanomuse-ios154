import SwiftUI

// iOS 15 backport helpers for iOS 16+ SwiftUI modifiers used at isolated call
// sites. On iOS 16+ each helper applies the official modifier unchanged, so
// supported systems keep the exact upstream behaviour. On iOS 15 the helper
// is an identity (or the closest system equivalent, noted per helper) because
// the API does not exist there at all.

// MARK: - Drag & drop (session list)

extension View {
    /// `.draggable` is iOS 16+. iOS 15 has no SwiftUI drag source for this
    /// row; the menu-based move actions remain available.
    @ViewBuilder
    func nmDraggable(_ id: String) -> some View {
        if #available(iOS 16, *) {
            self.draggable(id)
        } else {
            self
        }
    }

    /// `.dropDestination(for:action:isTargeted:)` is iOS 16+. iOS 15 has no
    /// drop target here; the drag source above is likewise absent on 15.
    @ViewBuilder
    func nmDropDestination(
        for type: String.Type,
        action: @escaping ([String], CGPoint) -> Bool,
        isTargeted: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 16, *) {
            self.dropDestination(for: type, action: action, isTargeted: isTargeted)
        } else {
            self
        }
    }
}

// MARK: - Navigation

extension View {
    /// `.navigationSplitViewColumnWidth` is iOS 16+. On iOS 15 the split
    /// layout is an HStack whose sidebar width is set with `.frame` at the
    /// call site, so this is an identity there.
    @ViewBuilder
    func nmNavigationSplitViewColumnWidth(min: CGFloat, ideal: CGFloat, max: CGFloat) -> some View {
        if #available(iOS 16, *) {
            self.navigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
        } else {
            self
        }
    }

    /// `.toolbar(_:for:)` visibility is iOS 16+. On iOS 15
    /// `.navigationBarHidden` is the equivalent.
    @ViewBuilder
    func nmNavigationBarHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16, *) {
            self.toolbar(hidden ? .hidden : .visible, for: .navigationBar)
        } else {
            self.navigationBarHidden(hidden)
        }
    }

    /// Tap navigation for session rows on iOS 15 only. On iOS 16+ the row's
    /// hidden `NavigationLink(value:)` handles the tap, so this must stay
    /// out of the way there.
    @ViewBuilder
    func nmOnTapGesture15(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 16, *) {
            self
        } else {
            self.onTapGesture(perform: action)
        }
    }
}

/// `ToolbarItemPlacement.secondaryAction` is iOS 16+. `.navigationBarTrailing`
/// is the closest iOS 15 equivalent.
var nmSecondaryActionPlacement: ToolbarItemPlacement {
    if #available(iOS 16, *) {
        .secondaryAction
    } else {
        .navigationBarTrailing
    }
}

// MARK: - Scrolling & keyboard

extension View {
    /// `.scrollDismissesKeyboard` is iOS 16+. On iOS 15 the keyboard keeps
    /// its default dismiss behaviour.
    @ViewBuilder
    func nmScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    /// `.scrollIndicators` is iOS 16+. Indicators are visible by default on
    /// iOS 15, so dropping the modifier there changes nothing visible.
    @ViewBuilder
    func nmScrollIndicatorsVisible() -> some View {
        if #available(iOS 16, *) {
            self.scrollIndicators(.visible)
        } else {
            self
        }
    }
}

// MARK: - Bars & overlays

extension View {
    /// `.toolbarBackground` is iOS 16+. On iOS 15 the bar keeps its default
    /// background.
    @ViewBuilder
    func nmToolbarBackgroundHidden(_ hidden: Bool) -> some View {
        if #available(iOS 16, *) {
            self.toolbarBackground(hidden ? .hidden : .visible, for: .navigationBar)
        } else {
            self
        }
    }

    /// `.persistentSystemOverlays` is iOS 16+. On iOS 15 the overlays keep
    /// their default behaviour.
    @ViewBuilder
    func nmPersistentSystemOverlaysHidden() -> some View {
        if #available(iOS 16, *) {
            self.persistentSystemOverlays(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Text & lists

extension View {
    /// Range `.lineLimit` (e.g. `1...4`) is iOS 16+. On iOS 15 only the upper
    /// bound can be expressed; the minimum is unenforceable there.
    @ViewBuilder
    func nmLineLimit(_ range: ClosedRange<Int>) -> some View {
        if #available(iOS 16, *) {
            self.lineLimit(range)
        } else {
            self.lineLimit(range.upperBound)
        }
    }

    /// `.listRowSeparatorLeading` alignment guide is iOS 16+. On iOS 15 the
    /// separator keeps its default inset.
    @ViewBuilder
    func nmListRowSeparatorLeadingZero() -> some View {
        if #available(iOS 16, *) {
            self.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } else {
            self
        }
    }
}

// MARK: - Context menus

extension View {
    /// `.contextMenu(menuItems:preview:)` is iOS 16+. On iOS 15 the menu
    /// renders without the custom preview (the system default preview).
    @ViewBuilder
    func nmContextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        if #available(iOS 16, *) {
            self.contextMenu(menuItems: menuItems, preview: preview)
        } else {
            self.contextMenu(menuItems: menuItems)
        }
    }
}
