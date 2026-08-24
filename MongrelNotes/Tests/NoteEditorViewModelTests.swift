import XCTest
@testable import MongrelNotes
import SharedFoundation

/// Tests for NoteEditorViewModel — auto-save, word count, title extraction, and backlinks.
@MainActor
final class NoteEditorViewModelTests: XCTestCase {

    private var tmpDir: URL!
    private var store: VaultStore!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let vault = Vault(name: "Test", rootURL: tmpDir, isCloudBacked: false)
        store = VaultStore(vault: vault)
        await store.loadVault()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: – Initialisation

    func test_init_loadsNoteBody() {
        let note = store.createNote(title: "Hello")
        let vm = NoteEditorViewModel(note: note, store: store)
        XCTAssertEqual(vm.body, note.body)
    }

    func test_init_computesWordCount() async {
        let note = store.createNote(title: "T")
        var filled = note
        filled = Note(id: note.id, fileURL: note.fileURL, title: "T",
                      body: "one two three", createdAt: note.createdAt, updatedAt: Date())
        store.save(filled)
        let vm = NoteEditorViewModel(note: filled, store: store)
        await waitForDerivedState { vm.wordCount == 3 }
        XCTAssertEqual(vm.wordCount, 3)
    }

    // MARK: – noteID / title

    func test_noteID_matchesNote() {
        let note = store.createNote(title: "Alpha")
        let vm = NoteEditorViewModel(note: note, store: store)
        XCTAssertEqual(vm.noteID, note.id)
    }

    func test_title_extractedFromH1() {
        let note = store.createNote(title: "Fallback")
        var filled = note
        filled = Note(id: note.id, fileURL: note.fileURL, title: "Fallback",
                      body: "# My Real Title\n\nContent.", createdAt: note.createdAt, updatedAt: Date())
        store.save(filled)
        let vm = NoteEditorViewModel(note: filled, store: store)
        XCTAssertEqual(vm.title, "My Real Title")
    }

    func test_title_fallsBackToNoteTitle() {
        let note = store.createNote(title: "File Name")
        let vm = NoteEditorViewModel(note: note, store: store)
        // Default body is "# File Name\n\n" so title IS extracted from H1
        XCTAssertEqual(vm.title, "File Name")
    }

    // MARK: – Derived state on body change

    func test_bodyChange_updatesDirtyFlag() {
        let note = store.createNote(title: "Dirty")
        let vm = NoteEditorViewModel(note: note, store: store)
        XCTAssertFalse(vm.isDirty)
        vm.body = "Changed content"
        XCTAssertTrue(vm.isDirty)
    }

    func test_bodyChange_updatesWordCount() async {
        let note = store.createNote(title: "WC")
        let vm = NoteEditorViewModel(note: note, store: store)
        vm.body = "alpha beta gamma"
        await waitForDerivedState { vm.wordCount == 3 }
        XCTAssertEqual(vm.wordCount, 3)
    }

    func test_bodyChange_updatesOutboundLinks() async {
        let note = store.createNote(title: "Links")
        let vm = NoteEditorViewModel(note: note, store: store)
        vm.body = "See [[Target A]] and [[Target B]]."
        await waitForDerivedState { vm.outboundLinks.count == 2 }
        XCTAssertEqual(vm.outboundLinks, ["Target A", "Target B"])
    }

    // MARK: – Backlinks

    func test_backlinkNotes_updatesWhenStoreChanges() async throws {
        let hub  = store.createNote(title: "Hub")
        let src  = store.createNote(title: "Src")

        var srcFilled = src
        srcFilled = Note(id: src.id, fileURL: src.fileURL, title: "Src",
                         body: "[[Hub]]", createdAt: src.createdAt, updatedAt: Date())
        store.save(srcFilled)

        let vm = NoteEditorViewModel(note: hub, store: store)
        // Brief wait for @Published chain to settle
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.backlinkNotes.contains(where: { $0.id == src.id }),
                      "Backlinks: \(vm.backlinkNotes.map(\.title))")
    }

    // MARK: – saveNow

    func test_saveNow_persistsBodyToDisk() async throws {
        let note = store.createNote(title: "Persist")
        let vm = NoteEditorViewModel(note: note, store: store)
        vm.body = "Saved content."
        await vm.saveNowAsync()
        let onDisk = try String(contentsOf: note.fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "Saved content.")
    }

    func test_saveNow_clearsDirtyFlag() async {
        let note = store.createNote(title: "Dirty")
        let vm = NoteEditorViewModel(note: note, store: store)
        vm.body = "Changed"
        XCTAssertTrue(vm.isDirty)
        await vm.saveNowAsync()
        XCTAssertFalse(vm.isDirty)
    }

    func test_togglePinned_persistsPinnedState() {
        let note = store.createNote(title: "Pinned")
        let vm = NoteEditorViewModel(note: note, store: store)

        XCTAssertFalse(vm.isPinned)
        vm.togglePinned()

        XCTAssertTrue(vm.isPinned)
        XCTAssertTrue(store.notes.first(where: { $0.id == note.id })?.isPinned == true)
    }

    private func waitForDerivedState(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
