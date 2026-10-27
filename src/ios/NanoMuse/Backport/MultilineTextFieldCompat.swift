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

    var body: some View {
        if #available(iOS 16.0, *) {
            if let range = axisVerticalLineLimit {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(range)
            } else {
                TextField(placeholder, text: $text, axis: .vertical)
            }
        } else {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: 36)
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color(UIColor.placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
