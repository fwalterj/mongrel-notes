import XCTest
@testable import MongrelNotes
import SharedFoundation

/// Tests for NoteTemplate and TemplateStore.
/// Runs in the MongrelNotesTests Xcode target.
final class TemplateStoreTests: XCTestCase {

    // MARK: – NoteTemplate.instantiate (variable substitution)

    func test_instantiate_titleSubstituted() {
        let t = NoteTemplate(id: UUID(), name: "T", body: "# {{title}}", icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "My Note")
        XCTAssertTrue(result.contains("# My Note"), "Got: \(result)")
        XCTAssertFalse(result.contains("{{title}}"))
    }

    func test_instantiate_dateSubstituted() {
        let t = NoteTemplate(id: UUID(), name: "T", body: "Date: {{date}}", icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "X", date: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(result.contains("{{date}}"), "Date var should be substituted, got: \(result)")
    }

    func test_instantiate_isoDateSubstituted() {
        let t = NoteTemplate(id: UUID(), name: "T", body: "ISO: {{date-iso}}", icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "X", date: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(result.contains("{{date-iso}}"))
        XCTAssertTrue(result.contains("1970-01-01"), "Got: \(result)")
    }

    func test_instantiate_timeSubstituted() {
        let t = NoteTemplate(id: UUID(), name: "T", body: "{{time}}", icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "X")
        XCTAssertFalse(result.contains("{{time}}"), "Got: \(result)")
    }

    func test_instantiate_unknownVariablesLeftIntact() {
        let t = NoteTemplate(id: UUID(), name: "T", body: "{{unknown}}", icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "X")
        // Unknown vars should not be silently dropped; they pass through unchanged.
        XCTAssertTrue(result.contains("{{unknown}}"))
    }

    func test_instantiate_multipleSubstitutionsInOneBody() {
        let body = "# {{title}}\n\n**Date:** {{date}}\n**ISO:** {{date-iso}}"
        let t = NoteTemplate(id: UUID(), name: "T", body: body, icon: "doc", isBuiltIn: false)
        let result = t.instantiate(title: "Sprint Review", date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(result.contains("# Sprint Review"))
        XCTAssertTrue(result.contains("1970-01-01"))
        XCTAssertFalse(result.contains("{{"))
    }

    // MARK: – Built-in templates

    func test_builtIns_notEmpty() {
        XCTAssertFalse(NoteTemplate.builtIns.isEmpty)
    }

    func test_builtIns_blankIsFirst() {
        XCTAssertEqual(NoteTemplate.builtIns.first?.name, "Blank")
    }

    func test_builtIns_allHaveIcons() {
        for t in NoteTemplate.builtIns {
            XCTAssertFalse(t.icon.isEmpty, "\(t.name) has no icon")
        }
    }

    func test_builtIns_allInstantiateWithoutCrash() {
        for t in NoteTemplate.builtIns {
            let result = t.instantiate(title: "Test")
            XCTAssertFalse(result.isEmpty, "\(t.name) produced empty output")
        }
    }

    func test_builtIns_allHaveUniqueIDs() {
        let ids = NoteTemplate.builtIns.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count, "Duplicate IDs detected in built-ins")
    }

    // MARK: – TemplateStore — file-based loading

    func test_templateStore_loadsBuiltInsWhenNoDirExists() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmpl-\(UUID().uuidString)")
        let store = await TemplateStore(vaultURL: tmpDir)
        // No _templates/ directory → falls back to built-ins only.
        let templates = await store.templates
        XCTAssertEqual(templates.count, NoteTemplate.builtIns.count)
    }

    func test_templateStore_loadsCustomTemplateFromDisk() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmpl-\(UUID().uuidString)")
        let templatesDir = tmpDir.appendingPathComponent("_templates")
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        let customFile = templatesDir.appendingPathComponent("Custom Template.md")
        try "# {{title}}\n\nCustom content.".write(to: customFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = await TemplateStore(vaultURL: tmpDir)
        // Give the async Task in init time to finish
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        let templates = await store.templates
        XCTAssertTrue(templates.contains(where: { $0.name == "Custom Template" }),
                      "Templates: \(templates.map(\.name))")
    }

    func test_templateStore_customOverridesBuiltIn() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmpl-override-\(UUID().uuidString)")
        let templatesDir = tmpDir.appendingPathComponent("_templates")
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)

        // A custom "Meeting Notes" template overrides the built-in
        let customFile = templatesDir.appendingPathComponent("Meeting Notes.md")
        try "# {{title}} — Custom".write(to: customFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = await TemplateStore(vaultURL: tmpDir)
        try await Task.sleep(nanoseconds: 100_000_000)
        let templates = await store.templates
        let meetingTemplates = templates.filter { $0.name == "Meeting Notes" }
        XCTAssertEqual(meetingTemplates.count, 1, "Should be exactly one Meeting Notes template (custom overrides built-in)")
        XCTAssertFalse(meetingTemplates.first?.isBuiltIn == true, "Custom template should not be marked isBuiltIn")
    }
}
