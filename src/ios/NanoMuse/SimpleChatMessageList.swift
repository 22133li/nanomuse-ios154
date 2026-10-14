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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                                isActiveMessage: message.id == vm.messages.last?.id && vm.isProcessing,
                                horizontalSizeClass: horizontalSizeClass
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
                    // Pin to bottom on new messages only when the user is
                    // already near the bottom (matches the full list's
                    // autoScrolling mode; a user scrolled up stays put).
                    guard isNearBottom, let last = vm.messages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                // Follow the view model's scroll signal (fired on streaming
                // text updates), gated on isNearBottom like the full list's
                // CollectionViewMessageListV3 subscription. Auto-scroll sets
                // the offset directly with no animation so rapid streaming
                // flushes don't jitter.
                .onReceive(vm.scrollToBottomSignal) { _ in
                    guard isNearBottom, let last = vm.messages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                // Feed the locally tracked scroll position back to the view
                // model: on iOS 15 the CollectionView list never runs, so
                // this is the only writer of vm.isNearBottom (it also drives
                // the header scrim, composer fade and floating buttons).
                .onChange(of: isNearBottom) { newValue in
                    if vm.isNearBottom != newValue {
                        vm.isNearBottom = newValue
                    }
                }

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
    var horizontalSizeClass: UserInterfaceSizeClass?
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

    /// Thinking blocks (shown as collapsible cards, simplified from
    /// the full ThinkingBlockView — no follow/freeze state machine).
    private var thinkingBlocks: [AssistantBlock] {
        message.blocks.filter { $0.kind == .thinking }
    }

    private var hasTextContent: Bool {
        !message.blocks.filter({ $0.kind == .text }).isEmpty || !message.content.isEmpty
    }

    /// Body text metrics matching MarkdownNSRenderer's base attributes
    /// (scaled 16.5pt base font, lineSpacing = 25% of size, label color),
    /// applied to the plain-text streaming fallback so streaming and
    /// completed rendering share line heights (no jump at completion).
    private static var streamingFallbackAttributes: [NSAttributedString.Key: Any] {
        let size = FontSettings.shared.scaledMessage(16.5)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = size * 0.25
        return [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]
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
            // (e.g. mid-stream), styled with the renderer's body metrics so
            // the switch to the fully-rendered string at completion doesn't
            // shift line heights.
            let nsStr = block.cachedAttributedString
                ?? NSAttributedString(string: block.content, attributes: Self.streamingFallbackAttributes)
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
                            .background(NanoMuseTones.ink)
                            .foregroundColor(NanoMuseTones.onInk)
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
                    // Thinking process (collapsible, simplified).
                    ForEach(thinkingBlocks) { block in
                        SimpleThinkingCard(block: block)
                    }
                    // Text bubble.
                    if hasTextContent {
                        Text(assistantAttributedString)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(NanoMuseTones.agentPill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .frame(maxWidth: NanoMuseColumn.agentPillWidth(for: horizontalSizeClass), alignment: .leading)
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
                        .foregroundStyle(NanoMuseTones.onInk.opacity(0.9))
                    Text(meta.fileName)
                        .font(.system(size: 13))
                        .foregroundStyle(NanoMuseTones.onInk)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NanoMuseTones.ink.opacity(0.7))
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
                        .foregroundStyle(NanoMuseTones.onInk.opacity(0.9))
                    Text(att.fileName)
                        .font(.system(size: 13))
                        .foregroundStyle(NanoMuseTones.onInk)
                        .lineLimit(1)
                    if att.loadState == .loading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NanoMuseTones.ink.opacity(0.7))
                .cornerRadius(10)
            }
        }
    }
}

/// Simplified thinking block for the iOS 15 message list.
/// Collapsible card showing the model's reasoning; simplified from the
/// full ThinkingBlockView (no drag-follow/freeze state machine).
private struct SimpleThinkingCard: View {
    @ObservedObject var block: AssistantBlock

    private var thinkingText: String {
        let buf = block.thinkingContentBuffer
        return buf.isEmpty ? block.content : buf
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                block.isThinkingExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13))
                        .foregroundStyle(.purple)
                    Text("思考过程")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: block.isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if block.isThinkingExpanded {
                Text(thinkingText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
