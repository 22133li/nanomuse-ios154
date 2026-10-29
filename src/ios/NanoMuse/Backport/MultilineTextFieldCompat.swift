import SwiftUI

// iOS 15 backport: `TextField(_:text:axis:.vertical)` is iOS 16+.
//
// On iOS 16 and later this returns the official multi-line `TextField` unchanged,
// so supported systems keep the exact text-edit behaviour, keyboard return key,
// submit handling, focus bindings and modifier chains upstream wrote. On iOS 15
// it falls back to a `TextEditor` carrying the same binding, with the same
// placeholder text shown until the field is non-empty. This is the closest
// multi-line editor the older SDK offers; single-line-only fields are unaffected
// because those call sites use the plain `TextField` that has always existed.
struct NanoMuseMultilineTextField: View {
    let placeholder: String
    @Binding var text: String
    var axisVerticalLineLimit: ClosedRange<Int>? = nil

    /// iOS 15 only: the sizing twin's measured height; the editor is framed
    /// to it explicitly (see the iOS 15 branch for why the twin alone
    /// cannot size the stack).
    @State private var measuredH: CGFloat = 0

    private var editorH: CGFloat { max(measuredH, 36) }

    /// The text the invisible sizing twin renders on iOS 15: a space stands
    /// in for the empty field (one line), and a trailing newline gets a
    /// trailing space so the fresh empty line is counted too.
    private var measureText: String {
        if text.isEmpty { return " " }
        return text.hasSuffix("\n") ? text + " " : text
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            if let range = axisVerticalLineLimit {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(range)
            } else {
                TextField(placeholder, text: $text, axis: .vertical)
            }
        } else {
            // A bare TextEditor takes every point of height it is offered,
            // which stretched the composer to most of the screen on iOS 15
            // (device log 2026-10-29: input-bar samples of 354-920pt for an
            // empty one-line field). Size it the way the iOS 16 vertical
            // TextField sizes itself: an invisible twin of the same text --
            // same font and line limit, both inherited from the call site's
            // modifiers -- is measured, and the editor is framed to that
            // height explicitly. (Letting the twin size the ZStack is NOT
            // enough: the stack takes the flexible editor's proposed
            // height instead -- round13 shipped that and the field stayed
            // full-screen.) The twin's padding mirrors TextEditor's own
            // insets (8pt vertical, 5pt line-fragment padding) so the
            // measured height is the editor's content height.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(height: editorH)
                Text(measureText)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 5)
                    .modifier(TwinLineLimit(range: axisVerticalLineLimit))
                    .opacity(0)
                    .allowsHitTesting(false)
                    .onGeometryChangeBackport(for: CGFloat.self, tag: GeometryChangeComposerTwinTag.self) { proxy in
                        proxy.size.height
                    } action: { h in
                        if h > 0, abs(h - measuredH) > 0.5 { measuredH = h }
                    }
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color(UIColor.placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 36)
        }
    }
}

/// Applies the directly-passed line limit to the sizing twin, when a call
/// site used the initializer property instead of the `.nmLineLimit`
/// modifier (whose environment value the twin already inherits). A nil
/// range leaves the twin untouched so a call-site limit is never
/// overridden away.
private struct TwinLineLimit: ViewModifier {
    let range: ClosedRange<Int>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let range {
            content.lineLimit(range.upperBound)
        } else {
            content
        }
    }
}
