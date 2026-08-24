import XCTest
@testable import SharedFoundation

/// Tests for VaultStore CRUD operations using a temporary directory on disk.
/// These run against real file I/O without depending on any macOS framework UI.
@MainActor
final class VaultStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: VaultStore!

    override func setUp() async throws {
        try await super.setUp()
        // Create a fresh temp directory for each test.
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let vault = Vault(name: "Test Vault", rootURL: tmpDir, isCloudBacked: false)
        store = VaultStore(vault: vault)
        await store.loadVault()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: – createNote

    func test_createNote_writesFileToDisk() {
        let note = store.createNote(title: "Hello World")
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.fileURL.path),
                      "Expected file at \(note.fileURL.path)")
    }

    func test_createNote_fileContainsH1() {
        let note = store.createNote(title: "My Title")
        let content = try? String(contentsOf: note.fileURL, encoding: .utf8)
        XCTAssertTrue(content?.contains("# My Title") == true, "Content: \(content ?? "(nil)")")
    }

    func test_createNote_appearsInNotes() {
        let note = store.createNote(title: "New Note")
        XCTAssertTrue(store.notes.contains { $0.id == note.id })
    }

    func test_createNote_titleSanitised() {
        // Colons and slashes are invalid in filenames.
        let note = store.createNote(title: "A: B/C")
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.fileURL.path),
                      "File should exist even with special chars in title")
    }

    func test_createNote_duplicateTitle_generatesUniqueFile() {
        let first = store.createNote(title: "Same")
        let second = store.createNote(title: "Same")
        XCTAssertNotEqual(first.fileURL.path, second.fileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.fileURL.path))
    }

    func test_createNote_emptyTitle_fallsBackToUntitled() {
        let note = store.createNote(title: "   ")
        XCTAssertEqual(note.title, "Untitled")
        XCTAssertEqual(note.fileURL.deletingPathExtension().lastPathComponent, "Untitled")
    }

    // MARK: – save

    func test_save_updatesNoteInStore() {
        var note = store.createNote(title: "Original")
        note = Note(id: note.id, fileURL: note.fileURL, title: "Original",
                    body: "Updated body.", createdAt: note.createdAt, updatedAt: Date())
        store.save(note)
        let saved = store.notes.first(where: { $0.id == note.id })
        XCTAssertEqual(saved?.body, "Updated body.")
    }

    func test_save_writesUpdatedBodyToDisk() throws {
        var note = store.createNote(title: "Disk Write")
        note = Note(id: note.id, fileURL: note.fileURL, title: "Disk Write",
                    body: "Persisted content.", createdAt: note.createdAt, updatedAt: Date())
        store.save(note)
        let content = try String(contentsOf: note.fileURL, encoding: .utf8)
        XCTAssertEqual(content, "Persisted content.")
    }

    func test_save_updatesLinkGraph() {
        var a = store.createNote(title: "Alpha")
        let b = store.createNote(title: "Beta")
        a = Note(id: a.id, fileURL: a.fileURL, title: "Alpha",
                 body: "[[Beta]]", createdAt: a.createdAt, updatedAt: Date())
        store.save(a)
        XCTAssertFalse(store.linkGraph.backlinks(for: b.id).isEmpty,
                       "Beta should have Alpha as a backlink")
    }

    // MARK: – delete

    func test_delete_removesFromNotes() {
        let note = store.createNote(title: "To Delete")
        store.delete(note)
        XCTAssertFalse(store.notes.contains(where: { $0.id == note.id }))
    }

    func test_delete_movesFileToTrash() {
        let note = store.createNote(title: "Trashed")
        store.delete(note)
        // After trashing, the file should no longer be at its original location.
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.fileURL.path),
                       "File should be trashed, not at original path")
    }

    // MARK: – rename

    func test_rename_updatesTitle() {
        let note = store.createNote(title: "Old Name")
        let renamed = store.rename(note, to: "New Name")
        XCTAssertEqual(renamed.title, "New Name")
    }

    func test_rename_movesFile() {
        let note = store.createNote(title: "Before")
        let renamed = store.rename(note, to: "After")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.fileURL.path))
    }

    // MARK: – search

    func test_search_findsMatchingNote() {
        let _ = store.createNote(title: "Swift Concurrency")
        let results = store.search(query: "Concurrency")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.title == "Swift Concurrency" }))
    }

    func test_search_emptyQueryReturnsAll() {
        let _ = store.createNote(title: "A")
        let _ = store.createNote(title: "B")
        XCTAssertEqual(store.search(query: "").count, store.notes.count)
    }

    func test_search_noMatch_returnsEmpty() {
        let _ = store.createNote(title: "Apples")
        XCTAssertTrue(store.search(query: "xyzzy").isEmpty)
    }

    // MARK: – importFile

    func test_importFile_copiesMarkdownFile() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).md")
        try "# Imported Note\n\nContent.".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let note = store.importFile(at: source)
        XCTAssertNotNil(note)
        XCTAssertTrue(FileManager.default.fileExists(atPath: note!.fileURL.path))
        XCTAssertEqual(note?.title, "Imported Note")
    }

    func test_importFile_nonMarkdownFile_returnsNil() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).txt")
        try "not md".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        XCTAssertNil(store.importFile(at: source))
    }

    func test_importFile_collisionHandled() throws {
        let filename = "same-name.md"
        let source1 = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let source2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("alt-\(UUID().uuidString).md")
        try "# First".write(to: source1, atomically: true, encoding: .utf8)
        try "# Second".write(to: source2, atomically: true, encoding: .utf8)

        // Put the first one in the vault directly so there's already a same-name.md
        let existing = tmpDir.appendingPathComponent(filename)
        try "# Existing".write(to: existing, atomically: true, encoding: .utf8)

        let note = store.importFile(at: source1)
        // Should succeed and create a non-colliding filename.
        XCTAssertNotNil(note)
        XCTAssertNotEqual(note?.fileURL.path, existing.path)

        try? FileManager.default.removeItem(at: source1)
        try? FileManager.default.removeItem(at: source2)
    }
}
