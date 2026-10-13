//
//  NanoMuseMemory.swift
//  nanoMuse
//
//  The Memory tab, Muse style: the diary timeline (all days, newest first),
//  SOUL.md / GLOBAL.md editors, search across entries, and entry delete.
//  Memory used to live only in the chat's "Memories in Session" popup and the
//  system file browser; this is the standalone page.
//  Android: ui/memory/*.
//

import Foundation
import SwiftUI

// MARK: - Model

/// One entry inside a `YYYY-MM-DD.md` daily log: a `<!-- timestamp -->`
/// marker plus the body up to the next marker (or EOF). Same marker format
/// as MemoryWriteRevoker.
struct NanoMuseDiaryEntry: Identifiable, Equatable {
    let id = UUID()
    /// "2026-10-13" — the log file's day.
    let day: String
    /// "2026-10-13 14:30:05" — from the entry's marker.
    let timestamp: String
    let body: String
    let fileURL: URL

    /// First non-empty line, for list previews.
    var preview: String {
        body.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }

    static func == (lhs: NanoMuseDiaryEntry, rhs: NanoMuseDiaryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// A top-level memory file (SOUL.md / GLOBAL.md) opened in the editor.
struct NanoMuseMemoryFile: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let url: URL
}

// MARK: - Store

/// Loads every `YYYY-MM-DD.md` daily log from the memory dir and parses its
/// entries. Deleting an entry removes its marker + body from the log file.
final class NanoMuseMemoryStore: ObservableObject {
    @Published private(set) var entries: [NanoMuseDiaryEntry] = []
    /// Days present, newest first.
    @Published private(set) var days: [String] = []

    private static let markerPattern = "<!-- (\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}) -->"
    private static let filePattern = "^\\d{4}-\\d{2}-\\d{2}\\.md$"

    var isEmpty: Bool { entries.isEmpty }

    func entries(on day: String) -> [NanoMuseDiaryEntry] {
        entries.filter { $0.day == day }
    }

    func reload() {
        let fm = FileManager.default
        let memDir = AIChatViewModel.minisMemoryPersistentDir
        guard let fileRegex = try? NSRegularExpression(pattern: Self.filePattern),
              let markerRegex = try? NSRegularExpression(pattern: Self.markerPattern),
              let names = try? fm.contentsOfDirectory(atPath: memDir.path) else {
            entries = []
            days = []
            return
        }

        var parsed: [NanoMuseDiaryEntry] = []
        for name in names {
            let range = NSRange(name.startIndex..., in: name)
            guard fileRegex.firstMatch(in: name, range: range) != nil else { continue }
            let day = String(name.dropLast(3)) // strip ".md"
            let fileURL = memDir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            parsed.append(contentsOf: Self.parseEntries(text: text, day: day, fileURL: fileURL, markerRegex: markerRegex))
        }

        // Newest first: by day, then by timestamp within the day.
        parsed.sort {
            if $0.day != $1.day { return $0.day > $1.day }
            return $0.timestamp > $1.timestamp
        }
        entries = parsed

        var seen: [String] = []
        for e in parsed where !seen.contains(e.day) { seen.append(e.day) }
        days = seen
    }

    private static func parseEntries(text: String, day: String, fileURL: URL, markerRegex: NSRegularExpression) -> [NanoMuseDiaryEntry] {
        let ns = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out: [NanoMuseDiaryEntry] = []
        for (i, match) in matches.enumerated() {
            let timestamp = ns.substring(with: match.range(at: 1))
            var bodyStart = match.range.location + match.range.length
            if bodyStart < ns.length, ns.character(at: bodyStart) == 10 { bodyStart += 1 } // skip newline after marker
            let entryEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            guard entryEnd >= bodyStart else { continue }
            let body = ns.substring(with: NSRange(location: bodyStart, length: entryEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            out.append(NanoMuseDiaryEntry(day: day, timestamp: timestamp, body: body, fileURL: fileURL))
        }
        return out
    }

    /// The body of the entry identified by `timestamp` in `text`, or nil.
    private static func body(for timestamp: String, in text: String, markerRegex: NSRegularExpression) -> String? {
        let ns = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for (i, match) in matches.enumerated() {
            guard ns.substring(with: match.range(at: 1)) == timestamp else { continue }
            var bodyStart = match.range.location + match.range.length
            if bodyStart < ns.length, ns.character(at: bodyStart) == 10 { bodyStart += 1 }
            let entryEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            guard entryEnd >= bodyStart else { return nil }
            return ns.substring(with: NSRange(location: bodyStart, length: entryEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Delete one entry: remove its marker + body from the daily log. When the
    /// file holds nothing afterwards, the file itself is removed. Both the
    /// timestamp and the body must match, so a stale row can never delete the
    /// wrong entry.
    @discardableResult
    func delete(_ entry: NanoMuseDiaryEntry) -> String {
        let fileURL = entry.fileURL
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let markerRegex = try? NSRegularExpression(pattern: Self.markerPattern),
              let currentBody = Self.body(for: entry.timestamp, in: text, markerRegex: markerRegex),
              currentBody == entry.body.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return AppLocalized("Entry not found.")
        }

        let ns = text as NSString
        let matches = markerRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for (i, match) in matches.enumerated() {
            guard ns.substring(with: match.range(at: 1)) == entry.timestamp else { continue }
            let entryStart = match.range.location
            let entryEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let newText = ns.replacingCharacters(in: NSRange(location: entryStart, length: entryEnd - entryStart), with: "")
            do {
                if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try FileManager.default.removeItem(at: fileURL)
                } else {
                    try newText.write(to: fileURL, atomically: true, encoding: .utf8)
                }
                reload()
                return AppLocalized("Deleted")
            } catch {
                return AppLocalized("Error writing file: \(error.localizedDescription)")
            }
        }
        return AppLocalized("Entry not found.")
    }
}

// MARK: - Room

struct NanoMuseMemoryRoom: View {
    var chrome: NanoMuseRoomChrome

    @StateObject private var store = NanoMuseMemoryStore()
    @State private var searchText = ""
    @State private var detail: NanoMuseDiaryEntry?
    @State private var fileDetail: NanoMuseMemoryFile?
    @State private var pendingDelete: NanoMuseDiaryEntry?
    @State private var showDeleteConfirm = false
    @State private var deleteResult: String?

    private var searching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filteredEntries: [NanoMuseDiaryEntry] {
        guard searching else { return store.entries }
        let q = searchText.lowercased()
        return store.entries.filter {
            $0.body.lowercased().contains(q) || $0.timestamp.contains(q) || $0.day.contains(q)
        }
    }

    private var filteredDays: [String] {
        var seen: [String] = []
        for e in filteredEntries where !seen.contains(e.day) { seen.append(e.day) }
        return seen
    }

    /// SOUL.md / GLOBAL.md, like SessionMemoryView's auto-injected section.
    private var systemFiles: [NanoMuseMemoryFile] {
        let fm = FileManager.default
        let memDir = AIChatViewModel.minisMemoryPersistentDir
        return [
            ("SOUL.md", "person.fill"),
            ("GLOBAL.md", "star.fill"),
        ].compactMap { name, icon in
            let url = memDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { return nil }
            return NanoMuseMemoryFile(name: name, icon: icon, url: url)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NanoMuseRoomHeader(chrome: chrome) {
                NanoMuseRoundButton(symbol: "arrow.clockwise", label: AppLocalized("Refresh")) {
                    store.reload()
                }
            }
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !searching, !systemFiles.isEmpty {
                        systemFilesSection
                    }
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredDays, id: \.self) { day in
                            daySection(day)
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { store.reload() }
        }
        .background(NanoMuseTones.canvas.ignoresSafeArea())
        .onAppear { store.reload() }
        .sheet(item: $detail) { entry in
            NavigationView {
                NanoMuseDiaryEntryDetail(entry: entry, store: store)
            }
        }
        .sheet(item: $fileDetail) { file in
            NavigationView {
                NanoMuseMemoryFileEditor(file: file)
            }
        }
        .alert(AppLocalized("Delete this entry?"), isPresented: $showDeleteConfirm) {
            Button(AppLocalized("Cancel"), role: .cancel) { pendingDelete = nil }
            Button(AppLocalized("Delete"), role: .destructive) {
                if let entry = pendingDelete {
                    deleteResult = store.delete(entry)
                    pendingDelete = nil
                }
            }
        } message: {
            Text(AppLocalized("This cannot be undone."))
        }
        .alert(deleteResult ?? "", isPresented: Binding(
            get: { deleteResult != nil },
            set: { if !$0 { deleteResult = nil } }
        )) {
            Button(AppLocalized("OK")) {}
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(AppLocalized("Search"), text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if searching {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Sections

    private var systemFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalized("System files"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ForEach(systemFiles) { file in
                Button { fileDetail = file } label: {
                    HStack(spacing: 10) {
                        Image(systemName: file.icon)
                            .foregroundStyle(.pink)
                            .frame(width: 20)
                        Text(file.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func daySection(_ day: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel(day))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ForEach(store.entries(on: day).filter { filteredEntries.contains($0) }) { entry in
                entryCard(entry)
            }
        }
    }

    private func entryCard(_ entry: NanoMuseDiaryEntry) -> some View {
        Button { detail = entry } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = entry
                showDeleteConfirm = true
            } label: {
                Label(AppLocalized("Delete"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = entry
                showDeleteConfirm = true
            } label: {
                Label(AppLocalized("Delete"), systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(searching ? AppLocalized("No matching entries") : AppLocalized("No diary entries yet"))
                .font(.headline)
            Text(AppLocalized("Things your agent writes down with memory_write will appear here, grouped by day."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func dayLabel(_ day: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let yesterday = fmt.string(from: Date().addingTimeInterval(-86400))
        if day == today { return AppLocalized("Today") }
        if day == yesterday { return AppLocalized("Yesterday") }
        return day
    }
}

// MARK: - Entry detail

/// Full entry with delete. Presented as a sheet from the timeline.
private struct NanoMuseDiaryEntryDetail: View {
    let entry: NanoMuseDiaryEntry
    @ObservedObject var store: NanoMuseMemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var deleteResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                Text(entry.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
            .padding(.bottom)
        }
        .navigationTitle(entry.day)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert(AppLocalized("Delete this entry?"), isPresented: $showDeleteConfirm) {
            Button(AppLocalized("Cancel"), role: .cancel) {}
            Button(AppLocalized("Delete"), role: .destructive) {
                deleteResult = store.delete(entry)
            }
        } message: {
            Text(AppLocalized("This cannot be undone."))
        }
        .alert(deleteResult ?? "", isPresented: Binding(
            get: { deleteResult != nil },
            set: { if !$0 { deleteResult = nil } }
        )) {
            Button(AppLocalized("OK")) {
                if deleteResult == AppLocalized("Deleted") { dismiss() }
            }
        }
    }
}

// MARK: - File editor

/// SOUL.md / GLOBAL.md editor: pencil → TextEditor → Save writes to disk.
/// Same pattern as SessionMemoryView's MemoryContentView, including the
/// SOUL.md side effects (refresh the in-memory cache + mark dirty for iCloud).
private struct NanoMuseMemoryFileEditor: View {
    let file: NanoMuseMemoryFile
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var editedContent: String = ""
    @State private var isEditing = false
    @State private var saved = false

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(AppLocalized("Done")) { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button(AppLocalized("Save")) { save() }
                } else {
                    Button {
                        editedContent = content
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if saved {
                Text(AppLocalized("Saved"))
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            content = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
        }
    }

    private func save() {
        do {
            try editedContent.write(to: file.url, atomically: true, encoding: .utf8)
            content = editedContent
            if file.url.lastPathComponent == "SOUL.md" {
                SoulStore.refreshCache()
                Task { await ChatStore.shared.markDirty(recordType: "SoulV2", recordId: "soul") }
            }
            isEditing = false
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { saved = false }
            }
        } catch {
            // stay in editing mode on failure
        }
    }
}
