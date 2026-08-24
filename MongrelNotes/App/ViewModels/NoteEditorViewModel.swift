import SwiftUI
import Combine
import SharedFoundation

/// ViewModel for the note editor. Manages auto-save, undo history, word count, and backlinks panel.
///
/// **Encryption flow**
/// When the note is encrypted:
/// - If the session is unlocked, the body is decrypted immediately in `init` so
///   the editor always works with plaintext.
/// - If the session is locked, `isLocked` is `true` and the body is empty;
///   the editor shows `LockedNoteOverlay` instead.
/// - `performSave()` re-encrypts before writing to disk when `isEncryptedNote == true`.
/// - `toggleEncryption()` flips encryption on or off at the storage level.
@MainActor
final class NoteEditorViewModel: ObservableObject {

    // MARK: – Published

    @Published var body: String = "" {
        didSet {
            guard !suppressDirtyTracking else { return }
            isDirty = true
            updateDerivedState()
            scheduleSave()
        }
    }
    @Published var wordCount: Int = 0
    @Published var charCount: Int = 0
    @Published var outboundLinks: [String] = []
    @Published var backlinkNotes: [Note] = []
    @Published var isDirty: Bool = false
    @Published var isSaving: Bool = false
    @Published var showBacklinksPanel: Bool = false

    /// `true` while the note is encrypted and the session is not yet unlocked.
    /// The editor replaces its content with `LockedNoteOverlay` when this is set.
    @Published private(set) var isLocked: Bool = false

    /// Whether this note is stored encrypted on disk (persists even after unlock).
    private(set) var isEncryptedNote: Bool = false

    // MARK: – Identity (exposed for Handoff)

    var noteID: UUID { note.id }
    var title: String { WikilinkParser.extractTitle(from: body, fallback: note.title) }
    var isPinned: Bool { note.isPinned }
    var createdAt: Date { note.createdAt }
    var updatedAt: Date { note.updatedAt }
    var fileName: String { note.fileURL.lastPathComponent }
    /// Tags parsed live from the in-memory body — reflects edits before they are saved.
    var liveTags: [String] { WikilinkParser.extractTags(from: body) }
    var tagCount: Int { liveTags.count }
    var outboundLinkCount: Int { outboundLinks.count }
    var backlinkCount: Int { backlinkNotes.count }

    // MARK: – Dependencies

    private(set) var note: Note
    let store: VaultStore
    private var saveTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// When `true`, `body` assignments do not trigger dirty-marking or auto-save.
    /// Used to load/decrypt the body without starting an unwanted save cycle.
    private var suppressDirtyTracking: Bool = false

    // MARK: – Init

    init(note: Note, store: VaultStore) {
        self.note  = note
        self.store = store
        self.isEncryptedNote = note.isEncrypted
        self.suppressDirtyTracking = true

        if note.isEncrypted {
            let service = NoteEncryptionService.shared
            if service.isUnlocked, let plaintext = try? service.decrypt(note.body) {
                // Auto-decrypt: editor works entirely with plaintext
                self.body = plaintext
                self.isLocked = false
            } else {
                // Session locked or decryption failed — show the overlay
                self.body     = ""
                self.isLocked = true
            }
        } else {
            self.body = note.body
        }
        self.suppressDirtyTracking = false
        self.isDirty = false
        updateDerivedState()
    }

    // MARK: – Actions

    /// Force an immediate save (e.g., when the note loses focus or the window closes).
    func saveNow() {
        saveTask?.cancel()
        performSave()
    }

    /// Async variant of `saveNow()` — useful in tests and `onDisappear` async contexts.
    func saveNowAsync() async {
        saveNow()
    }

    func insertWikilink(to target: Note) {
        body += " [[\(target.title)]]"
    }

    /// Appends `#tag` to the body if it isn't already present.
    func addTag(_ tag: String) {
        let cleaned = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty, !liveTags.contains(cleaned) else { return }
        // Append on its own line after a blank line for clean formatting.
        if body.hasSuffix("\n") {
            body += "\n#\(cleaned)"
        } else {
            body += "\n\n#\(cleaned)"
        }
    }

    /// Removes all occurrences of `#tag` from the body.
    func removeTag(_ tag: String) {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        // Match the full #tag token, preceded by non-word char or start, followed by non-tag char.
        let pattern = "(?<!\\w)#\(escaped)(?![A-Za-z0-9_/\\-])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var cleaned = regex.stringByReplacingMatches(in: body, range: range, withTemplate: "")
        // Collapse 3+ blank lines that removing an inline tag may leave behind.
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        body = cleaned
    }

    /// Called when the user edits the title field directly.
    /// Replaces (or inserts) the leading `# H1` in the body to match,
    /// keeping the title field and the body in sync.
    func applyTitleEdit(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let lines = body.components(separatedBy: "\n")
        if let firstH1 = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            // Replace existing H1
            var updated = lines
            updated[firstH1] = "# \(trimmed)"
            body = updated.joined(separator: "\n")
        } else {
            // No H1 yet — prepend one
            body = "# \(trimmed)\n\n" + body
        }
    }

    func toggleBacklinksPanel() {
        showBacklinksPanel.toggle()
    }

    func togglePinned() {
        let updated = Note(
            id: note.id,
            fileURL: note.fileURL,
            title: note.title,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: !note.isPinned,
            tags: note.tags
        )
        store.save(updated)
        note = updated
    }

    // MARK: – Encryption actions

    /// Called by `LockedNoteOverlay` after the user successfully unlocks.
    /// Decrypts the on-disk body and arms the editor for normal editing.
    func unlockAndDecrypt() {
        guard isEncryptedNote else { return }
        let service = NoteEncryptionService.shared
        guard service.isUnlocked else { return }

        if let latest = store.notes.first(where: { $0.id == note.id }) {
            note = latest
        }

        guard let plaintext = try? service.decrypt(note.body) else { return }
        suppressDirtyTracking = true
        body = plaintext
        suppressDirtyTracking = false
        isDirty  = false
        isLocked = false
        updateDerivedState()
    }

    /// Toggles encryption at the storage level.
    ///
    /// - When the note is plaintext: encrypts the current body on disk and marks
    ///   `isEncryptedNote = true`.  The ViewModel continues working with the
    ///   plaintext body in memory.
    /// - When the note is encrypted: decrypts the on-disk file and marks
    ///   `isEncryptedNote = false`.
    ///
    /// Requires the session to be unlocked.
    func toggleEncryption() {
        guard NoteEncryptionService.shared.isUnlocked else { return }
        if isEncryptedNote {
            // Remove encryption from disk
            try? store.decryptNote(note)
            isEncryptedNote = false
        } else {
            // First flush any unsaved edits as plaintext, then encrypt
            saveNow()
            if let fresh = store.notes.first(where: { $0.id == note.id }) {
                note = fresh
            }
            try? store.encryptNote(note)
            isEncryptedNote = true
        }
        // Refresh our note reference so title / tags stay in sync
        if let updated = store.notes.first(where: { $0.id == note.id }) {
            note = updated
        }
    }

    // MARK: – Auto-save

    private func scheduleSave() {
        saveTask?.cancel()
        // Read the delay from UserDefaults each time so Settings changes apply
        // immediately without requiring a ViewModel re-init.
        let delay = UserDefaults.standard.double(forKey: Prefs.autoSaveDelay)
        let seconds = delay > 0 ? delay : 1.5
        saveTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            performSave()
        }
    }

    private func performSave() {
        guard isDirty, !isLocked else { return }
        isSaving = true

        // When the note is encrypted, re-encrypt the plaintext before writing.
        let bodyToSave: String
        if isEncryptedNote {
            guard let encrypted = try? NoteEncryptionService.shared.encrypt(body) else {
                isSaving = false
                return
            }
            bodyToSave = encrypted
        } else {
            bodyToSave = body
        }

        let updated = Note(
            id: note.id,
            fileURL: note.fileURL,
            title: WikilinkParser.extractTitle(from: body, fallback: note.title),
            body: bodyToSave,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: note.isPinned,
            tags: WikilinkParser.extractTags(from: body)
        )
        store.save(updated)
        note = updated
        isDirty  = false
        isSaving = false
    }

    // MARK: – Derived state

    private func updateDerivedState() {
        // Word count (runs off-main for long notes).
        // Cancel any in-flight computation so stale results never overwrite fresher ones.
        updateTask?.cancel()
        let text = body
        updateTask = Task.detached(priority: .utility) { [weak self] in
            let words = text.split { $0.isWhitespace }.count
            let chars = text.filter { !$0.isWhitespace }.count
            let links = WikilinkParser.extractLinks(from: text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.wordCount = words
                self.charCount = chars
                self.outboundLinks = links
                self.refreshBacklinks()
            }
        }
    }

    private func refreshBacklinks() {
        backlinkNotes = store.backlinks(for: note)
    }
}
