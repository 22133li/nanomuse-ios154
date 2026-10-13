// AIChatViewModifiers.swift
// Extracted from AIChatView.swift to keep the main view file within the
// Swift type-checker budget. Contains standalone ViewModifiers, sheets,
// and helper views used by AIChatView.

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

// MARK: - Composer Surface

/// Background + shadow for the composer's outer rounded container.
///
/// **[T-popup-white-patch 7a0e3d62] — the invariant both branches must keep.**
/// The fill is painted INSIDE a rounded shape, never as a rectangular
/// `.background(color)` + `.clipShape(...)` pair. With that older pairing the
/// host CALayer carried a rectangular backing colour which the system
/// text-selection / edit-menu pop animation snapshotted *before* SwiftUI's mask
/// applied, flashing a square of colour around the rounded corners mid-animation.
/// Filling the shape directly leaves the host layer's `backgroundColor` at
/// `.clear`, so the snapshot is already rounded. `clipShape` is still applied so
/// child views (text view, attachment grid) are clipped to the same rect.
///
/// `glassEffect(in:)` composites the material into the shape it is given, for
/// the same reason: it does not set a rectangular layer background, so it
/// preserves the invariant rather than reintroducing the bug. Verified on device
/// by long-pressing composer text to raise the edit menu — see the task notes.
///
/// The two hand-rolled shadows are dropped on the glass path (Liquid Glass
/// renders its own edge and shadow; stacking the old ones reads as a dark halo —
/// the same finding as the FAB conversion). The sub-26 branch keeps the original
/// fill and BOTH shadows byte-for-byte, including the dark-mode-only top shadow
/// that lifts the bar off the message list.
private struct ComposerSurface: ViewModifier {
    /// nanoMuse: Muse's pill in the shell — a flat grey capsule, no shadow (Android: MuseTones.bubble, 26 dp).
    var pill = false // nanoMuse:

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: pill ? 26 : 20, style: .continuous) // nanoMuse: 26 for the pill
    }

    func body(content: Content) -> some View {
        if pill { // nanoMuse:
            content // nanoMuse:
                .background(shape.fill(NanoMuseTones.bubble)) // nanoMuse:
                .clipShape(shape) // nanoMuse:
        } else {
            content
                .background(shape.fill(ChatColors.inputBg))
                .clipShape(shape)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
                .shadow(color: Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.5) : UIColor(white: 0, alpha: 0) }), radius: 8, x: 0, y: -4)
        }
    }
}

// MARK: - Provider Import Prompt

/// Presents the import-vs-attach choice for a shared/opened Provider-export
/// JSON, plus a result alert. Extracted from AIChatView.body so the (already
/// large) body's type-checker stays cheap. [T-ios-json-open-provider-import-prompt]
private struct ProviderImportPromptModifier: ViewModifier {
    @Binding var pending: AIChatView.PendingProviderImport?
    @Binding var result: String?
    /// Import the provider from JSON; returns the new instance label on success.
    let onImport: (String) -> String?
    /// Add the (temp-copied) file to the chat as an attachment.
    let onAttach: (URL) -> Void

    func body(content: Content) -> some View {
        content
            // [T-ios-provider-import-prompt-bottom-sheet] Use a real bottom
            // sheet, not .confirmationDialog. On iPad / regular width SwiftUI
            // renders .confirmationDialog (and a UIAlertController .actionSheet)
            // as a SOURCE-ANCHORED POPOVER; with no anchor it floats a centered
            // rounded card over the messages — the "not a system dialog" look
            // the user reported. A `.sheet` with detents is a genuine
            // bottom-pinned sheet on BOTH iPhone and iPad.
            .sheet(item: $pending) { item in
                ProviderImportSheet(
                    onImport: {
                        pending = nil
                        if let label = onImport(item.json) {
                            result = AppLocalized("Imported provider \"\(label)\".")
                        } else {
                            result = AppLocalized("Could not import this provider configuration.")
                        }
                        try? FileManager.default.removeItem(at: item.fileURL)
                    },
                    onAttach: {
                        pending = nil
                        onAttach(item.fileURL)
                    },
                    onCancel: {
                        try? FileManager.default.removeItem(at: item.fileURL)
                        pending = nil
                    }
                )
            }
            .alert(
                AppLocalized("Provider Import"),
                isPresented: Binding(
                    get: { result != nil },
                    set: { if !$0 { result = nil } }
                )
            ) {
                Button(AppLocalized("OK"), role: .cancel) { result = nil }
            } message: {
                Text(result ?? "")
            }
    }
}

// MARK: - Provider Import Bottom Sheet

/// Bottom sheet offering "Import as Provider" vs "Add as Chat Attachment" for a
/// shared/opened Provider-export JSON. A real sheet (not .confirmationDialog)
/// so it pins to the bottom on iPad too, instead of floating a centered popover
/// card. [T-ios-provider-import-prompt-bottom-sheet]
private struct ProviderImportSheet: View {
    let onImport: () -> Void
    let onAttach: () -> Void
    let onCancel: () -> Void

    /// Set once the user taps any explicit button, so the `.onDisappear`
    /// safety-cleanup only fires for a genuine swipe-to-dismiss (no choice).
    @State private var chose = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .padding(.top, 8)
                Text(AppLocalized("Provider Configuration Detected"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(AppLocalized("This JSON file looks like an exported provider configuration. Import it as a new provider, or add it to the chat as a file attachment?"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: { chose = true; onImport() }) {
                    Text(AppLocalized("Import as Provider"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { chose = true; onAttach() }) {
                    Text(AppLocalized("Add as Chat Attachment"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .cancel, action: { chose = true; onCancel() }) {
                    Text(AppLocalized("Cancel"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(24)
        // Swipe-to-dismiss without tapping a button still needs cleanup.
        .onDisappear { if !chose { onCancel() } }
    }
}

// MARK: - Swipe-to-Send Hint

/// Floating "send arrow + Release to send" hint shown while the user is
/// dragging the input bar upward. Extracted out of `inputBar` because
/// inlining `.overlay { HStack { … } .offset(…).animation(…) }` deepens
/// SwiftUI's already-fragile generic chain on `inputBar.body` and crashes
/// the runtime type-metadata decoder via deep recursion
/// (`swift_getTypeByMangledName...`). Keeping the overlay as a single named
/// struct lets the parent's generic signature collapse to one slot.
///
/// - `progress` 0...1: drag distance as a fraction of the send threshold.
///   Arrow opacity = `min(1, progress * 1.4)`. Capsule opacity ramps in
///   over `[0.4, 0.8]` so it reaches full opacity exactly at the arming
///   fraction (`kSendSwipeArmFraction = 0.8`), where the haptic tick
///   fires and lifting the finger sends.
/// - `armFraction`: the threshold at which release fires send. Drives the
///   spring "pop" animation so the visual confirmation matches behavior.
/// - `location`: live fingertip position in the input bar's coordinate
///   space. The hint sits ~60pt above the finger (about one thumb-tip).

// MARK: - Nav Bar Modifiers

private struct NavTitleFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // [NavTitleTopClip 2026-07-23] The principal titleView aligns to the
            // liquid-glass navbar's ~44pt band. Give it 46pt centered so tall
            // title glyphs (semibold 16pt + CJK/caps ascenders) render in full.
            //
            // [NavTitleTransitionClip 2026-07-23] Do NOT `.clipped()`. During a
            // push/pop transition the system interpolates the principal item's
            // frame/scale/alpha; a hard clip rectangle cuts the mid-transition
            // frames along the 46pt box far more aggressively than the steady
            // state (users saw the title sliced to half a line during the
            // animation). The 46pt frame only *sizes* the item for band
            // alignment — the 3-row stack's natural height already fits within
            // it at steady state (spacing -2, ~44pt), so there is nothing to clip
            // away, and letting transition frames render uncropped restores the
            // standard system title transition.
            content
                .frame(height: 46, alignment: .center)
        } else {
            content
        }
    }
}

private struct NavBarStyleModifier: ViewModifier {
    @Binding var topSafeAreaInset: CGFloat

    func body(content: Content) -> some View {
        // nanoMuse: in the Muse shell the header is a top safe-area inset the list scrolls under,
        // so the content must keep the container's top inset; the shell takes the lower branch.
        if #available(iOS 26, *), !NanoMuseShellPrefs.shell { // nanoMuse:
            // iOS 26: extend content behind nav bar so liquid-glass has
            // something to show through; the collection view's
            // contentInsetAdjustmentBehavior = .automatic keeps messages
            // starting below the bar.
            content
                .ignoresSafeArea(.container, edges: .top)
        } else {
            // iOS 16–18: opaque navbar background
            content
                // nanoMuse: side chats pushed from the shell float on a blur, as the main chat's header does
                .overlay(alignment: .top) {
                    // [T-ios-geometry-observer-crash] onGeometryChange replaces
                    // the GeometryReader scaffold (async-renderer SIGTRAP — see
                    // the floating-bar site). The proxy measures the same
                    // Color.clear the reader wrapped; ignoresSafeArea/frame
                    // stay outside it exactly as before, and the action's
                    // initial fire covers the old onAppear seed.
                    Color.clear
                        .onGeometryChangeBackport(for: CGFloat.self) { proxy in
                            proxy.safeAreaInsets.top
                        } action: { topSafeAreaInset = $0 }
                        .ignoresSafeArea()
                        .frame(height: 0)
                }
        }
    }
}


// MARK: - Chat Trailing "…" Menu

/// [T-ios-trailing-menu-streaming-stability] The chat page's "…" menu,
/// extracted from AIChatView into an Equatable child so an OPEN menu stays
/// stable during streaming. AIChatView.body re-evaluates on every streaming
/// tick (the whole view observes the view model); with the Menu declared
/// inline, each tick pushed rebuilt menu content into the presented UIMenu,
/// which could reshuffle/reset it right as the user tapped — the reported
/// mis-taps on menu items mid-stream.
///
/// `.equatable()` at the call site makes SwiftUI diff with `==` below, which
/// compares ONLY the values that change what the menu displays — none of
/// which mutate during a stream — so streaming ticks stop invalidating this
/// subtree entirely. Action closures are recreated by every parent body pass
/// but never change behavior, so they're deliberately excluded from `==`.
/// [T-ios-navbar-principal-streaming-stability] Generic value-keyed equatable
/// wrapper. SwiftUI skips re-evaluating `content` while `key` compares equal —
/// the same guard ChatTrailingMenu gets from its custom `==`, made reusable
/// for views (like the navbar titleView) that are too entangled with local
/// @State/onChange plumbing to extract wholesale. The content closure is
/// recreated every parent pass but is excluded from equality, exactly like
/// ChatTrailingMenu's action closures. Internal @State / onReceive updates
/// inside `content` still fire on their own — only parent-driven invalidation
/// is gated. Anything the content READS from the parent/vm must therefore be
/// represented in `key`, or its changes will not render.
#if DEBUG
/// [T-ios-navbar-principal-streaming-stability] Eval counters proving (or
/// disproving) that the toolbar equatable gates actually hold during
/// streaming. toolbarPass ≈ one per streaming tick (counted in navTitleKey,
/// which the toolbar builder computes every pass); titleEval / menuEval
/// should stay ~1 while a stream runs IF the gates work. Grep: [NavbarEval].
enum NavbarEvalStats {
    static var toolbarPass = 0
    static var titleEval = 0
    static var menuEval = 0
    static let logger = AppLogger(category: "NavbarEval")
}
#endif

private struct EquatableByValue<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    @ViewBuilder let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.titleEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] titleEval=\(NavbarEvalStats.titleEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        content()
    }
}

/// [T-ios-navbar-principal-streaming-stability] Every display input the navbar
/// principal titleView renders, snapshotted as an Equatable key. While this is
/// unchanged (the entire streaming case), SwiftUI proves the principal toolbar
/// item unchanged and does NOT re-push the navigation bar's item set — which
/// was what kept rebuilding the OPEN "..." UIMenu each token even after
/// 59b31441 equatable-guarded the trailing menu itself: the guard covered the
/// trailing subtree, but the un-guarded principal item invalidated the whole
/// bar every tick, and UIKit refreshes the presented menu when bar items are
/// re-set (items shifting under the user's finger → mis-taps).
private struct NavTitleKey: Equatable {
    let sessionTitle: String?
    let canEditTitle: Bool
    let soulName: String
    let modelName: String
    let isGroupBound: Bool
    /// [T-codex-fast-mode] Circular ⚡ badge before the model name while
    /// Fast Mode is enabled on a Codex OAuth model.
    let showFastBolt: Bool
    let resolvedText: String?
    let hasBinding: Bool
    let hasProviders: Bool
    let showThinkingBadge: Bool
    let thinkingLevelName: String
    let fallbackTrigger: Int
    /// The fallback-pulse @State lives on AIChatView but is RENDERED inside
    /// the gated titleView — each discrete set (6 over ~1.75s) must pierce
    /// the gate or the red pulse freezes at its first frame.
    let fallbackPulse: Double
    /// [T-ios-navtitle-blur-stuck-after-unlock] Face ID lock state — the
    /// title's `.blur(radius: titleIsVisuallyLocked ? 8 : 0)` renders inside
    /// the gated toolbar content, so the unlock transition must pierce the
    /// gate too. Without this field the chat body unblurred on unlock while
    /// the navbar title stayed frozen at blur 8 (user report 2026-07-24).
    let titleLocked: Bool
}

/// [T-ios-navbar-toolbar-host] Combined display key for the WHOLE toolbar:
/// the principal title's inputs plus the trailing menu's eight displayed
/// values. While this is unchanged, ChatToolbarHost.body — and therefore the
/// ToolbarContent builder — never re-runs.
private struct ChatToolbarKey: Equatable {
    let navTitle: NavTitleKey
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Menu row shown only for Codex OAuth models.
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool
}

/// [T-ios-navbar-toolbar-host] Zero-footprint host that owns the navigation
/// toolbar. Attached via .background on the chat content, so it sits inside
/// the NavigationStack destination (toolbar registers from any descendant),
/// occupies no layout, and — being Equatable on the toolbar's displayed
/// inputs — its body (the ToolbarContent builder) only re-runs when something
/// the toolbar actually shows changes. Streaming ticks leave the key equal,
/// the builder never re-runs, the bridge gets no new ToolbarContent to push,
/// and the OPEN native SwiftUI Menu stays untouched. Content closures are
/// recreated by every parent pass (excluded from ==, same pattern as
/// EquatableByValue/ChatTrailingMenu) so a key change always renders through
/// the freshest parent state.
private struct ChatToolbarHost<Title: View, Trailing: View>: View, Equatable {
    let key: ChatToolbarKey
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing

    static func == (lhs: Self, rhs: Self) -> Bool {
        let eq = lhs.key == rhs.key
        #if DEBUG
        if !eq {
            // Name the exact field that broke equality so a false-negative
            // key can be pinned from device logs.
            var diffs: [String] = []
            if lhs.key.navTitle != rhs.key.navTitle {
                let l = lhs.key.navTitle, r = rhs.key.navTitle
                if l.sessionTitle != r.sessionTitle { diffs.append("sessionTitle") }
                if l.canEditTitle != r.canEditTitle { diffs.append("canEditTitle") }
                if l.soulName != r.soulName { diffs.append("soulName") }
                if l.modelName != r.modelName { diffs.append("modelName") }
                if l.isGroupBound != r.isGroupBound { diffs.append("isGroupBound") }
                if l.resolvedText != r.resolvedText { diffs.append("resolvedText") }
                if l.hasBinding != r.hasBinding { diffs.append("hasBinding") }
                if l.hasProviders != r.hasProviders { diffs.append("hasProviders") }
                if l.showThinkingBadge != r.showThinkingBadge { diffs.append("showThinkingBadge") }
                if l.thinkingLevelName != r.thinkingLevelName { diffs.append("thinkingLevelName") }
                if l.fallbackTrigger != r.fallbackTrigger { diffs.append("fallbackTrigger") }
                if l.fallbackPulse != r.fallbackPulse { diffs.append("fallbackPulse") }
                if l.titleLocked != r.titleLocked { diffs.append("titleLocked") }
            }
            if lhs.key.messagesEmpty != rhs.key.messagesEmpty { diffs.append("messagesEmpty") }
            if lhs.key.hasSession != rhs.key.hasSession { diffs.append("hasSession") }
            if lhs.key.isForcePulling != rhs.key.isForcePulling { diffs.append("isForcePulling") }
            if lhs.key.iCloudSyncEnabled != rhs.key.iCloudSyncEnabled { diffs.append("iCloudSyncEnabled") }
            if lhs.key.memoryEnabled != rhs.key.memoryEnabled { diffs.append("memoryEnabled") }
            if lhs.key.speakEnabled != rhs.key.speakEnabled { diffs.append("speakEnabled") }
            if lhs.key.showEnhancedCacheToggle != rhs.key.showEnhancedCacheToggle { diffs.append("showEnhancedCacheToggle") }
            if lhs.key.enhancedCacheEnabled != rhs.key.enhancedCacheEnabled { diffs.append("enhancedCacheEnabled") }
            if lhs.key.showFastModeToggle != rhs.key.showFastModeToggle { diffs.append("showFastModeToggle") }
            if lhs.key.fastModeEnabled != rhs.key.fastModeEnabled { diffs.append("fastModeEnabled") }
            NavbarEvalStats.logger.info("[NavbarEval] host == FALSE diffs=[\(diffs.joined(separator: ","))]")
        }
        #endif
        return eq
    }

    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.titleEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] toolbarHostEval=\(NavbarEvalStats.titleEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .toolbar {
                ToolbarItem(placement: .principal) { title() }
                ToolbarItem(placement: .topBarTrailing) { trailing() }
            }
    }
}

/// [T-ios-navbar-uikit-menu] UIKit-owned replacement for ChatTrailingMenu.
///
/// Instrumented device run (NavbarEval, 2026-07-17 19:35): during a streaming
/// reply the toolbar builder ran 34 times while BOTH equatable gates held
/// (titleEval=3, menuEval=2) — yet the presented menu still refreshed. The
/// leak is below SwiftUI: the toolbar bridge re-pushes the navigation item's
/// bar buttons every host pass even when the content views compare equal, and
/// UIKit refreshes/re-anchors a presented UIMenu whenever its bar's items are
/// re-set. No amount of view-level Equatable can stop that.
///
/// Fix: own the button AND the menu in UIKit. The UIViewRepresentable's
/// UIButton instance survives SwiftUI updates, the presented UIMenu is
/// anchored to that stable instance, and updateUIView only touches
/// `button.menu` when the DISPLAYED state actually changed — a no-op SwiftUI
/// pass physically cannot reach the menu. Field names/order are identical to
/// ChatTrailingMenu so the call site only swaps the type name. The DEBUG
/// request-count rows use UIDeferredMenuElement.uncached to stay fresh at
/// each open, matching the SwiftUI Menu's lazy content read.
/// [T-ios-navbar-toolbar-host] Native SwiftUI "..." menu, restored. The
/// UIKit ChatTrailingMenuButton below remains as the proven fallback (it
/// verifiably stops the mid-stream refresh but loses the system's round
/// Liquid-Glass chrome); with the toolbar now hosted in the equatable-gated
/// ChatToolbarHost the ToolbarContent is never rebuilt during streaming, so
/// the native Menu — and its native appearance — should be stable. Item set
/// mirrors the UIKit buildMenu exactly (incl. Compact Messages + the divider
/// between Clear Chat and the iCloud actions from T-chat-menu-compact-entry).
private struct ChatTrailingMenu: View, Equatable {
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Mirrors ChatTrailingMenuButton.
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool

    let onNewChat: () -> Void
    let onCompact: () -> Void
    let onClearChat: () -> Void
    let onForceSync: () -> Void
    let onForcePull: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenBrowser: () -> Void
    let onBrowseFiles: () -> Void
    let onSkills: () -> Void
    let onMCPs: () -> Void
    let onMemories: () -> Void
    let setSpeakEnabled: (Bool) -> Void
    let setEnhancedCache: (Bool) -> Void
    let setFastMode: (Bool) -> Void
    let onTokenUsage: () -> Void
    let onCopyRequests: () -> Void
    let onCopySessionData: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messagesEmpty == rhs.messagesEmpty
            && lhs.hasSession == rhs.hasSession
            && lhs.isForcePulling == rhs.isForcePulling
            && lhs.iCloudSyncEnabled == rhs.iCloudSyncEnabled
            && lhs.memoryEnabled == rhs.memoryEnabled
            && lhs.speakEnabled == rhs.speakEnabled
            && lhs.showEnhancedCacheToggle == rhs.showEnhancedCacheToggle
            && lhs.enhancedCacheEnabled == rhs.enhancedCacheEnabled
            && lhs.showFastModeToggle == rhs.showFastModeToggle
            && lhs.fastModeEnabled == rhs.fastModeEnabled
    }

    var body: some View {
        #if DEBUG
        let _ = {
            NavbarEvalStats.menuEval += 1
            NavbarEvalStats.logger.info("[NavbarEval] menuEval=\(NavbarEvalStats.menuEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        }()
        #endif
        return Menu {
            Button { onNewChat() } label: {
                Label(AppLocalized("New Chat"), systemImage: "square.and.pencil")
            }

            Divider()

            // [T-chat-menu-compact-entry] Compact above Clear Chat.
            Button { onCompact() } label: {
                Label(AppLocalized("Compact Messages"), systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(messagesEmpty)

            Button(role: .destructive) { onClearChat() } label: {
                Label(AppLocalized("Clear Chat"), systemImage: "trash")
            }
            .disabled(messagesEmpty)

            Divider()

            // iCloud sync actions: iOS 17+ (v2 sync engine) AND the user's
            // iCloud Sync toggle on.
            if #available(iOS 17.0, *), iCloudSyncEnabled {
                Button { onForceSync() } label: {
                    Label(AppLocalized("Force iCloud Sync"), systemImage: "icloud.and.arrow.up")
                }
                .disabled(!hasSession || isForcePulling)

                Button { onForcePull() } label: {
                    Label(AppLocalized("Force Pull Messages"), systemImage: "icloud.and.arrow.down")
                }
                .disabled(!hasSession || isForcePulling)

                Divider()
            }

            Button { onOpenTerminal() } label: {
                Label(AppLocalized("Open Terminal"), systemImage: "terminal")
            }

            Button { onOpenBrowser() } label: {
                Label(AppLocalized("Open Browser"), systemImage: "globe")
            }

            Button { onBrowseFiles() } label: {
                Label(AppLocalized("Browse Chat Files"), systemImage: "folder")
            }

            Divider()

            Button { onSkills() } label: {
                Label(AppLocalized("Skills in Session"), systemImage: "puzzlepiece.extension")
            }

            Button { onMCPs() } label: {
                Label(AppLocalized("MCPs in Session"), systemImage: "wrench.and.screwdriver")
            }

            if memoryEnabled {
                Button { onMemories() } label: {
                    Label(AppLocalized("Memories in Session"), systemImage: "brain.head.profile")
                }
            }

            Toggle(isOn: Binding(
                get: { speakEnabled },
                set: { setSpeakEnabled($0) }
            )) {
                Label(AppLocalized("Speak Responses"), systemImage: "speaker.wave.2")
            }

            // [T-codex-fast-mode-menu-group] Model-control toggles in their
            // own divider-separated section (mirrors the UIKit buildMenu).
            if showEnhancedCacheToggle || showFastModeToggle {
                Divider()

                if showEnhancedCacheToggle {
                    Toggle(isOn: Binding(
                        get: { enhancedCacheEnabled },
                        set: { setEnhancedCache($0) }
                    )) {
                        Label(AppLocalized("Enhanced Cache"), systemImage: "clock.arrow.circlepath")
                    }
                }

                if showFastModeToggle {
                    Toggle(isOn: Binding(
                        get: { fastModeEnabled },
                        set: { setFastMode($0) }
                    )) {
                        Label(AppLocalized("Enable Fast Mode"), systemImage: "bolt.fill")
                    }
                }
            }

            Divider()

            Button { onTokenUsage() } label: {
                Label(AppLocalized("Token Usage"), systemImage: "number")
            }

            #if DEBUG
            Divider()

            Button { onCopyRequests() } label: {
                let n = LastAPIRequestBody.shared.getAll().count
                Label("Copy Requests (\(n))", systemImage: "arrow.up.doc")
            }

            Button { onCopySessionData() } label: {
                Label("Copy Session Data", systemImage: "tray.and.arrow.up")
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ChatColors.primaryText)
        }
        // [T-ios-voiceover-labels] Matches the label the UIKit ellipsis button
        // elsewhere in this file already sets, so both read the same.
        .accessibilityLabel(Text("More options", comment: "VoiceOver label for the overflow menu button"))
    }
}

/// [T-ios-navbar-uikit-menu] PROVEN FALLBACK, currently unused: swaps in for
/// ChatTrailingMenu at the trailingMenu call site if the ChatToolbarHost
/// approach ever regresses. Verified on-device (2026-07-17) to stop the
/// mid-stream menu refresh; its remaining flaw was appearance (no native
/// round glass chrome — mitigated here by sizeThatFits reporting the
/// button's intrinsic size so the system container wraps it like a plain
/// toolbar icon).
private struct ChatTrailingMenuButton: UIViewRepresentable {
    let messagesEmpty: Bool
    let hasSession: Bool
    let isForcePulling: Bool
    let iCloudSyncEnabled: Bool
    let memoryEnabled: Bool
    let speakEnabled: Bool
    let showEnhancedCacheToggle: Bool
    let enhancedCacheEnabled: Bool
    /// [T-codex-fast-mode] Shown only when the active model's provider is a
    /// Codex OAuth instance (OpenAI OAuth, no custom base).
    let showFastModeToggle: Bool
    let fastModeEnabled: Bool

    let onNewChat: () -> Void
    let onCompact: () -> Void
    let onClearChat: () -> Void
    let onForceSync: () -> Void
    let onForcePull: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenBrowser: () -> Void
    let onBrowseFiles: () -> Void
    let onSkills: () -> Void
    let onMCPs: () -> Void
    let onMemories: () -> Void
    let setSpeakEnabled: (Bool) -> Void
    let setEnhancedCache: (Bool) -> Void
    let setFastMode: (Bool) -> Void
    let onTokenUsage: () -> Void
    let onCopyRequests: () -> Void
    let onCopySessionData: () -> Void

    /// The displayed-state snapshot — the ONLY trigger for a menu rebuild.
    struct Key: Equatable {
        let messagesEmpty: Bool
        let hasSession: Bool
        let isForcePulling: Bool
        let iCloudSyncEnabled: Bool
        let memoryEnabled: Bool
        let speakEnabled: Bool
        let showEnhancedCacheToggle: Bool
        let enhancedCacheEnabled: Bool
        let showFastModeToggle: Bool
        let fastModeEnabled: Bool
    }

    private var key: Key {
        Key(messagesEmpty: messagesEmpty, hasSession: hasSession,
            isForcePulling: isForcePulling, iCloudSyncEnabled: iCloudSyncEnabled,
            memoryEnabled: memoryEnabled, speakEnabled: speakEnabled,
            showEnhancedCacheToggle: showEnhancedCacheToggle,
            enhancedCacheEnabled: enhancedCacheEnabled,
            showFastModeToggle: showFastModeToggle,
            fastModeEnabled: fastModeEnabled)
    }

    final class Coordinator {
        var lastKey: Key?
        var parent: ChatTrailingMenuButton
        init(parent: ChatTrailingMenuButton) { self.parent = parent }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: cfg), for: .normal)
        button.tintColor = UIColor(ChatColors.primaryText)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = AppLocalized("More options")
        button.menu = Self.buildMenu(key: key, coordinator: context.coordinator)
        context.coordinator.lastKey = key
        return button
    }

    /// Report the button's intrinsic size so the toolbar proposes an
    /// icon-sized footprint and the system wraps it in the same round glass
    /// as a plain toolbar icon (a representable otherwise accepts the full
    /// proposed width -> stretched capsule, the 2026-07-17 regression).
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }

    func updateUIView(_ button: UIButton, context: Context) {
        // Closures capture view state -- refresh them every pass so actions
        // always see the latest values (excluded from the rebuild decision,
        // exactly like ChatTrailingMenu's ==).
        context.coordinator.parent = self
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        button.menu = Self.buildMenu(key: key, coordinator: context.coordinator)
        #if DEBUG
        NavbarEvalStats.menuEval += 1
        NavbarEvalStats.logger.info("[NavbarEval] uikitMenuRebuild=\(NavbarEvalStats.menuEval) (toolbarPass=\(NavbarEvalStats.toolbarPass))")
        #endif
    }

    private static func buildMenu(key: Key, coordinator: Coordinator) -> UIMenu {
        var groups: [UIMenuElement] = []

        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("New Chat"),
                     image: UIImage(systemName: "square.and.pencil")) { _ in coordinator.parent.onNewChat() },
        ]))

        // [T-chat-menu-compact-entry] Compact sits ABOVE Clear Chat in its own
        // group with the destructive clear; the iCloud actions moved to a
        // separate inline group so a divider lands between Clear Chat and the
        // sync rows (user-requested layout).
        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("Compact Messages"),
                     image: UIImage(systemName: "arrow.down.right.and.arrow.up.left"),
                     attributes: key.messagesEmpty ? [.disabled] : []) { _ in coordinator.parent.onCompact() },
            UIAction(title: AppLocalized("Clear Chat"),
                     image: UIImage(systemName: "trash"),
                     attributes: key.messagesEmpty ? [.destructive, .disabled] : [.destructive]) { _ in coordinator.parent.onClearChat() },
        ]))

        // Same gate as before: iOS 17+ (v2 sync engine) AND the user's
        // iCloud Sync toggle on.
        if #available(iOS 17.0, *), key.iCloudSyncEnabled {
            let disabled: UIMenuElement.Attributes = (!key.hasSession || key.isForcePulling) ? [.disabled] : []
            groups.append(UIMenu(options: .displayInline, children: [
                UIAction(title: AppLocalized("Force iCloud Sync"),
                         image: UIImage(systemName: "icloud.and.arrow.up"),
                         attributes: disabled) { _ in coordinator.parent.onForceSync() },
                UIAction(title: AppLocalized("Force Pull Messages"),
                         image: UIImage(systemName: "icloud.and.arrow.down"),
                         attributes: disabled) { _ in coordinator.parent.onForcePull() },
            ]))
        }

        groups.append(UIMenu(options: .displayInline, children: [
            UIAction(title: AppLocalized("Open Terminal"),
                     image: UIImage(systemName: "terminal")) { _ in coordinator.parent.onOpenTerminal() },
            UIAction(title: AppLocalized("Open Browser"),
                     image: UIImage(systemName: "globe")) { _ in coordinator.parent.onOpenBrowser() },
            UIAction(title: AppLocalized("Browse Chat Files"),
                     image: UIImage(systemName: "folder")) { _ in coordinator.parent.onBrowseFiles() },
        ]))

        var sessionGroup: [UIMenuElement] = [
            UIAction(title: AppLocalized("Skills in Session"),
                     image: UIImage(systemName: "puzzlepiece.extension")) { _ in coordinator.parent.onSkills() },
            UIAction(title: AppLocalized("MCPs in Session"),
                     image: UIImage(systemName: "wrench.and.screwdriver")) { _ in coordinator.parent.onMCPs() },
        ]
        if key.memoryEnabled {
            sessionGroup.append(UIAction(title: AppLocalized("Memories in Session"),
                                         image: UIImage(systemName: "brain.head.profile")) { _ in coordinator.parent.onMemories() })
        }
        sessionGroup.append(UIAction(title: AppLocalized("Speak Responses"),
                                     image: UIImage(systemName: "speaker.wave.2"),
                                     state: key.speakEnabled ? .on : .off) { _ in
            coordinator.parent.setSpeakEnabled(!key.speakEnabled)
        })
        groups.append(UIMenu(options: .displayInline, children: sessionGroup))

        // [T-codex-fast-mode-menu-group] Model-control toggles (they shape how
        // the MODEL is invoked, unlike the session-scoped rows above) live in
        // their own inline group so dividers separate them on both sides.
        var modelControlGroup: [UIMenuElement] = []
        if key.showEnhancedCacheToggle {
            modelControlGroup.append(UIAction(title: AppLocalized("Enhanced Cache"),
                                              image: UIImage(systemName: "clock.arrow.circlepath"),
                                              state: key.enhancedCacheEnabled ? .on : .off) { _ in
                coordinator.parent.setEnhancedCache(!key.enhancedCacheEnabled)
            })
        }
        // [T-codex-fast-mode] Only for Codex OAuth models. Injects
        // service_tier=priority (the wire value codex_cli_rs sends for its
        // Fast mode) into Codex requests while enabled; 2x credit burn.
        if key.showFastModeToggle {
            modelControlGroup.append(UIAction(title: AppLocalized("Enable Fast Mode"),
                                              image: UIImage(systemName: "bolt.fill"),
                                              state: key.fastModeEnabled ? .on : .off) { _ in
                coordinator.parent.setFastMode(!key.fastModeEnabled)
            })
        }
        if !modelControlGroup.isEmpty {
            groups.append(UIMenu(options: .displayInline, children: modelControlGroup))
        }

        var tailGroup: [UIMenuElement] = [
            UIAction(title: AppLocalized("Token Usage"),
                     image: UIImage(systemName: "number")) { _ in coordinator.parent.onTokenUsage() },
        ]
        #if DEBUG
        tailGroup.append(UIDeferredMenuElement.uncached { completion in
            let n = LastAPIRequestBody.shared.getAll().count
            completion([
                UIAction(title: "Copy Requests (\(n))",
                         image: UIImage(systemName: "arrow.up.doc")) { _ in coordinator.parent.onCopyRequests() },
                UIAction(title: "Copy Session Data",
                         image: UIImage(systemName: "tray.and.arrow.up")) { _ in coordinator.parent.onCopySessionData() },
            ])
        })
        #endif
        groups.append(UIMenu(options: .displayInline, children: tailGroup))

        return UIMenu(children: groups)
    }
}


// MARK: - Move To Session Sheet

private struct MoveToSessionSheet: View {
    let currentSessionId: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSession] = []
    @State private var searchText = ""
    @State private var searchMatchedIds: Set<String>?
    @State private var searchTask: Task<Void, Never>?

    /// Prefix used by ContentView for draft session IDs.
    private static let newSessionPrefix = "__new__"

    private var isSearching: Bool { !searchText.isEmpty }

    private var displayedSessions: [ChatSession] {
        let filtered = sessions.filter { $0.id != currentSessionId }
        guard let matchedIds = searchMatchedIds else { return filtered }
        return filtered.filter { matchedIds.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            List {
                if !isSearching {
                    Button {
                        let newId = "\(Self.newSessionPrefix)\(UUID().uuidString)"
                        dismiss()
                        onSelect(newId)
                    } label: {
                        Label(AppLocalized("New Chat"), systemImage: "plus.bubble")
                    }
                }

                Section(isSearching ? AppLocalized("Results") : AppLocalized("Recent")) {
                    ForEach(displayedSessions) { session in
                        Button {
                            dismiss()
                            onSelect(session.id)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    highlightedText(
                                        session.title ?? AppLocalized("New Chat"),
                                        font: .system(size: 16, weight: .semibold),
                                        color: Color(UIColor.label)
                                    )
                                    .lineLimit(1)
                                    highlightedText(
                                        session.lastMessage ?? AppLocalized("No messages yet"),
                                        font: .system(size: 14),
                                        color: Color(UIColor.secondaryLabel)
                                    )
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 1)
                                Text(relativeDate(session.updatedAt))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(UIColor.tertiaryLabel))
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: AppLocalized("Search chats..."))
            .onChange(of: searchText) { _ in scheduleSearch() }
            .navigationTitle(AppLocalized("Move to…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                }
            }
        }
        .task {
            sessions = NanoMuseSync.shared.visible(await ChatStore.shared.listSessions()) // nanoMuse: C12 — another account's chats stay hidden
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchMatchedIds = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = await ChatStore.shared.searchSessions(query: query)
            if !Task.isCancelled {
                searchMatchedIds = Set(results.map(\.session.id))
            }
        }
    }

    // MARK: - Highlight

    @ViewBuilder
    private func highlightedText(_ text: String, font: Font, color: Color) -> some View {
        if isSearching, let query = Optional(searchText.trimmingCharacters(in: .whitespaces)),
           !query.isEmpty, text.range(of: query, options: .caseInsensitive) != nil {
            buildHighlighted(text, query: query, font: font, color: color)
        } else {
            Text(text).font(font).foregroundStyle(color)
        }
    }

    private func buildHighlighted(_ text: String, query: String, font: Font, color: Color) -> Text {
        let lower = text.lowercased()
        let lowerQ = query.lowercased()
        var result = Text("")
        var current = text.startIndex

        while current < text.endIndex,
              let range = lower.range(of: lowerQ, range: current..<lower.endIndex) {
            if current < range.lowerBound {
                result = result + Text(text[current..<range.lowerBound])
                    .font(font).foregroundColor(color)
            }
            result = result + Text(text[range])
                .font(font).foregroundColor(.accentColor).bold()
            current = range.upperBound
        }
        if current < text.endIndex {
            result = result + Text(text[current..<text.endIndex])
                .font(font).foregroundColor(color)
        }
        return result
    }

    // MARK: - Relative Date

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let seconds = Int(now.timeIntervalSince(date))
        if calendar.isDateInToday(date) {
            if seconds < 60 {
                return AppLocalized("Just now")
            } else if seconds < 3600 {
                let mins = seconds / 60
                return "\(mins) min ago"
            } else {
                let hrs = seconds / 3600
                return "\(hrs) hr ago"
            }
        } else if calendar.isDateInYesterday(date) {
            return AppLocalized("Yesterday")
        } else {
            let diff = calendar.dateComponents([.day], from: date, to: now)
            if let days = diff.day, days < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - UIView helpers

private extension UIView {
    /// Walk the responder chain to find the nearest UIViewController.
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

// MARK: - Face ID Session Lock Overlay
//
// Encapsulates the entire Face ID gate (state + overlay UI + lifecycle
// observers) into a self-contained `View` so that AIChatView's body
// only references it as a single opaque type. This keeps the chat
// body's generic-type depth bounded — earlier inlined attempts pushed
// `__swift_instantiateConcreteTypeFromMangledNameV2` into runtime
// metadata recursion and crashed with EXC_BAD_ACCESS at the stack
// guard region on iOS 26.
private struct SessionLockGateOverlay: View {
    let sessionId: String?

    @ObservedObject private var store = SessionLockStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// True while an LAContext prompt is in flight — suppresses repeated
    /// auto-prompts when the system overlay itself transiently resigns
    /// the chat view.
    @State private var promptInFlight = false
    /// Set after a failed / cancelled prompt so the overlay renders a
    /// tap-to-retry affordance instead of immediately re-prompting.
    @State private var attemptFailed = false

    var body: some View {
        Group {
            if shouldShow {
                gateView
            }
        }
        .onAppear { evaluate(reason: "onAppear") }
        .onDisappear {
            // [T-faceid-lock-on-exit 2026-05-21] "Lock on exit" mode
            // (idleTimeoutSeconds < 0): clear this session's unlock as
            // soon as the chat view leaves the screen (user popped back
            // to the sidebar / pushed a settings page / navigated to
            // another session). Without this, the unlock stamp survives
            // until the app backgrounds, which doesn't match the user's
            // intent of "locking the moment I leave this chat".
            //
            // Positive idle windows are NOT cleared here — they keep
            // the stamp so navigating away and back within the window
            // doesn't re-prompt for Face ID.
            if let sid = sessionId, store.isLocked(sid), store.idleTimeoutSeconds < 0 {
                store.clearUnlock(sid)
                attemptFailed = false
            }
        }
        .onChange(of: scenePhase) { newPhase in
            handleScene(newPhase)
        }
        .onChange(of: sessionId) { _ in
            attemptFailed = false
            promptInFlight = false
            evaluate(reason: "sessionIdChanged")
        }
    }

    private var shouldShow: Bool {
        guard let sid = sessionId, !sid.isEmpty else { return false }
        return store.isVisuallyLocked(sid)
    }

    private var gateView: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .overlay {
                    Color(UIColor.systemBackground).opacity(0.4)
                        .ignoresSafeArea()
                }

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                Text("This session is locked")
                    .font(.system(size: 18, weight: .semibold))

                Text(attemptFailed
                     ? "Authentication failed. Tap to try again."
                     : "Tap to unlock with \(BiometricAuth.biometryDisplayName)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    promptForBiometricUnlock()
                } label: {
                    Label(attemptFailed
                          ? AppLocalized("Try again")
                          : AppLocalized("Unlock"),
                          systemImage: "faceid")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { promptForBiometricUnlock() }
        .transition(.opacity)
    }

    private func evaluate(reason: String) {
        guard let sid = sessionId, !sid.isEmpty else { return }
        guard store.globalEnabled, BiometricAuth.isAvailable else { return }
        guard store.isLocked(sid) else { return }
        store.relockIfIdleExpired(sid)
        guard !store.isCurrentlyUnlocked(sid) else { return }
        guard !promptInFlight, !attemptFailed else { return }
        promptForBiometricUnlock()
    }

    private func promptForBiometricUnlock() {
        guard let sid = sessionId, !sid.isEmpty else { return }
        guard !promptInFlight else { return }
        promptInFlight = true
        Task { @MainActor in
            let reason = AppLocalized("Unlock this chat session")
            let ok = await BiometricAuth.authenticate(reason: reason)
            promptInFlight = false
            if ok {
                store.noteUnlock(sid)
                attemptFailed = false
            } else {
                attemptFailed = true
            }
        }
    }

    private func handleScene(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            // [T-faceid-lock-background-timeout 2026-05-21] Previously
            // cleared the per-session unlock stamp unconditionally on
            // background/inactive, which made the idle timeout setting
            // (e.g. "10 minutes") behave as if it were "Lock on exit":
            // any backgrounding instantly re-locked the chat. Honor the
            // user's chosen idle window now — only clear the unlock if
            // they explicitly chose "Lock on exit" (idle < 0). For
            // positive idle values the stamp is kept and re-evaluated
            // on .active via evictIdleExpired() + evaluate().
            if let sid = sessionId, store.isLocked(sid) {
                if store.idleTimeoutSeconds < 0 {
                    store.clearUnlock(sid)
                }
                attemptFailed = false
            }
        case .active:
            store.evictIdleExpired()
            evaluate(reason: "scenePhase.active")
        @unknown default:
            break
        }
    }
}

// MARK: - Mic Button (touch-release activation)

/// Mic button that triggers on touch-release (finger lift) to avoid accidental activation.
/// Press highlight is provided via GestureState.
private struct MicButton: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Binding var inputFocused: Bool
    /// Opens the voice-input (VAD) panel. The mic button no longer drives the
    /// in-bar SFSpeech live dictation directly — the panel (with the configured
    /// ASR provider, or the offline System fallback) is the single voice entry
    /// point. The SpeechRecognitionManager path stays in place but is no longer
    /// triggered from here.
    var onTap: () -> Void = {}
    /// True while inline voice mode is active — the button flips to a "T" glyph
    /// that switches back to text input.
    var isVoiceActive: Bool = false
    /// Press feedback for the custom-gesture button.
    @State private var micPressed = false

    private static let diameter: CGFloat = 34

    var body: some View {
        // NOT a Button: SwiftUI's Button has a generous system touch-slop / touch-
        // up tolerance that fires when the finger lifts slightly outside, or moves
        // a little during a scroll/drag — which made this toggle very easy to
        // mis-tap. We use a DragGesture(minimumDistance: 0) and only activate when
        // BOTH the press and release land inside the circle AND movement is tiny.
        // In voice mode: a keyboard glyph = switch back to text input. The keyboard
        // glyph is wider than the mic, so render it ~4pt smaller for parity.
        Image(systemName: isVoiceActive ? "keyboard" : "mic")
            .font(.system(size: isVoiceActive ? 15 : 18, weight: .medium))
            .foregroundStyle(ChatColors.secondaryText)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(ChatColors.inputIconBg)
            .clipShape(Circle())
            .overlay(Circle().stroke(ChatColors.inputIconBorder, lineWidth: 0.5))
            .scaleEffect(micPressed ? 0.9 : 1.0)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        micPressed = Self.isInside(value.location)
                    }
                    .onEnded { value in
                        let started = Self.isInside(value.startLocation)
                        let ended = Self.isInside(value.location)
                        let moved = hypot(value.translation.width, value.translation.height)
                        micPressed = false
                        guard started, ended, moved < 10 else { return }
                        inputFocused = false
                        onTap()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isVoiceActive
                ? Text("Switch to text input", comment: "Mic button exits voice mode")
                : Text("Voice input", comment: "Mic button opens voice panel"))
    }

    /// Whether a point (in the button's local space) is within the visible circle.
    private static func isInside(_ p: CGPoint) -> Bool {
        let r = diameter / 2
        let dx = p.x - r, dy = p.y - r
        return (dx * dx + dy * dy) <= r * r
    }
}

// MARK: - Speech Language Picker Sheet

private struct SpeechLanguagePickerSheet: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLocales: [Locale] {
        if searchText.isEmpty { return speechManager.availableLocales }
        let query = searchText.lowercased()
        return speechManager.availableLocales.filter { loc in
            let name = speechManager.displayName(for: loc).lowercased()
            let id = loc.identifier.lowercased()
            return name.contains(query) || id.contains(query)
        }
    }

    /// Indices where the preferred/non-preferred boundary lies for section headers.
    private var preferredCodes: Set<String> {
        Set(Locale.preferredLanguages.map { Locale(identifier: $0).languageCode ?? "" })
    }

    var body: some View {
        NavigationView {
            List {
                let preferred = filteredLocales.filter { preferredCodes.contains($0.languageCode ?? "") }
                let others = filteredLocales.filter { !preferredCodes.contains($0.languageCode ?? "") }

                if !preferred.isEmpty {
                    Section(AppLocalized("Preferred", comment: "Section header for preferred speech languages")) {
                        ForEach(preferred, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    }
                }

                if !others.isEmpty {
                    Section(AppLocalized("All Languages", comment: "Section header for all speech languages")) {
                        ForEach(others, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text("Search Languages", comment: "Search field placeholder for speech language picker"))
            .navigationTitle(Text("Voice Language", comment: "Navigation title for speech language picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Done", comment: "Dismiss speech language picker")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func languageRow(_ loc: Locale) -> some View {
        Button {
            speechManager.setLanguage(loc)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(speechManager.displayName(for: loc))
                        .foregroundStyle(.primary)
                    Text(loc.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if loc.identifier == speechManager.locale.identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        
                }
            }
        }
    }
}

