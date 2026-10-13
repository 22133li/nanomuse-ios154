import SwiftUI

struct OffloadPermissionDialogModifier: ViewModifier {
    @ObservedObject private var manager = OffloadPermissionManager.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $manager.pendingRequest) { request in
                OffloadPermissionDialogContent(request: request)
                    // Both detents — long arg lists were getting pushed below
                    // the medium detent's bottom edge with the Allow / Deny
                    // buttons trailing them, leaving no way to respond. Allow
                    // dragging up to .large; the content is scrollable in
                    // either height.
                    .interactiveDismissDisabled()
            }
    }
}

private struct OffloadPermissionDialogContent: View {
    let request: PermissionRequest
    /// "Remember this choice": when on, the decision is persisted as the
    /// command's permission level (.bypass on Allow, .notAllowed on Deny)
    /// instead of applying to this session only.
    @State private var rememberChoice = false

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content. Long argument lists previously stretched the
            // outer VStack past the sheet height and pushed the Allow / Deny
            // buttons below the bottom edge with no way to scroll to them.
            // Pinning the buttons in a separate sibling and wrapping the rest
            // in a ScrollView guarantees the action row is always visible.
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)

                        Text("Permission Request")
                            .font(.title3.bold())

                        Text("The agent wants to use **\(request.commandName)**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                    // Description
                    if !request.description.isEmpty {
                        Text(request.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    // Arguments
                    let args = request.parsedArguments
                    if !args.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(args.enumerated()), id: \.offset) { idx, arg in
                                HStack {
                                    Text(arg.key)
                                        .font(.footnote.bold())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .trailing)
                                    Text(arg.value)
                                        .font(.footnote.monospaced())
                                        .lineLimit(2)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                if idx < args.count - 1 {
                                    Divider().padding(.leading, 108)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
            }

            // Buttons — pinned to the bottom of the sheet, outside the
            // ScrollView, so they stay tappable even with very long arg lists.
            VStack(spacing: 10) {
                Toggle(isOn: $rememberChoice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("记住此选择")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        Text("Remember this choice for \(request.commandName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                .padding(.horizontal, 4)

                Button {
                    let manager = OffloadPermissionManager.shared
                    if rememberChoice {
                        manager.setPermissionLevel(.bypass, for: request.commandName)
                    }
                    manager.respond(to: request.id, allowed: true)
                } label: {
                    Text("Allow in Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    let manager = OffloadPermissionManager.shared
                    if rememberChoice {
                        manager.setPermissionLevel(.notAllowed, for: request.commandName)
                    }
                    manager.respond(to: request.id, allowed: false)
                } label: {
                    Text("Deny in Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
}

extension View {
    func offloadPermissionDialog() -> some View {
        modifier(OffloadPermissionDialogModifier())
    }
}
