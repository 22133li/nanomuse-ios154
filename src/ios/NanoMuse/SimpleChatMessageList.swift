// SimpleChatMessageList.swift
// iOS 15 fallback: the UICollectionView-based CollectionViewMessageListV3
// does not reliably update on iOS 15.4. This SwiftUI-native list is used
// on iOS 15 only. It shows basic text bubbles; advanced features (tool
// blocks, images, etc.) are not rendered here.

import SwiftUI

struct SimpleChatMessageList: View {
    @ObservedObject var vm: AIChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { message in
                        SimpleMessageRow(message: message)
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
                Text(displayText)
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else {
                // Observe blocks so streaming text updates the row.
                BlocksObserver(blocks: message.blocks)
                Text(displayText)
                    .padding(10)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                Spacer()
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
