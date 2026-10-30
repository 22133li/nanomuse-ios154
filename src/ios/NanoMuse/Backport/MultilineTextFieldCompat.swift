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
    /// cannot size the stack). The twin's 8+8 vertical padding mirrors
    /// TextEditor's own insets, so this height includes them.
    @State private var measuredH: CGFloat = 0

    /// iOS 15 only: the TextEditor's frame height — the measured height
    /// (text + insets), floored at 36 (one line + insets). The editor
    /// needs every point of it or its text is clipped.
    private var editorH: CGFloat { max(measuredH, 36) }

    /// iOS 15 only: the height this view reports to its parent — the pure
    /// text height, editorH minus the 16pt of editor insets. Upstream's
    /// iOS 16 vertical TextField reports just the text height, and the
    /// composer pill's row is bottom-aligned, so reporting the
    /// inset-inclusive editorH sank the + and send/stop buttons 16pt
    /// below centre on iOS 15. The editor keeps its full editorH frame
    /// inside this shorter slot and overflows it 8pt above and below;
    /// SwiftUI does not clip, so the text renders in full, centred on
    /// the slot — and the placeholder, positioned from the editor's
    /// frame origin as before, still coincides with the editor's text.
    private var slotH: CGFloat { editorH - 16 }

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
            // The stack is framed to slotH (editorH - 16), not editorH:
            // the layout height reported upward is the pure text height,
            // exactly what upstream's iOS 16 field reports, while the
            // editor keeps its editorH frame and overflows the slot
            // symmetrically (8pt each side, unclipped).
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .background(TextEditorBackgroundClearer())
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
            .frame(height: slotH)
        }
    }
}

/// [ios15-texteditor-bg] iOS 15 only: SwiftUI's TextEditor paints its
/// UITextView's default background (black in dark mode, white in light)
/// inside the composer pill, where upstream's field is transparent over
/// the pill's flat grey capsule — the iOS 16 vertical TextField has no
/// background, and upstream's own UIKit text view for the classic bar
/// sets backgroundColor = .clear explicitly (ChatInputBar.swift). There
/// is no scrollContentBackground on 15.
///
/// round32 walked this view's ancestor subtrees looking for the text
/// view and never reached it on device (build117: box unchanged) — the
/// background host and the editor do not share a shallow UIKit ancestor
/// in SwiftUI 15's TextEditor hierarchy. Frame matching is used instead:
/// a SwiftUI background fills its view's bounds exactly, so this view's
/// frame in window coordinates IS the editor's frame; the text view in
/// the window whose frame matches it is the editor, whatever the
/// hierarchy. Attempts retry briefly in case the editor joins the
/// window after this view's first update, and the outcome is logged
/// once per launch (category TextEditorBG) so a device log can prove
/// whether the clear landed.
private struct TextEditorBackgroundClearer: UIViewRepresentable {
    private static var didLogOutcome = false

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        scheduleClear(from: uiView, attempt: 0)
    }

    private func scheduleClear(from view: UIView, attempt: Int) {
        let delay: TimeInterval = attempt == 0 ? 0 : (attempt == 1 ? 0.1 : 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = view.window, view.bounds.width > 1 else {
                if attempt < 2 { scheduleClear(from: view, attempt: attempt + 1) }
                return
            }
            let target = view.convert(view.bounds, to: window)
            var cleared = false
            Self.forEachTextView(in: window) { textView in
                let frame = textView.convert(textView.bounds, to: window)
                let overlap = frame.intersection(target)
                guard !overlap.isNull,
                      overlap.width * overlap.height >= 0.8 * target.width * target.height,
                      frame.width <= target.width + 12,
                      frame.height <= target.height + 12 else { return }
                textView.backgroundColor = .clear
                cleared = true
            }
            if !cleared, attempt < 2 {
                scheduleClear(from: view, attempt: attempt + 1)
                return
            }
            if !Self.didLogOutcome {
                Self.didLogOutcome = true
                AppLogger(category: "TextEditorBG").info("[ios15-texteditor-bg] \(cleared ? "cleared editor background" : "NO MATCHING TEXT VIEW FOUND") target=\(Int(target.width))x\(Int(target.height)) attempts=\(attempt + 1)")
            }
        }
    }

    private static func forEachTextView(in view: UIView, visit: (UITextView) -> Void) {
        if let textView = view as? UITextView { visit(textView) }
        for subview in view.subviews {
            forEachTextView(in: subview, visit: visit)
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
