import SwiftUI
import SharedFoundation

/// ⌘P command palette — fuzzy-search across all notes and commands.
/// Presented as a sheet from ContentView and dismissed on selection or Escape.
struct CommandPaletteView: View {

    @EnvironmentObject private var appState: AppState
    @Binding var selectedNote: Note?
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var hoveredIndex: Int? = nil
    @FocusState private var searchFocused: Bool

    // MARK: – Results

    private var noteResults: [NoteResult] {
        guard let store = appState.activeVault else { return [] }
        let notes = query.isEmpty
            ? Array(store.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(12))
            : store.search(query: query)
                   .sorted { score($0, query: query) > score($1, query: query) }
                   .prefix(12)
                   .map { $0 }
        return notes.map { NoteResult(note: $0) }
    }

    private var commandResults: [CommandResult] {
        let cmds: [CommandResult] = [
            .init(title: "New Note…",            icon: "square.and.pencil",    shortcut: "⌘N") {
                NotificationCenter.default.post(name: .mongrelNewNote, object: nil)
            },
            .init(title: "Today's Daily Note",   icon: "calendar",             shortcut: "⌘⇧D") { [self] in
                appState.createOrOpenDailyNote()
            },
            .init(title: "Open Vault…",          icon: "folder.badge.plus",    shortcut: "⌘⇧O") { [self] in
                openVaultPanel()
            },
            .init(title: "Toggle Graph View",    icon: "arrow.triangle.branch", shortcut: nil) { [self] in
                NotificationCenter.default.post(name: .mongrelSwitchMode, object: "graph")
            },
            .init(title: "Toggle Canvas",        icon: "scribble",              shortcut: nil) { [self] in
                NotificationCenter.default.post(name: .mongrelSwitchMode, object: "canvas")
            },
        ]
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return cmds.filter { $0.title.lowercased().contains(q) }
    }

    // Combined list for keyboard navigation
    private enum PaletteItem {
        case note(NoteResult)
        case command(CommandResult)
    }

    private var allItems: [PaletteItem] {
        noteResults.map { .note($0) } + commandResults.map { .command($0) }
    }

    // MARK: – Body

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().foregroundStyle(DesignTokens.borderRim)
            resultsList
        }
        .frame(width: 560, height: min(CGFloat(allItems.count) * 52 + 56, 480))
        .glassChromeBackground(style: .deep, cornerRadius: 14)
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        .padding(1)   // lets the border rim show outside the clip shape
        .onAppear { searchFocused = true }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) {
            hoveredIndex = min((hoveredIndex ?? -1) + 1, allItems.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            hoveredIndex = max((hoveredIndex ?? 1) - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if let idx = hoveredIndex { activate(allItems[idx]) }
            return .handled
        }
    }

    // MARK: – Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.accent)
                .font(.system(size: 16, weight: .medium))

            TextField("Search notes or type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.chromeText)
                .focused($searchFocused)
                .onChange(of: query) { _ in hoveredIndex = allItems.isEmpty ? nil : 0 }

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: – Results list

    @ViewBuilder
    private var resultsList: some View {
        if allItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.2))
                Text("No results")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.3))
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !noteResults.isEmpty {
                            sectionHeader("Notes")
                            ForEach(Array(noteResults.enumerated()), id: \.element.id) { idx, result in
                                PaletteNoteRow(
                                    result: result,
                                    query: query,
                                    isHighlighted: hoveredIndex == idx
                                ) {
                                    activate(.note(result))
                                }
                                .id(idx)
                                .onHover { if $0 { hoveredIndex = idx } }
                            }
                        }
                        if !commandResults.isEmpty {
                            sectionHeader("Commands")
                            ForEach(Array(commandResults.enumerated()), id: \.element.id) { i, cmd in
                                let idx = noteResults.count + i
                                PaletteCommandRow(
                                    command: cmd,
                                    isHighlighted: hoveredIndex == idx
                                ) {
                                    activate(.command(cmd))
                                }
                                .id(idx)
                                .onHover { if $0 { hoveredIndex = idx } }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: hoveredIndex) { idx in
                    if let idx { withAnimation { proxy.scrollTo(idx, anchor: .center) } }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                .kerning(0.8)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: – Actions

    private func activate(_ item: PaletteItem) {
        switch item {
        case .note(let r):
            selectedNote = r.note
            appState.activeVault = appState.openVaults.first {
                $0.notes.contains { $0.id == r.note.id }
            } ?? appState.activeVault
        case .command(let c):
            c.action()
        }
        dismiss()
    }

    // MARK: – Fuzzy score

    /// Simple relevance score: title prefix > title contains > body contains.
    private func score(_ note: Note, query: String) -> Int {
        let q = query.lowercased()
        let t = note.title.lowercased()
        if t.hasPrefix(q)          { return 100 }
        if t.contains(q)           { return 80 }
        if note.body.lowercased().contains(q) { return 40 }
        return 0
    }

    private func openVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.openVault(at: url) }
    }
}

// MARK: – Data types

struct NoteResult: Identifiable {
    let note: Note
    var id: UUID { note.id }
}

struct CommandResult: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let shortcut: String?
    let action: () -> Void
}

// MARK: – Row views

struct PaletteNoteRow: View {
    let result: NoteResult
    let query: String
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .frame(width: 20)
                    .foregroundStyle(isHighlighted ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    HighlightedText(text: result.note.title, highlight: query)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(DesignTokens.chromeText)
                    Text(result.note.excerpt)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                Text(result.note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHighlighted
                ? DesignTokens.glassHotSpot.opacity(0.5)
                : Color.clear
        )
    }
}

struct PaletteCommandRow: View {
    let command: CommandResult
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .frame(width: 20)
                    .foregroundStyle(isHighlighted ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.5))

                Text(command.title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(DesignTokens.chromeText)

                Spacer()

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignTokens.glassBase.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(DesignTokens.borderRim, lineWidth: 0.5)
                                )
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHighlighted
                ? DesignTokens.glassHotSpot.opacity(0.5)
                : Color.clear
        )
    }
}

// MARK: – Highlighted text helper

/// Renders `text` with every occurrence of `highlight` bolded in the accent colour.
/// Uses NSMutableAttributedString for reliable range handling across all Unicode.
struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        let ns = NSMutableAttributedString(string: text)
        // Base style
        let fullRange = NSRange(location: 0, length: ns.length)
        ns.addAttribute(.font,
                        value: NSFont.systemFont(ofSize: 14),
                        range: fullRange)

        guard !highlight.isEmpty else {
            return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(text)
        }

        // Highlight every match
        let lowText  = (text as NSString).lowercased
        let lowQuery = highlight.lowercased()
        var search = NSRange(location: 0, length: lowText.count)
        while search.location < lowText.count {
            let found = (lowText as NSString).range(of: lowQuery, options: [], range: search)
            guard found.location != NSNotFound else { break }
            ns.addAttribute(.foregroundColor, value: NSColor(DesignTokens.accent), range: found)
            ns.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: found)
            search = NSRange(location: found.upperBound,
                             length: lowText.count - found.upperBound)
        }
        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(text)
    }
}

// MARK: – Notification for mode switching from commands

extension Notification.Name {
    static let mongrelSwitchMode = Notification.Name("com.mongrel.notes.switchMode")
}
