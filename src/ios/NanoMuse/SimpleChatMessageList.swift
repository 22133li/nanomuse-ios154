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

    @State private var isNearBottom: Bool = true

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages) { message in
                            SimpleMessageRow(
                                message: message,
                                onRetryMessage: onRetryMessage,
                                onEdit: onEdit,
                                onDeleteFrom: onDeleteFrom,
                                isActiveMessage: message.id == vm.messages.last?.id && vm.isProcessing
                            )
                                .id(message.id)
                        }
                        // Bottom anchor for scroll tracking
                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor")
                            .onAppear { isNearBottom = true }
                            .onDisappear { isNearBottom = false }
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
                .background(
                    // Stick to bottom while tokens stream into the last
                    // assistant message. The full list only fires its
                    // scrollToBottomSignal when isNearBottom; mirror that
                    // here so reading history isn't yanked back down.
                    Group {
                        if vm.isProcessing,
                           let last = vm.messages.last,
                           last.role == .assistant {
                            StreamScrollTrigger(message: last) {
                                if isNearBottom {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                )

                // Floating scroll buttons (like Android and the full iOS list)
                if !vm.messages.isEmpty && !isNearBottom {
                    VStack(spacing: 10) {
                        Button {
                            withAnimation {
                                proxy.scrollTo(vm.messages.first?.id, anchor: .top)
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                                .background(Color(UIColor.systemGray6))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        Button {
                            withAnimation {
                                proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                                .background(Color(UIColor.systemGray6))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
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
    var isActiveMessage: Bool = false
    @AppStorage(NanoMuseSteps.key) private var showSteps: Bool = NanoMuseSteps.defaultValue
    /// Tool block tapped for input/output inspection (mirrors the full
    /// list's detailBlock -> ToolLiveSheet presentation).
    @State private var detailBlock: AssistantBlock?

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

    /// Tool blocks to show as step capsules, respecting the
    /// "Show the agent's steps" setting (like the full message list).
    private var visibleToolBlocks: [AssistantBlock] {
        message.blocks.filter { block in
            !NanoMuseSteps.hidden(block.kind, active: isActiveMessage, showSteps: showSteps)
        }.filter { block in
            switch block.kind {
            case .shellTool, .fileReadTool, .fileWriteTool, .fileEditTool,
                 .browserTool, .readImageTool, .memoryTool:
                return true
            case .text, .thinking, .info:
                return false
            }
        }
    }

    private var hasTextContent: Bool {
        !message.blocks.filter({ $0.kind == .text }).isEmpty || !message.content.isEmpty
    }

    /// Convert the view model's cached NSAttributedString (rendered by the
    /// upstream MarkdownNSRenderer) to SwiftUI AttributedString. This
    /// preserves all formatting (bold, lists, paragraphs) without needing
    /// a UITextView, so SwiftUI handles wrapping natively.
    private var assistantAttributedString: AttributedString {
        let textBlocks = message.blocks.filter { $0.kind == .text }
        if textBlocks.isEmpty {
            return AttributedString(displayText)
        }
        var combined = AttributedString()
        for (i, block) in textBlocks.enumerated() {
            if i > 0 {
                combined += AttributedString("\n\n")
            }
            // Fall back to raw content while the renderer hasn't cached yet
            // (e.g. mid-stream), matching the upstream SelectableMarkdownView path.
            let nsStr = block.cachedAttributedString ?? NSAttributedString(string: block.content)
            combined += AttributedString(nsStr)
        }
        return combined
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 6) {
                    // Attachments above the text bubble (like the full list)
                    if !message.attachments.isEmpty {
                        SimpleAttachmentList(attachments: message.attachments)
                    } else if !message.inputAttachments.isEmpty {
                        SimpleInputAttachmentList(attachments: message.inputAttachments)
                    }
                    if !displayText.isEmpty {
                        Text(verbatim: displayText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(18)
                    }
                }
            } else {
                // Observe blocks so streaming text updates the row.
                BlocksObserver(blocks: message.blocks)
                VStack(alignment: .leading, spacing: 8) {
                    // Tool step capsules (agent's steps), like Android.
                    ForEach(visibleToolBlocks) { block in
                        SimpleToolCapsule(block: block, detailBlock: $detailBlock)
                    }
                    // Text bubble.
                    if hasTextContent {
                        Text(assistantAttributedString)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(NanoMuseTones.agentPill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .frame(maxWidth: 340, alignment: .leading)
                    }
                }
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
        .sheet(item: $detailBlock) { block in
            ToolLiveSheet(
                toolBlocks: message.blocks.filter { $0.toolStatus != nil },
                initialIdx: message.blocks.filter({ $0.toolStatus != nil }).firstIndex(where: { $0.id == block.id }) ?? 0,
                browserPool: nil
            )
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

/// Simplified tool step capsule for the iOS 15 message list.
/// Mirrors ToolCapsuleView's appearance (icon + description in a pill).
/// Tapping opens the same ToolLiveSheet detail as the full list.
private struct SimpleToolCapsule: View {
    @ObservedObject var block: AssistantBlock
    @Binding var detailBlock: AssistantBlock?

    private var icon: String {
        switch block.kind {
        case .shellTool: return "terminal"
        case .fileReadTool: return "doc.text"
        case .fileWriteTool: return "doc.text.fill"
        case .fileEditTool: return "square.and.pencil"
        case .browserTool: return "globe"
        case .readImageTool: return "photo"
        case .memoryTool: return "brain.head.profile"
        case .text, .thinking, .info: return "circle"
        }
    }

    private var accentColor: Color {
        switch block.kind {
        case .shellTool: return .green
        case .fileReadTool: return .cyan
        case .fileWriteTool: return .blue
        case .fileEditTool: return .orange
        case .browserTool: return .blue
        case .readImageTool: return .purple
        case .memoryTool: return .pink
        case .text, .thinking, .info: return .gray
        }
    }

    private var displayText: String {
        if let summary = block.toolSummary, !summary.isEmpty {
            return summary
        }
        return block.toolDescription
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(accentColor)
            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(UIColor.systemGray6))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            detailBlock = block
        }
    }
}

/// Fires `onStreamUpdate` whenever a block of `message` changes (tokens
/// streaming in), so the iOS 15 list can stick to bottom mid-message.
private struct StreamScrollTrigger: View {
    @ObservedObject var message: ChatMessage
    var onStreamUpdate: () -> Void

    var body: some View {
        ForEach(message.blocks) { block in
            BlockScrollObserver(block: block, onUpdate: onStreamUpdate)
        }
    }
}

private struct BlockScrollObserver: View {
    @ObservedObject var block: AssistantBlock
    var onUpdate: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: block.content) { _ in
                onUpdate()
            }
    }
}

/// Simplified attachment tiles for the iOS 15 message list.
/// Shows file chips (icon + name) instead of the full thumbnail tiles.
private struct SimpleAttachmentList: View {
    let attachments: [AttachmentMeta]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(attachments) { meta in
                HStack(spacing: 8) {
                    Image(systemName: meta.isImage ? "photo" : (meta.isVideo ? "video" : "doc"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(meta.fileName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.7))
                .cornerRadius(10)
            }
        }
    }
}

/// Queued (not yet uploaded) attachments preview.
private struct SimpleInputAttachmentList: View {
    let attachments: [InputAttachment]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(attachments) { att in
                HStack(spacing: 8) {
                    Image(systemName: att.kind == .image ? "photo" : (att.kind == .video ? "video" : "doc"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(att.fileName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    if att.loadState == .loading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.7))
                .cornerRadius(10)
            }
        }
    }
}
