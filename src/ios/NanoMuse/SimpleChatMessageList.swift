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

    /// Render markdown to AttributedString; fall back to plain text.
    private var displayAttr: AttributedString {
        if let attr = try? AttributedString(markdown: displayText) {
            return attr
        }
        return AttributedString(displayText)
    }

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
                Spacer()
                Text(displayAttr)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else {
                // Observe blocks so streaming text updates the row.
                BlocksObserver(blocks: message.blocks)
                Text(displayAttr)
                    .padding(10)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
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
