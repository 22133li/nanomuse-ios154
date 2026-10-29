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
            // modifiers -- sets the stack height, so the editor grows line
            // by line up to the cap and scrolls internally past it. The
            // twin's padding mirrors TextEditor's own insets (8pt vertical,
            // 5pt line-fragment padding) so the two heights agree.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                Text(measureText)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 5)
                    .opacity(0)
                    .allowsHitTesting(false)
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
