import Foundation
import Combine
import CoreSpotlight
import UniformTypeIdentifiers

/// Manages reading, writing, watching, and indexing all notes inside a vault directory.
/// Notes are stored as plain `.md` files. This class is the single source of truth.
@MainActor
public final class VaultStore: ObservableObject {

    // MARK: – Published state

    @Published public private(set) var notes: [Note] = []
    @Published public private(set) var folders: [NoteFolder] = []
    @Published public private(set) var linkGraph: LinkGraph = LinkGraph(notes: [])
    @Published public private(set) var isLoading: Bool = false

    // MARK: – Properties

    public let vault: Vault
    nonisolated(unsafe) private var fileEventSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var watchedDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.mongrel.notes.vaultstore", qos: .utility)

    // MARK: – Init / Deinit

    public init(vault: Vault) {
        self.vault = vault
    }

    deinit {
        fileEventSource?.cancel()
        fileEventSource = nil
        if watchedDescriptor >= 0 {
            close(watchedDescriptor)
            watchedDescriptor = -1
        }
    }

    // MARK: – Load

    public func loadVault() async {
        isLoading = true
        defer { isLoading = false }
        let url = vault.rootURL
        let loaded = await Task.detached(priority: .userInitiated) { [url] in
            Self.scanDirectory(url)
        }.value
        notes = loaded.notes
        folders = loaded.folders
        linkGraph = LinkGraph(notes: loaded.notes)
        reindexAll()
        startWatching()
    }

    // MARK: – CRUD

    public func createNote(title: String, body: String? = nil, in folder: NoteFolder? = nil) -> Note {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = folder?.directoryURL ?? vault.rootURL
        let filenameStem = sanitiseFilename(resolvedTitle)
        let url = makeUniqueMarkdownURL(in: dir, baseName: filenameStem)
        let initialBody = body ?? "# \(resolvedTitle)\n\n"
        let note = Note(fileURL: url, title: resolvedTitle, body: initialBody)
        writeNote(note)
        notes.append(note)
        linkGraph = LinkGraph(notes: notes)
        return note
    }

    public func save(_ note: Note) {
        writeNote(note)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.append(note)
        }
        linkGraph = LinkGraph(notes: notes)
    }

    public func delete(_ note: Note) {
        try? FileManager.default.trashItem(at: note.fileURL, resultingItemURL: nil)
        deindexFromSpotlight(note)
        notes.removeAll { $0.id == note.id }
        linkGraph = LinkGraph(notes: notes)
    }

    public func rename(_ note: Note, to newTitle: String) -> Note {
        let dir = note.fileURL.deletingLastPathComponent()
        let resolvedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilename = sanitiseFilename(resolvedTitle)
        let newURL = makeUniqueMarkdownURL(in: dir, baseName: newFilename, excluding: note.fileURL)

        if newURL != note.fileURL {
            do {
                try FileManager.default.moveItem(at: note.fileURL, to: newURL)
            } catch {
                print("[VaultStore] Rename failed: \(error)")
                return note
            }
        }

        var updated = note
        updated = Note(
            id: note.id,
            fileURL: newURL,
            title: resolvedTitle,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: note.isPinned,
            tags: note.tags
        )
        save(updated)
        return updated
    }

    // MARK: – Import

    /// Copy (or move) an external `.md` file into the vault.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the `.md` file to import.
    ///   - folder:    Optional destination folder inside the vault; defaults to the vault root.
    ///   - move:      When `true` the source file is moved; when `false` (default) it is copied.
    /// - Returns: The new `Note` on success, `nil` if the file could not be read.
    @discardableResult
    public func importFile(at sourceURL: URL, into folder: NoteFolder? = nil, move: Bool = false) -> Note? {
        guard sourceURL.pathExtension.lowercased() == "md" else { return nil }
        guard let body = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            print("[VaultStore] Import failed: could not read text from \(sourceURL.path)")
            return nil
        }
        let title = WikilinkParser.extractTitle(from: body, fallback: sourceURL.deletingPathExtension().lastPathComponent)

        let dir = folder?.directoryURL ?? vault.rootURL
        // Avoid filename collision by appending a counter if needed.
        var destURL = dir.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            destURL = dir.appendingPathComponent("\(stem)-\(counter).md")
            counter += 1
        }

        do {
            if move {
                try FileManager.default.moveItem(at: sourceURL, to: destURL)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        } catch {
            print("[VaultStore] Import failed: \(error)")
            return nil
        }

        let note = Note(fileURL: destURL, title: title, body: body)
        notes.append(note)
        notes.sort { $0.title < $1.title }
        linkGraph = LinkGraph(notes: notes)
        indexInSpotlight(note)
        return note
    }

    // MARK: – Encryption

    /// Encrypts a note's body in place and persists the ciphertext to disk.
    ///
    /// This is a **storage-level** operation: it re-encodes the on-disk file so
    /// the note is encrypted at rest.  The caller (e.g. the editor toolbar) is
    /// responsible for ensuring the session is unlocked first.
    ///
    /// - Throws: `EncryptionError.locked` if no session key is in memory,
    ///           or other `EncryptionError` variants on failure.
    public func encryptNote(_ note: Note) throws {
        guard !note.isEncrypted else { return }   // already encrypted — no-op
        let encryptedBody = try NoteEncryptionService.shared.encrypt(note.body)
        let updated = Note(
            id: note.id,
            fileURL: note.fileURL,
            title: note.title,
            body: encryptedBody,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: note.isPinned,
            tags: note.tags
        )
        save(updated)
    }

    /// Decrypts a note's body in place and persists the plaintext to disk.
    ///
    /// After this call the note is stored unencrypted.  The session must be
    /// unlocked so the key is available.
    ///
    /// - Throws: `EncryptionError.locked` or `EncryptionError.decryptionFailed`.
    public func decryptNote(_ note: Note) throws {
        guard note.isEncrypted else { return }   // already plaintext — no-op
        let plainBody = try NoteEncryptionService.shared.decrypt(note.body)
        let updated = Note(
            id: note.id,
            fileURL: note.fileURL,
            title: note.title,
            body: plainBody,
            createdAt: note.createdAt,
            updatedAt: Date(),
            isPinned: note.isPinned,
            tags: note.tags
        )
        save(updated)
    }

    // MARK: – Search

    public func search(query: String) -> [Note] {
        guard !query.isEmpty else { return notes }
        let q = query.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(q) ||
            $0.body.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: – Backlinks

    public func backlinks(for note: Note) -> [Note] {
        let ids = linkGraph.backlinks(for: note.id)
        return notes.filter { ids.contains($0.id) }
    }

    // MARK: – File watching

    private func startWatching() {
        stopWatching()
        let path = vault.rootURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.loadVault()
            }
        }
        source.resume()
        fileEventSource = source
    }

    private func stopWatching() {
        fileEventSource?.cancel()
        fileEventSource = nil
        if watchedDescriptor >= 0 {
            close(watchedDescriptor)
            watchedDescriptor = -1
        }
    }

    // MARK: – Private helpers

    private func writeNote(_ note: Note) {
        let dir = note.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? note.body.write(to: note.fileURL, atomically: true, encoding: .utf8)
        // Persist UUID in extended attributes so renames don't break identity.
        note.fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            var uuid = note.id
            withUnsafeBytes(of: &uuid) { ptr in
                setxattr(path, "com.mongrel.notes.uuid", ptr.baseAddress, ptr.count, 0, 0)
            }
        }
        indexInSpotlight(note)
    }

    // MARK: – Spotlight indexing

    /// The domain identifier scopes our items so we can remove them cleanly
    /// without touching Spotlight items from other apps.
    private static let spotlightDomain = "com.mongrel.notes"

    /// Mirrors the `Prefs.spotlightEnabled` key defined in the app target.
    /// Reading UserDefaults directly avoids a cross-module dependency on `Prefs`.
    /// Defaults to `true` when the key has never been written (same as the UI default).
    private var isSpotlightEnabled: Bool {
        let val = UserDefaults.standard.object(forKey: "spotlightEnabled")
        return val == nil ? true : UserDefaults.standard.bool(forKey: "spotlightEnabled")
    }

    /// Index (or update) a note in Core Spotlight so it appears in system search.
    private func indexInSpotlight(_ note: Note) {
        guard isSpotlightEnabled else { return }
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title          = note.title
        attrs.textContent    = note.body
        attrs.keywords       = note.tags
        attrs.contentURL     = note.fileURL
        attrs.contentCreationDate    = note.createdAt
        attrs.contentModificationDate = note.updatedAt

        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: Self.spotlightDomain,
            attributeSet: attrs
        )
        // Items expire after 1 month of inactivity; set a far future date instead.
        item.expirationDate = .distantFuture

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error { print("[Spotlight] Index error: \(error)") }
        }
    }

    /// Remove a note from the Spotlight index when it is deleted.
    private func deindexFromSpotlight(_ note: Note) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [note.id.uuidString]
        ) { error in
            if let error { print("[Spotlight] Deindex error: \(error)") }
        }
    }

    /// Re-index every note in the vault — call after a full reload to keep
    /// Spotlight in sync with the on-disk state.
    /// Also called from `SettingsView` (outside this module), so must be `public`.
    public func reindexAll() {
        guard isSpotlightEnabled else { return }
        // Delete stale items for this domain first, then re-add all.
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [Self.spotlightDomain]
        ) { [weak self] _ in
            guard let self else { return }
            let items: [CSSearchableItem] = self.notes.map { note in
                let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
                attrs.title           = note.title
                attrs.textContent     = note.body
                attrs.keywords        = note.tags
                attrs.contentURL      = note.fileURL
                attrs.contentCreationDate     = note.createdAt
                attrs.contentModificationDate = note.updatedAt
                let item = CSSearchableItem(
                    uniqueIdentifier: note.id.uuidString,
                    domainIdentifier: Self.spotlightDomain,
                    attributeSet: attrs
                )
                item.expirationDate = .distantFuture
                return item
            }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error { print("[Spotlight] Bulk index error: \(error)") }
            }
        }
    }

    private nonisolated static func scanDirectory(_ url: URL) -> (notes: [Note], folders: [NoteFolder]) {
        var notes: [Note] = []
        var folders: [NoteFolder] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        for case let fileURL as URL in enumerator {
            let res = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey])
            if res?.isDirectory == true {
                let folder = NoteFolder(
                    name: fileURL.lastPathComponent,
                    directoryURL: fileURL
                )
                folders.append(folder)
                continue
            }
            guard fileURL.pathExtension == "md" else { continue }

            let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let title = WikilinkParser.extractTitle(from: body, fallback: stem)
            let created = res?.creationDate ?? Date()
            let modified = res?.contentModificationDate ?? Date()
            let tags = WikilinkParser.extractTags(from: body)

            // Try to read UUID from extended attributes.
            var noteID = UUID()
            fileURL.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                var buf = UUID()
                let size = getxattr(path, "com.mongrel.notes.uuid", &buf, MemoryLayout<UUID>.size, 0, 0)
                if size == MemoryLayout<UUID>.size { noteID = buf }
            }

            let note = Note(
                id: noteID,
                fileURL: fileURL,
                title: title,
                body: body,
                createdAt: created,
                updatedAt: modified,
                tags: tags
            )
            notes.append(note)
        }
        return (notes, folders)
    }

    private func sanitiseFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.init(charactersIn: " -_"))
        let sanitized = title
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
            .prefix(80)
            .description
        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    private func makeUniqueMarkdownURL(in directory: URL, baseName: String, excluding originalURL: URL? = nil) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) && candidate != originalURL {
            candidate = directory.appendingPathComponent("\(baseName)-\(counter)").appendingPathExtension("md")
            counter += 1
        }
        return candidate
    }
}
