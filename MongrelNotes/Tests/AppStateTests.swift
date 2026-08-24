import XCTest
@testable import MongrelNotes
import SharedFoundation

/// Smoke tests for AppState vault management.
/// These are integration tests: real directories, real file I/O.
@MainActor
final class AppStateTests: XCTestCase {

    private var tmpDir: URL!
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // Use a fresh UserDefaults to avoid polluting the real app's vault list.
        appState = AppState(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: – openVault

    func test_openVault_addsToOpenVaults() async {
        await appState.openVault(at: tmpDir)
        XCTAssertEqual(appState.openVaults.count, 1)
    }

    func test_openVault_setsActiveVault() async {
        await appState.openVault(at: tmpDir)
        XCTAssertNotNil(appState.activeVault)
        XCTAssertEqual(
            appState.activeVault?.vault.rootURL.standardizedFileURL.path,
            tmpDir.standardizedFileURL.path
        )
    }

    func test_openVault_correctVaultName() async {
        await appState.openVault(at: tmpDir)
        XCTAssertEqual(appState.activeVault?.vault.name, tmpDir.lastPathComponent)
    }

    func test_openMultipleVaults_allPresent() async {
        let dir2 = tmpDir.appendingPathComponent("sub-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir2) }

        await appState.openVault(at: tmpDir)
        await appState.openVault(at: dir2)
        XCTAssertEqual(appState.openVaults.count, 2)
    }

    func test_openMultipleVaults_lastIsActive() async {
        let dir2 = tmpDir.appendingPathComponent("sub-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir2) }

        await appState.openVault(at: tmpDir)
        await appState.openVault(at: dir2)
        XCTAssertEqual(
            appState.activeVault?.vault.rootURL.standardizedFileURL.path,
            dir2.standardizedFileURL.path
        )
    }

    func test_openVault_samePathDoesNotDuplicate() async {
        await appState.openVault(at: tmpDir)
        await appState.openVault(at: tmpDir)
        XCTAssertEqual(appState.openVaults.count, 1)
    }

    // MARK: – closeVault

    func test_closeVault_removesFromList() async {
        await appState.openVault(at: tmpDir)
        guard let store = appState.activeVault else { XCTFail("No vault"); return }
        appState.closeVault(store)
        XCTAssertTrue(appState.openVaults.isEmpty)
    }

    func test_closeVault_fallsBackToPreviousActiveVault() async {
        let dir2 = tmpDir.appendingPathComponent("sub-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir2) }

        await appState.openVault(at: tmpDir)
        await appState.openVault(at: dir2)
        // dir2 is now active. Close it.
        appState.closeVault(appState.activeVault!)
        // Should fall back to tmpDir vault.
        XCTAssertNotNil(appState.activeVault)
    }

    func test_closeLastVault_activeVaultIsNil() async {
        await appState.openVault(at: tmpDir)
        appState.closeVault(appState.activeVault!)
        XCTAssertNil(appState.activeVault)
    }

    // MARK: – createOrOpenDailyNote

    func test_createOrOpenDailyNote_createsDotMdFile() async {
        await appState.openVault(at: tmpDir)
        let note = appState.createOrOpenDailyNote()
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.fileURL.pathExtension, "md")
    }

    func test_createOrOpenDailyNote_titleIsISODate() async {
        await appState.openVault(at: tmpDir)
        let note = appState.createOrOpenDailyNote()
        let today = ISO8601DateFormatter.dailyNoteFormatter.string(from: Date())
        XCTAssertEqual(note?.title, today)
    }

    func test_createOrOpenDailyNote_calledTwice_returnsSameNote() async {
        await appState.openVault(at: tmpDir)
        let first  = appState.createOrOpenDailyNote()
        let second = appState.createOrOpenDailyNote()
        XCTAssertEqual(first?.id, second?.id, "Second call should return existing daily note")
    }

    func test_createOrOpenDailyNote_noActiveVault_returnsNil() {
        XCTAssertNil(appState.createOrOpenDailyNote())
    }
}
