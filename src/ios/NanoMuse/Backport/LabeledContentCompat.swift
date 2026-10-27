import SwiftUI

// iOS 15 backport: `LabeledContent` is iOS 16+.
//
// On iOS 16 and later this renders the system `LabeledContent` unchanged, so
// supported systems keep the official layout, Form row behaviour and
// accessibility semantics. iOS 15 gets the same label/value pairing as a
// plain row, which is the closest equivalent the older SDK offers.
struct NanoMuseLabeledContent<Content: View, Label: View>: View {
    private let content: Content
    private let label: Label

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent {
                content
            } label: {
                label
            }
        } else {
            HStack {
                label
                Spacer()
                content
            }
        }
    }
}

extension NanoMuseLabeledContent where Label == Text {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(LocalizedStringKey(label)) }
    }
}

extension NanoMuseLabeledContent where Label == Text, Content == Text {
    init(_ label: String, value: String) {
        self.init(content: { Text(value) }, label: { Text(LocalizedStringKey(label)) })
    }
}
