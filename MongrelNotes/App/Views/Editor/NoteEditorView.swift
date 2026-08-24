import SwiftUI
import SharedFoundation

/// Full-editor view: NSTextView wrapped for macOS, with backlinks panel and status bar.
///
/// The parent must use `.id(note.id)` so SwiftUI tears down and rebuilds this view
/// (and its @StateObject) whenever the selected note changes.
struct NoteEditorView: View {

    let store: VaultStore
    @StateObject private var viewModel: NoteEditorViewModel
    @StateObject private var exportManager = ExportManager()
    @EnvironmentObject private var enc: EncryptionManager

    // Preferences
    @AppStorage(Prefs.showWordCount) private var showWordCount: Bool   = true
    @AppStorage(Prefs.showCharCount) private var showCharCount: Bool   = false
    @AppStorage(Prefs.editorMood)    private var moodID:        String = "glass"

    // Inline colour tool
    @State private var inlineColor: Color = .orange
    @State private var showColorPicker = false

    // Mood quick-switcher
    @State private var showMoodPicker = false

    // Tag editor
    @State private var showTagEditor: Bool = false

    // Encryption sheets
    @State private var showSetPasswordSheet: Bool = false
    @State private var showUnlockSheet:      Bool = false

    private var mood: EditorMood { EditorMood.named(moodID) }

    /// Designated initialiser.  Parent should pair with `.id(note.id)`.
    init(note: Note, store: VaultStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: NoteEditorViewModel(note: note, store: store))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titleField
                Divider().foregroundStyle(DesignTokens.borderRim)

                HSplitView {
                    MarkdownEditorNSView(text: $viewModel.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if viewModel.showBacklinksPanel {
                        backlinksPanel.frame(width: 240)
                    }
                }
                .disabled(viewModel.isLocked)

                Divider().foregroundStyle(DesignTokens.borderRim)
                statusBar
            }
            .background(Color(mood.background))

            // ── Locked note overlay ────────────────────────────────────────
            if viewModel.isLocked {
                LockedNoteOverlay {
                    // Called after successful unlock / if already unlocked
                    viewModel.unlockAndDecrypt()
                }
            }
        }
        .toolbar { editorToolbar }
        // Mood quick-picker popover
        .popover(isPresented: $showMoodPicker, arrowEdge: .top) {
            MoodPickerPopover(moodID: $moodID)
        }
        // Encryption sheets
        .sheet(isPresented: $showSetPasswordSheet) {
            SetPasswordSheet()
        }
        .sheet(isPresented: $showUnlockSheet) {
            UnlockSheet {
                viewModel.unlockAndDecrypt()
            }
        }
        .alert("Export Failed", isPresented: exportErrorIsPresented) {
            Button("OK") { exportManager.errorMessage = nil }
        } message: {
            Text(exportManager.errorMessage ?? "The note could not be exported.")
        }
        // ── Handoff ─────────────────────────────────────────────────────────
        // Advertise the currently open note to other devices via Handoff.
        // macOS will surface a Handoff icon in the Dock on the receiving device.
        .userActivity(Handoff.activityType) { activity in
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch  = false
            activity.title = viewModel.title
            activity.userInfo = [
                Handoff.noteIDKey:   viewModel.noteID.uuidString,
                Handoff.vaultURLKey: store.vault.rootURL.path,
            ]
        }
    }

    // MARK: – Title field

    private var titleField: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Title", text: Binding(
                    get: { viewModel.title },
                    set: { newTitle in
                        // Sync the title back to the body's H1 line so that
                        // the file name and WikilinkParser.extractTitle stay consistent.
                        viewModel.applyTitleEdit(newTitle)
                    }
                ))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Spacer()

                if viewModel.isSaving {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Saving…")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                    }
                    .padding(.trailing, 16)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        viewModel.togglePinned()
                    } label: {
                        metadataChip(viewModel.isPinned ? "Pinned" : "Unpinned", icon: viewModel.isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.plain)
                    metadataChip(viewModel.isEncryptedNote ? "Encrypted" : "Plaintext", icon: viewModel.isEncryptedNote ? "lock.fill" : "lock.open")
                    metadataChip(viewModel.fileName, icon: "doc.text")
                    metadataChip("Created \(viewModel.createdAt.formatted(date: .abbreviated, time: .omitted))", icon: "calendar.badge.plus")
                    metadataChip("Updated \(relativeTimestamp(viewModel.updatedAt))", icon: "clock")
                    metadataChip("\(viewModel.wordCount) words", icon: "text.alignleft")
                    metadataChip("\(viewModel.charCount) chars", icon: "character.cursor.ibeam")
                    metadataChip("\(viewModel.outboundLinkCount) links", icon: "link")
                    metadataChip("\(viewModel.backlinkCount) backlinks", icon: "arrow.triangle.branch")
                    // Tag chip — always visible; tap to open the tag editor popover.
                    Button {
                        showTagEditor.toggle()
                    } label: {
                        metadataChip(
                            viewModel.tagCount > 0 ? "\(viewModel.tagCount) tags" : "Add tags",
                            icon: "tag"
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showTagEditor, arrowEdge: .bottom) {
                        TagEditorPopover(viewModel: viewModel)
                    }
                    .disabled(viewModel.isLocked)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: – Backlinks panel

    private func relativeTimestamp(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backlinks")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
                Spacer()
                Text("\(viewModel.backlinkNotes.count)")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().foregroundStyle(DesignTokens.borderRim)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.backlinkNotes) { note in
                        BacklinkRowView(note: note)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    if viewModel.backlinkNotes.isEmpty {
                        Text("No notes link here yet.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                            .padding()
                    }
                }
            }

            Divider().foregroundStyle(DesignTokens.borderRim)

            // Outbound links
            HStack {
                Text("Links")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
                Spacer()
                Text("\(viewModel.outboundLinks.count)")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.outboundLinks, id: \.self) { link in
                        Text("→ \(link)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    // MARK: – Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if showWordCount {
                Text("\(viewModel.wordCount) words")
            }
            if showCharCount {
                Text("\(viewModel.charCount) characters")
            }
            Spacer()
            if exportManager.isExporting {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Exporting…")
                }
            } else if let exportedURL = exportManager.lastExported {
                Text("Exported \(exportedURL.lastPathComponent)")
                    .lineLimit(1)
            }
            if !viewModel.note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(viewModel.note.tags.prefix(5), id: \.self) { tag in
                        Text("#\(tag)")
                            .foregroundStyle(DesignTokens.accent.opacity(0.8))
                    }
                }
            }
            Text(viewModel.note.updatedAt, style: .relative)
        }
        .font(.system(size: 11))
        .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {

        // ── Encryption ─────────────────────────────────────────────────
        ToolbarItem {
            Button {
                viewModel.togglePinned()
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(viewModel.isPinned ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.75))
            }
            .help(viewModel.isPinned ? "Unpin note" : "Pin note")
        }

        ToolbarItem {
            encryptionToolbarButton
        }

        // ── Mood switcher ──────────────────────────────────────────────
        ToolbarItem {
            Button {
                showMoodPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(mood.accent))
                        .frame(width: 8, height: 8)
                    Image(systemName: mood.icon)
                }
                .foregroundStyle(DesignTokens.chromeText.opacity(0.75))
            }
            .help("Switch editor mood (\(mood.name))")
        }

        // ── Inline colour picker ───────────────────────────────────────
        ToolbarItem {
            HStack(spacing: 2) {
                ColorPicker("", selection: $inlineColor, supportsOpacity: false)
                    .frame(width: 24)
                    .help("Pick text colour")
                Button {
                    insertColorSpan()
                } label: {
                    Image(systemName: "paintbrush.pointed")
                        .foregroundStyle(inlineColor)
                }
                .help("Wrap selection in colour span  ·  inserts <span style=\"color:…\">")
            }
            .disabled(viewModel.isLocked)
        }

        // ── Backlinks ──────────────────────────────────────────────────
        ToolbarItem {
            Button {
                viewModel.toggleBacklinksPanel()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(viewModel.showBacklinksPanel
                                     ? DesignTokens.accent
                                     : DesignTokens.chromeText)
            }
            .help("Toggle backlinks (⌘⇧B)")
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        // ── Export ─────────────────────────────────────────────────────
        ToolbarItem {
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        exportManager.export(viewModel.note, format: format, mood: mood)
                    } label: {
                        Label("Export as \(format.rawValue)…", systemImage: format.icon)
                    }
                }
            } label: {
                if exportManager.isExporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.75))
                }
            }
            .help("Export note")
            .disabled(viewModel.isLocked || exportManager.isExporting)
        }

        // ── Save ───────────────────────────────────────────────────────
        ToolbarItem {
            Button { viewModel.saveNow() } label: {
                Image(systemName: "arrow.down.doc")
            }
            .help("Save now (⌘S)")
            .keyboardShortcut("s")
            .disabled(viewModel.isLocked)
        }
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportManager.errorMessage != nil },
            set: { isPresented in
                if !isPresented { exportManager.errorMessage = nil }
            }
        )
    }

    // MARK: – Encryption toolbar button

    @ViewBuilder
    private var encryptionToolbarButton: some View {
        let isEncrypted = viewModel.isEncryptedNote
        let isLocked    = viewModel.isLocked
        let sessionLocked = !enc.isUnlocked

        Menu {
            if isEncrypted {
                // Note is encrypted
                if sessionLocked {
                    Button {
                        showUnlockSheet = true
                    } label: {
                        Label("Unlock notes…", systemImage: "lock.open")
                    }
                } else {
                    Button {
                        viewModel.toggleEncryption()
                    } label: {
                        Label("Remove encryption", systemImage: "lock.slash")
                    }
                }
                Divider()
                Button {
                    enc.lock()
                } label: {
                    Label("Lock session", systemImage: "lock")
                }
            } else {
                // Note is plaintext
                if enc.hasPassword {
                    Button {
                        if enc.isUnlocked {
                            viewModel.toggleEncryption()
                        } else {
                            showUnlockSheet = true
                        }
                    } label: {
                        Label("Encrypt this note", systemImage: "lock")
                    }
                } else {
                    Button {
                        showSetPasswordSheet = true
                    } label: {
                        Label("Set encryption password…", systemImage: "lock.badge.plus")
                    }
                }
            }
        } label: {
            Image(systemName: isEncrypted
                  ? (isLocked ? "lock.fill" : "lock.open.fill")
                  : "lock")
                .foregroundStyle(isEncrypted
                                 ? (isLocked ? DesignTokens.accent : DesignTokens.accentDim)
                                 : DesignTokens.chromeText.opacity(0.55))
        }
        .help(isEncrypted ? "Note is encrypted" : "Encrypt note")
    }

    // MARK: – Inline colour insertion

    /// Wraps the current selection (or inserts at cursor) with
    /// `<span style="color:#RRGGBB">…</span>`.
    private func insertColorSpan() {
        let hex = inlineColor.hexString
        let open  = "<span style=\"color:\(hex)\">"
        let close = "</span>"

        // Read current body, find selected range via notification, wrap it.
        // Because NSTextView manages its own selection we post a notification
        // that the Coordinator intercepts to do the actual insertion.
        NotificationCenter.default.post(
            name: .mongrelInsertColorSpan,
            object: nil,
            userInfo: ["open": open, "close": close]
        )
    }

    private func metadataChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.chromeText.opacity(0.72))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DesignTokens.glassElevated.opacity(0.9))
                .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: 0.5))
        )
    }
}

// MARK: – Mood picker popover

private struct MoodPickerPopover: View {
    @Binding var moodID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor Mood")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ForEach(EditorMood.all) { m in
                MoodRow(mood: m, isSelected: moodID == m.id) {
                    moodID = m.id
                }
            }
        }
        .padding(.bottom, 8)
        .frame(width: 200)
        .background(DesignTokens.glassDeep)
    }
}

private struct MoodRow: View {
    let mood: EditorMood
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(mood.background))
                        .frame(width: 28, height: 20)
                    Image(systemName: mood.icon)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Color(mood.accent))
                }
                Text(mood.name)
                    .font(.callout)
                    .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(hovered ? DesignTokens.glassBase.opacity(0.4) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: – Backlink row

struct BacklinkRowView: View {
    let note: Note
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.85))
            Text(note.excerpt)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassChromeBackground(style: .card, cornerRadius: 6)
    }
}

// MARK: – Split editor (editor + live preview side by side)

/// Side-by-side source + preview. Uses the same `NoteEditorViewModel` as the full
/// editor so auto-save, word count, and backlinks all work identically.
/// Parent must supply `.id(note.id)` to force a clean ViewModel on note switch.
struct SplitEditorView: View {
    @StateObject private var viewModel: NoteEditorViewModel

    init(note: Note, store: VaultStore) {
        _viewModel = StateObject(wrappedValue: NoteEditorViewModel(note: note, store: store))
    }

    var body: some View {
        HSplitView {
            MarkdownEditorNSView(text: $viewModel.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MarkdownPreviewView(markdown: viewModel.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
