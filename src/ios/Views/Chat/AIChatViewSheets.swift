// AIChatViewSheets.swift
// Extracted from AIChatView.swift to keep the main view file within the
// Swift type-checker budget. Contains standalone sheet views and helpers
// used by AIChatView.

import AVFoundation
import AVKit
import Combine
import GameController
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Compact Summary Sheet

struct CompactSummarySheet: View {
    let summary: String
    /// Optional revert action. When provided, a "Revert Compact" button is shown
    /// below the summary; tapping it invokes the closure (typically wired to
    /// AIChatViewModel.revertCompact()) and dismisses the sheet.
    var onRevert: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showRevertConfirm = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SelectableTextView(text: summary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                if onRevert != nil {
                    Divider()
                    Button(role: .destructive) {
                        showRevertConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Revert Compact")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Compact Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = summary
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                }
            }
            .alert("Revert this compact?", isPresented: $showRevertConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) {
                    let action = onRevert
                    dismiss()
                    action?()
                }
            } message: {
                Text("The summary will be discarded and the messages it covered will become active again. This may push the conversation past the model's context window — if that happens, long-press a message to re-compact from that point.")
            }
        }
    }
}

/// UITextView wrapper for efficient rendering of long selectable text.
private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.showsVerticalScrollIndicator = true
        tv.alwaysBounceVertical = true
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }
}

// MARK: - Token Usage Sheet

private struct TokenUsageSheet: View {
    @ObservedObject var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                let s = vm.sessionTokenStats

                Section("Context") {
                    StatRow(label: "Context Used", value: formatted(s.context), icon: "text.alignleft")
                    if let window = vm.currentModelContextWindow {
                        StatRow(label: "Context Window", value: formatted(window), icon: "arrow.left.and.right")
                    }
                    if let maxOut = vm.currentModelMaxOutputTokens {
                        StatRow(label: "Max Output", value: formatted(maxOut), icon: "arrow.up.to.line")
                    }
                }

                if let thinkingInfo = vm.currentModelThinkingInfo {
                    Section("Thinking") {
                        StatRow(label: "Thinking", value: thinkingInfo.enabled ? "On" : "Off", icon: "lightbulb", customIcon: Image("ThinkingIcon"))
                        if thinkingInfo.enabled {
                            StatRow(label: "Level", value: thinkingInfo.level, icon: "slider.horizontal.3")
                        }
                        StatRow(label: "Supported", value: thinkingInfo.supported ? "Yes" : "No", icon: "checkmark.circle")
                    }
                }

                Section("Tokens (Session Total)") {
                    let inputTotal = s.input + s.cacheRead + s.cacheWrite
                    StatRow(label: "Input (incl. cache)", value: formatted(inputTotal), icon: "arrow.down.circle")
                    StatRow(label: "Output", value: formatted(s.output), icon: "arrow.up.circle")
                }

                Section("Cache (Session Total)") {
                    StatRow(label: "Cache Read", value: formatted(s.cacheRead), icon: "arrow.triangle.2.circlepath")
                    StatRow(label: "Cache Write", value: formatted(s.cacheWrite), icon: "square.and.arrow.down")
                    // [T-ios-token-usage-cache-hit-rate] Cache hit rate = cache read
                    // over total input (incl. cache) — the same denominator as the
                    // "Input (incl. cache)" row above (input + cacheRead + cacheWrite).
                    // Shows how much of this session's input was served from cache.
                    let totalInput = s.input + s.cacheRead + s.cacheWrite
                    if totalInput > 0 && s.cacheRead > 0 {
                        let hitRate = Double(s.cacheRead) / Double(totalInput) * 100
                        StatRow(label: "Cache Hit Rate", value: String(format: "%.1f%%", hitRate), icon: "percent")
                    }
                }

                Section("Speed") {
                    let speed = vm.sessionOutputTokensPerSecond
                    StatRow(label: "Output Speed", value: speed > 0 ? String(format: "%.1f tok/s", speed) : "—", icon: "speedometer")
                }

                Section("Agent Loop") {
                    StatRow(label: "Total Loops", value: "\(s.loopCount)", icon: "repeat")
                }
            }
            .navigationTitle("Session Token Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String
    var customIcon: Image?

    var body: some View {
        HStack {
            if let customIcon {
                Label {
                    Text(label)
                } icon: {
                    customIcon
                        .resizable()
                        .frame(width: 14, height: 14)
                }
            } else {
                Label(label, systemImage: icon)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Empty Chat Directory Timeline

/// Onboarding view rendered in the center of a New Chat (no messages yet).
/// Shows the per-session vs cross-session directory layout under
/// `/var/minis/` as a 2-column folder grid so the user understands what's
/// available before typing.
///
/// Source-of-truth for the descriptions: AIChatViewModel.swift system-prompt
/// directory listing (`Shared directory /var/minis/ ...`). Keep them aligned
/// when either side changes.
private struct EmptyChatDirectoryTimeline: View {
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChatColors.secondaryText)
                Text("Workspace layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChatColors.secondaryText)
            }
            Text("Each chat gets its own **workspace**, **attachments**, **offloads**, and **browser** folders — wiped when the session ends.")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("All chats share **shared**, **skills**, **memory**, and **mounts** — persistent across sessions.")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: onBrowse) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Browse Chat Files")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(ChatColors.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(ChatColors.secondaryBg)
                    )
                    .overlay(
                        Capsule().stroke(ChatColors.toolBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ChatColors.secondaryBg.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ChatColors.toolBorder, lineWidth: 0.5)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}


// MARK: - Session Loading Card

/// Three-dot carousel indicator: dots pulse in a staggered wave. The single
/// loading language for the session-entry path (loading card, in-place reload,
/// kernel boot) — replaces every system ProgressView spinner there, so the
/// old "菊花" never appears after / alongside the new loading UI.
struct LoadingDotsView: View {
    var dotSize: CGFloat = 10
    var color: Color = .accentColor
    @State private var animating = false

    var body: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 0.95 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

/// Loading placeholder shown while ENTERING a session whose messages haven't
/// loaded yet — replaces the bare system spinner for that first-open moment
/// (black screen → lone spinner → content snap). Just the bare three-dot
/// carousel, centered — no card container or label (visual-simplification
/// feedback: the rounded material box + "Loading conversation…" text read as
/// too heavy). The container's transition fades/scales it out when loading
/// completes. Reload paths with content on screen never show this — see the
/// isLoadingSession overlay in AIChatView.
private struct SessionLoadingCard: View {
    var body: some View {
        LoadingDotsView(dotSize: 8)
            .frame(height: 24)
    }
}

/// [voice-correction §6] Build the conversation context for a correction: the last user
/// message and the agent reply that followed it.
///
/// Reads the in-memory `messages` the chat is already rendering — §12.1 explicitly forbids
/// a DB query here, since this runs on the correction path. Both halves are truncated by
/// `ConversationContextTruncator` (500-char soft cap, extended to the next sentence
/// terminator so a quoted fragment never ends mid-sentence).
///
/// This is what lets correction work on a FRESH INSTALL. With both learned tables empty and
/// no context, the prompt has no evidence at all and the model correctly refuses to change
/// anything — which is exactly why the suggestion icon never appeared on a new device.
func voiceCorrectionContext(from messages: [ChatMessage]) -> ConversationContext {
    // Budgeted builder (2026-07-16): sentence-split + segment + rarity-rank the
    // recent turns, expanding the message count under a 5k-char budget, instead
    // of the original "last user + reply, first 500 chars each". §12.1 still
    // holds — this reads only the in-memory messages the chat is rendering.
    // Only real conversation turns feed the context. compactDivider and
    // systemInfo rows would otherwise be classified as "assistant" and leak
    // UI copy into the rare-terms digest.
    let source = messages
        .filter { $0.role == .user || $0.role == .assistant }
        .map { msg -> CorrectionSourceMessage in
            // Assistant turns keep their prose in `blocks` (text blocks), not
            // in `content` — reading only `content` silently dropped every AI
            // reply from the correction context. `content` can also hold a
            // stale FRAGMENT alongside full blocks (observed: a 34-char title
            // while the reply lived in blocks), so for assistant turns the
            // text blocks are the source of truth and `content` is only the
            // fallback. Tool/thinking/info blocks stay out — their payloads
            // are commands and traces, not conversational vocabulary.
            var text = msg.content
            if msg.role == .assistant, !msg.blocks.isEmpty {
                let blockText = msg.blocks
                    .filter { $0.kind == .text }
                    .map(\.content)
                    .joined(separator: "\n")
                if !blockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = blockText
                }
            }
            return CorrectionSourceMessage(role: msg.role == .user ? .user : .assistant,
                                           text: TypedVocabularyBuilder.stripAttachmentMarkup(text))
        }
    return CorrectionContextBuilder.build(messages: source)
}

/// [T-browser-download-ux-v2] Sheet item for "Show in Files" from the
/// downloads panel: opens the file browser rooted at the session workspace
/// and highlights this filename.
struct DownloadLocateTarget: Identifiable {
    let filename: String
    var id: String { filename }
}
