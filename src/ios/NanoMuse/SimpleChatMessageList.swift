// SimpleChatMessageList.swift
// iOS 15 fallback: the UICollectionView-based CollectionViewMessageListV3
// does not reliably update on iOS 15.4. This SwiftUI-native list is used
// on iOS 15 only. It renders text bubbles, tool step capsules (with status),
// thinking cards, info notices, images and attachments — simplified from
// the full list but behavior-aligned with upstream.

import SwiftUI

struct SimpleChatMessageList: View {
    @ObservedObject var vm: AIChatViewModel
    var onRetryMessage: (UUID) -> Void = { _ in }
    var onEdit: (UUID) -> Void = { _ in }
    var onDeleteFrom: (UUID) -> Void = { _ in }
    /// Bottom inset for the composer (input bar) height, so the last message
    /// isn't blocked by the composer overlay. Matches CollectionView's inputBarHeight.
    var bottomInset: CGFloat = 0
    /// Browser tab pool for ToolLiveSheet browser previews (matches upstream).
    var browserPool: BrowserTabPool?
    /// Tool snapshots for ToolLiveSheet (matches upstream).
    var toolSnapshots: [ToolSnapshotItem] = []
    // Upstream callbacks (match CollectionViewMessageListV3's interface).
    var onRetryLast: () -> Void = {}
    var onOpenSoulSettings: () -> Void = {}
    var onWithdraw: (UUID) -> Void = { _ in }
    var onResume: () -> Void = {}
    var onStop: () -> Void = {}
    var onCompact: (UUID) -> Void = { _ in }
    var onRevertCompact: () -> Void = {}
    var onForceSync: () -> Void = {}
    var onScreenshotImage: (UIImage) -> Void = { _ in }

    @State private var isNearBottom: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// nanoMuse: iOS 15 equivalent of CollectionViewMessageListV3's `topOverlay` — the shell's Muse
    /// header floats over the list's top edge. NOTE: The shell already places the header as a
    /// top safe-area inset (NanoMuseShell), so the ScrollView starts below the header naturally.
    /// We do NOT add an additional inset here — that would double-count and push messages too far down.
    @Environment(\.nmTopOverlay) private var nmTopOverlay
    /// Tool detail sheet state. Held at the list level (not the row) — matches upstream
    /// CollectionViewMessageListV3 which presents ToolLiveSheet from a VC-level presenter.
    /// Attaching .sheet to a LazyVStack row on iOS 15 renders as a small floating black
    /// box overlapping messages instead of a full sheet.
    @State private var detailBlock: AssistantBlock?
    @State private var detailMessage: ChatMessage?

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
                                onWithdraw: onWithdraw,
                                isActiveMessage: message.id == vm.messages.last?.id && vm.isProcessing,
                                horizontalSizeClass: horizontalSizeClass,
                                onToolTap: { block in
                                    detailMessage = message
                                    detailBlock = block
                                }
                            )
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
                    // Bottom padding so the last message isn't blocked by the composer.
                    // Upstream formula: inputBarHeight + floatingBarHeight + 8
                    // = nmColumnHeight + nmBottomOverlay + 8 (floatingBarHeight=0).
                    // iOS 15 fallback: the async geometry measurement can stay 0,
                    // so enforce a source-derived minimum:
                    // NanoMuseBottomBar.height (70pt, from source: 46+6*2+12)
                    // + iPhone 13 Pro Max bottom safe area (34pt, home indicator)
                    // + minimum composer input bar (50pt) + 8 (upstream) = 162.
                    // User requested 180pt minimum for extra clearance.
                    .padding(.bottom, max(bottomInset + 8, 180))
                }
                .onChange(of: vm.messages.count) { _ in
                    // Pin to bottom on new messages.
                    // - User's own message: ALWAYS scroll (user expects to see what they just sent).
                    // - Assistant message: only when already near bottom (matches the full list's
                    //   autoScrolling mode; a user scrolled up to read history stays put).
                    // The old code gated both on isNearBottom, so sending a message while
                    // slightly scrolled up left the new message hidden below the fold.
                    guard let last = vm.messages.last else { return }
                    let isUserMessage = last.role == .user
                    guard isUserMessage || isNearBottom else { return }
                    // Dispatch async: scrollTo during a view update (e.g. a
                    // very fast reply arriving mid-render) can crash.
                    DispatchQueue.main.async {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                // Follow the view model's scroll signal (fired on streaming
                // text updates), gated on isNearBottom like the full list's
                // CollectionViewMessageListV3 subscription. Auto-scroll sets
                // the offset directly with no animation so rapid streaming
                // flushes don't jitter.
                .onReceive(vm.scrollToBottomSignal) { _ in
                    guard isNearBottom, let last = vm.messages.last else { return }
                    // Dispatch async to avoid crashing when the signal fires
                    // during an in-flight view update (fast reply race).
                    DispatchQueue.main.async {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
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
                // NOTE: Floating scroll buttons are provided by AIChatView's
                // overlay (same as iOS 16+); SimpleChatMessageList does not
                // define its own to avoid duplication.
            }
            // Tool detail sheet, presented from the list level (not the row).
            // Matches upstream CollectionViewMessageListV3's VC-level sheet presenter.
            // Attaching .sheet to a LazyVStack row on iOS 15 renders as a small
            // floating black box overlapping messages instead of a full sheet.
            .sheet(item: $detailBlock) { block in
                if let message = detailMessage {
                    ToolLiveSheet(
                        toolBlocks: message.blocks.filter { $0.toolStatus != nil },
                        initialIdx: message.blocks.filter({ $0.toolStatus != nil }).firstIndex(where: { $0.id == block.id }) ?? 0,
                        toolSnapshots: toolSnapshots,
                        browserPool: browserPool
                    )
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
    var onWithdraw: (UUID) -> Void = { _ in }
    var isActiveMessage: Bool = false
    var horizontalSizeClass: UserInterfaceSizeClass?
    var onToolTap: (AssistantBlock) -> Void = { _ in }
    @AppStorage(NanoMuseSteps.key) private var showSteps: Bool = NanoMuseSteps.defaultValue
    // iOS 15: ForEach rows with @ObservedObject don't reliably refresh when
    // blocks are appended (placeholder -> streaming text). Toggle this on
    // objectWillChange to force the row to re-evaluate without changing IDs
    // (which would break ScrollViewReader scroll targets).
    @State private var refreshToken = false

    /// Assistant messages carry their text in blocks, not content.
    private var displayText: String {
        if message.role == .user { return message.content }
        let blockText = message.blocks
            .filter { $0.kind == .text }
            .map { $0.content }
            .joined(separator: "\n\n")
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

    /// Info blocks (model downgrade notices, e.g. "⚠️ ... Switched to X").
    /// Simplified from AssistantBlockView's .info rendering.
    private var infoBlocks: [AssistantBlock] {
        message.blocks.filter { $0.kind == .info }
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
                    // Typing indicator — "request out, nothing back yet".
                    // Shows when the user sends a message and we're waiting
                    // for the first token. Matches the full list's
                    // showsTypingIndicator (bridge.isActiveMessage &&
                    // message.shouldShowTypingIndicator).
                    if isActiveMessage && message.shouldShowTypingIndicator {
                        TypingIndicator()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(NanoMuseTones.agentPill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .frame(maxWidth: NanoMuseColumn.agentPillWidth(for: horizontalSizeClass), alignment: .leading)
                    }
                    // Tool step capsules (agent's steps), like Android.
                    ForEach(visibleToolBlocks) { block in
                        SimpleToolCapsule(block: block, onTap: { onToolTap(block) }, onStop: { onStop() })
                    }
                    // Thinking process (collapsible, simplified).
                    ForEach(thinkingBlocks) { block in
                        SimpleThinkingCard(block: block)
                    }
                    // Info notices (model downgrade, etc.), simplified.
                    ForEach(infoBlocks) { block in
                        SimpleInfoCard(block: block)
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
                Label(AppLocalized("Copy All"), systemImage: "doc.on.doc")
            }
            Button {
                // Copy Markdown: same text content (already markdown source).
                UIPasteboard.general.string = displayText
            } label: {
                Label(AppLocalized("Copy Markdown"), systemImage: "text.quote")
            }
            if message.role == .user {
                Button {
                    onEdit(message.id)
                } label: {
                    Label(AppLocalized("Edit"), systemImage: "pencil")
                }
                // Withdraw queued messages (matches upstream).
                if message.isQueued {
                    Button(role: .destructive) {
                        onWithdraw(message.id)
                    } label: {
                        Label(AppLocalized("Withdraw"), systemImage: "arrow.uturn.backward")
                    }
                }
            } else {
                Button {
                    onRetryMessage(message.id)
                } label: {
                    Label(AppLocalized("Retry"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                onDeleteFrom(message.id)
            } label: {
                Label(AppLocalized("Delete"), systemImage: "trash")
            }
        }
        .onReceive(message.objectWillChange) { _ in
            // iOS 15: force row re-evaluation when blocks stream in.
            refreshToken.toggle()
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
    var onTap: () -> Void = {}
    var onStop: (() -> Void)? = nil

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

    /// Status-based icon color, matching upstream ToolCapsuleView.iconColor.
    private var statusColor: Color {
        switch block.toolStatus {
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .yellow
        default: return accentColor
        }
    }

    private var isActive: Bool {
        switch block.toolStatus {
        case .streaming, .running: return true
        default: return false
        }
    }

    private var durationText: String? {
        guard let dur = block.toolDuration else { return nil }
        if dur < 1 { return String(format: "%.1fs", dur) }
        if dur < 60 { return String(format: "%.0fs", dur) }
        let mins = Int(dur) / 60
        let secs = Int(dur) % 60
        return "\(mins)m \(secs)s"
    }

    private var displayText: String {
        if let summary = block.toolSummary, !summary.isEmpty {
            return summary
        }
        return block.toolDescription
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator: spinner while active, status-colored icon otherwise.
            if isActive {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor)
            }
            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            // Execution duration after completion (matches upstream).
            if let dur = durationText, !isActive {
                Text(dur)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            // Stop button for running commands (matches upstream).
            if case .running = block.toolStatus, let onStop {
                Button {
                    onStop()
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .padding(-3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(UIColor.systemGray6))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            onTap()
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

/// Simplified info block for the iOS 15 message list.
/// Renders model downgrade notices (e.g. "⚠️ ... Switched to X"),
/// simplified from AssistantBlockView's .info case.
private struct SimpleInfoCard: View {
    @ObservedObject var block: AssistantBlock

    private var reasonLines: [String] {
        let allLines = block.content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let reasons = allLines.filter { $0.hasPrefix("⚠️") }
        // Truncate middle if more than 9 reason lines (matches upstream)
        if reasons.count <= 9 { return reasons }
        return Array(reasons.prefix(4)) + ["⋯ \(reasons.count - 8) more"] + Array(reasons.suffix(4))
    }

    private var switchedLine: String? {
        let allLines = block.content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return allLines.first { !$0.hasPrefix("⚠️") && !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(reasonLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineLimit(2)
            }
            if let switched = switchedLine {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.8))
                    Text(switched)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(AppLocalized("Thinking"))
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
