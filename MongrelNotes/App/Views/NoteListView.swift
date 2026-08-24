import SwiftUI
import SharedFoundation

/// Middle column: searchable, sortable list of notes in the selected folder.
struct NoteListView: View {

    @EnvironmentObject private var appState: AppState
    @Binding var selectedNote: Note?
    let folder: NoteFolder?
    @Binding var searchQuery: String
    @Binding var selectedTag: String?

    // sortOrder is local UI state – no ViewModel needed since filteredNotes
    // is derived directly from appState.activeVault (an @ObservedObject chain).
    @State private var sortOrder: VaultViewModel.SortOrder = .updatedAt
    @FocusState private var searchFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().foregroundStyle(DesignTokens.borderRim)
            noteList
        }
        .background(
            ZStack {
                DesignTokens.glassDeep.ignoresSafeArea()
                // Drop zone highlight
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(DesignTokens.accent.opacity(0.8), lineWidth: 2)
                    DesignTokens.accent.opacity(0.06)
                }
            }
        )
        .overlay(alignment: .center) {
            if isDropTargeted {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(DesignTokens.accent)
                    Text("Drop to import .md files")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.accent)
                }
                .padding(20)
                .background(DesignTokens.glassDeep.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .toolbar { listToolbar }
        // Accept .md files dropped from Finder onto the note list column.
        // Uses the modern Transferable-based API (macOS 13+).
        .dropDestination(for: URL.self, action: { urls, _ in
            guard let store = appState.activeVault else { return false }
            let mdURLs = urls.filter { $0.pathExtension.lowercased() == "md" }
            guard !mdURLs.isEmpty else {
                appState.presentWorkflowAlert(
                    title: "Unsupported Files",
                    message: "Only .md files can be imported into notes."
                )
                return false
            }
            var lastNote: Note?
            var failedCount = 0
            for url in mdURLs {
                if let imported = store.importFile(at: url, into: folder) {
                    lastNote = imported
                } else {
                    failedCount += 1
                }
            }
            if let note = lastNote { selectedNote = note }
            if failedCount > 0 {
                appState.presentWorkflowAlert(
                    title: "Import Partially Failed",
                    message: "Imported \(mdURLs.count - failedCount) file(s), but \(failedCount) file(s) could not be read."
                )
            }
            return lastNote != nil
        }, isTargeted: { isDropTargeted = $0 })
    }

    // MARK: – Search bar

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
                    .font(.system(size: 13))
                TextField("Search notes…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.uiFont)
                    .foregroundStyle(DesignTokens.chromeText)
                    .focused($searchFocused)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassChromeBackground(style: .base, cornerRadius: 8)
            .padding(8)

            // Active tag filter chip
            if let tag = selectedTag {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9))
                    Text("#\(tag)")
                        .font(.system(size: 11, weight: .medium))
                    Button {
                        selectedTag = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(DesignTokens.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.accent.opacity(0.12))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: – Note list

    private var filteredNotes: [Note] {
        guard let store = appState.activeVault else { return [] }
        var notes = searchQuery.isEmpty ? store.notes : store.search(query: searchQuery)
        if let folder {
            notes = notes.filter { $0.fileURL.path.hasPrefix(folder.directoryURL.path) }
        }
        if let tag = selectedTag {
            notes = notes.filter { $0.tags.contains(tag) }
        }
        switch sortOrder {
        case .updatedAt: notes.sort { $0.updatedAt > $1.updatedAt }
        case .createdAt: notes.sort { $0.createdAt > $1.createdAt }
        case .title:     notes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        let pinned   = notes.filter(\.isPinned)
        let unpinned = notes.filter { !$0.isPinned }
        return pinned + unpinned
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if filteredNotes.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredNotes) { note in
                        NoteRowView(
                            note: note,
                            isSelected: selectedNote?.id == note.id,
                            searchQuery: searchQuery
                        ) {
                            selectedNote = note
                        }
                        .contextMenu {
                            noteContextMenu(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let isFiltered = !searchQuery.isEmpty || selectedTag != nil
        VStack(spacing: 10) {
            Image(systemName: isFiltered ? "magnifyingglass" : "note.text")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.25))
            Group {
                if !searchQuery.isEmpty {
                    Text("No results for \"\(searchQuery)\"")
                } else if let tag = selectedTag {
                    Text("No notes tagged #\(tag)")
                } else {
                    Text("No notes yet")
                }
            }
            .font(.callout)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
            if !isFiltered {
                Button("Create a note") {
                    NotificationCenter.default.post(name: .mongrelNewNote, object: nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.accent)
            }
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func noteContextMenu(_ note: Note) -> some View {
        Button {
            appState.activeVault?.save(
                Note(id: note.id, fileURL: note.fileURL, title: note.title,
                     body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt,
                     isPinned: !note.isPinned, tags: note.tags)
            )
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        Divider()
        Button(role: .destructive) {
            if selectedNote?.id == note.id { selectedNote = nil }
            appState.activeVault?.delete(note)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .mongrelNewNote, object: nil)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New Note… (⌘N)")
        }
        ToolbarItem {
            Menu {
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(VaultViewModel.SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .help("Sort & filter")
        }
    }
}

// MARK: – Note row

struct NoteRowView: View {

    let note: Note
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // ── Left accent stripe (selected state only) ──────────────
                DesignTokens.accent
                    .frame(width: 2)
                    .opacity(isSelected ? 1 : 0)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: DesignTokens.cardRadius,
                            bottomLeadingRadius: DesignTokens.cardRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                // ── Content ────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 5) {
                    // Title row
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(DesignTokens.accent)
                        }
                        if note.isEncrypted {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(DesignTokens.accentDim)
                        }
                        Text(note.title)
                            .font(.system(.callout, weight: .semibold))
                            .foregroundStyle(isSelected
                                             ? DesignTokens.chromeText
                                             : DesignTokens.chromeText.opacity(0.90))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(note.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                            .monospacedDigit()
                    }

                    // Excerpt
                    if !note.isEncrypted {
                        Text(note.excerpt)
                            .font(.system(size: 11.5))
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.48))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        if note.isEncrypted {
                            Label("Encrypted", systemImage: "lock.shield")
                                .font(.system(size: 9, weight: .medium))
                        } else {
                            Text("\(note.wordCount)w")
                            Text("\(note.characterCount)c")
                        }

                        Text("created")
                        Text(note.createdAt, style: .date)
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.38))

                    // Tags
                    if !note.tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(note.tags.prefix(3), id: \.self) { tag in
                                TagPill(tag: tag)
                            }
                            if note.tags.count > 3 {
                                Text("+\(note.tags.count - 3)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DesignTokens.accentDim)
                            }
                        }
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(isSelected: isSelected)
    }
}

// MARK: – Tag pill

/// A small tinted glass pill badge for a single tag.
struct TagPill: View {
    let tag: String
    var body: some View {
        Text("#\(tag)")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(DesignTokens.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.accent.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(DesignTokens.accent.opacity(0.28),
                                          lineWidth: 0.5)
                    )
            )
    }
}
