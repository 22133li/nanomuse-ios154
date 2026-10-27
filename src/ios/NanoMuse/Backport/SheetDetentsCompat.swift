import SwiftUI

// iOS 15 backport: `presentationDetents` and `presentationDragIndicator` are
// iOS 16+. Called from source that must compile against the iOS 15 SDK, these
// helpers keep the official sheet sizes on iOS 16+ and leave the sheet at the
// system default on iOS 15 (the only choice the older SDK exposes).
enum NanoMuseSheetSize {
    case large
    case medium
    case mediumOrLarge
    case fraction(CGFloat)
    case height(CGFloat)
}

extension View {
    @ViewBuilder
    func nanoMuseSheetSize(_ size: NanoMuseSheetSize) -> some View {
        if #available(iOS 16.0, *) {
            switch size {
            case .large:
                self.presentationDetents([.large])
            case .medium:
                self.presentationDetents([.medium])
            case .mediumOrLarge:
                self.presentationDetents([.medium, .large])
            case .fraction(let value):
                self.presentationDetents([.fraction(value)])
            case .height(let value):
                self.presentationDetents([.height(value)])
            }
        } else {
            self
        }
    }

    /// Two-size variant: a fraction with the large detent above it.
    @ViewBuilder
    func nanoMuseSheetFractionOrLarge(_ fraction: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.fraction(fraction), .large])
        } else {
            self
        }
    }

    /// A fixed height with the medium detent as the second stop.
    @ViewBuilder
    func nanoMuseSheetHeightOrMedium(_ height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(height), .medium])
        } else {
            self
        }
    }

    @ViewBuilder
    func nanoMuseSheetDragIndicator(_ visible: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(visible ? .visible : .hidden)
        } else {
            self
        }
    }
}
