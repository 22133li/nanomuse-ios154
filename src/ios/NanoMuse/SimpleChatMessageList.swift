// SimpleChatMessageList.swift
// iOS 15 fallback: the UICollectionView-based CollectionViewMessageListV3
// does not reliably update on iOS 15.4. This SwiftUI-native list is used
// on iOS 15 only. It shows basic text bubbles; advanced features (tool
// blocks, images, etc.) are not rendered here.

import SwiftUI

struct SimpleChatMessageList: View {
    @ObservedObject var vm: AIChatViewModel
    var onRetryMessage: (UUID) -> Void = { _ in }
    var onEdit: (UUID) -> Void = { _ in }
    var onDeleteFrom: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { message in
                        SimpleMessageRow(
                            message: message,
                            onRetryMessage: onRetryMessage,
                            onEdit: onEdit,
                            onDeleteFrom: onDeleteFrom
                        )
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.count) { _ in
                // Scroll to bottom when new messages arrive
                if let last = vm.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct SimpleMessageRow: View {
    @ObservedObject var message: ChatMessage
    var onRetryMessage: (UUID) -> Void = { _ in }
    var onEdit: (UUID) -> Void = { _ in }
    var onDeleteFrom: (UUID) -> Void = { _ in }

    /// Assistant messages carry their text in blocks, not content.
    private var displayText: String {
        if message.role == .user { return message.content }
        let blockText = message.blocks
            .filter { $0.kind == .text }
            .map { $0.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !blockText.isEmpty { return blockText }
        return message.content
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
                Text(verbatim: displayText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(18)
            } else {
                // Observe blocks so streaming text updates the row.
                BlocksObserver(blocks: message.blocks)
                SimpleMarkdownText(message: message, textWidth: 312)
                    .frame(width: 312, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(NanoMuseTones.agentPill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(maxWidth: 340, alignment: .leading)
                Spacer()
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = displayText
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            if message.role == .user {
                Button {
                    onEdit(message.id)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            } else {
                Button {
                    onRetryMessage(message.id)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                onDeleteFrom(message.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// Subscribes to each block's objectWillChange so the row refreshes as
/// assistant text streams in on iOS 15.
private struct BlocksObserver: View {
    var blocks: [AssistantBlock]
    var body: some View {
        ForEach(blocks) { block in
            BlockObserver(block: block)
        }
    }
}

private struct BlockObserver: View {
    @ObservedObject var block: AssistantBlock
    var body: some View { EmptyView() }
}

/// Renders an assistant message's text blocks using the already-cached
/// NSAttributedString from the view model (same renderer the main list
/// uses), inside a non-editable UITextView with explicit width so
/// SwiftUI's LazyVStack lays it out correctly on iOS 15.
private struct SimpleMarkdownText: UIViewRepresentable {
    @ObservedObject var message: ChatMessage
    var textWidth: CGFloat = 312

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let attr: NSAttributedString
        if message.role == .user {
            attr = NSAttributedString(string: message.content)
        } else {
            let parts = message.blocks
                .filter { $0.kind == .text }
                .map { $0.cachedAttributedString ?? NSAttributedString(string: $0.content) }
            let combined = NSMutableAttributedString()
            for (i, p) in parts.enumerated() {
                if i > 0 { combined.append(NSAttributedString(string: "\n\n")) }
                combined.append(p)
            }
            attr = combined.length > 0 ? combined : NSAttributedString(string: message.content)
        }
        if tv.attributedText == nil || !tv.attributedText.isEqual(to: attr) {
            tv.attributedText = attr
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let size = uiView.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: textWidth, height: size.height)
    }
}
