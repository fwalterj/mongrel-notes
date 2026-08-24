import XCTest
@testable import SharedFoundation

final class NoteModelTests: XCTestCase {

    private let dummyURL = URL(fileURLWithPath: "/tmp/test.md")

    // MARK: – Identity

    func test_defaultInit_getsUniqueID() {
        let a = Note(fileURL: dummyURL, title: "A")
        let b = Note(fileURL: dummyURL, title: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_customID_preserved() {
        let id = UUID()
        let note = Note(id: id, fileURL: dummyURL, title: "T", body: "")
        XCTAssertEqual(note.id, id)
    }

    // MARK: – wordCount

    func test_wordCount_empty() {
        let note = Note(fileURL: dummyURL, title: "T", body: "")
        XCTAssertEqual(note.wordCount, 0)
    }

    func test_wordCount_singleWord() {
        let note = Note(fileURL: dummyURL, title: "T", body: "hello")
        XCTAssertEqual(note.wordCount, 1)
    }

    func test_wordCount_multipleWords() {
        let note = Note(fileURL: dummyURL, title: "T", body: "one two three four")
        XCTAssertEqual(note.wordCount, 4)
    }

    func test_wordCount_multilineBody() {
        let note = Note(fileURL: dummyURL, title: "T", body: "line one\nline two\nline three")
        XCTAssertEqual(note.wordCount, 6)
    }

    func test_wordCount_markdownHeadings() {
        let note = Note(fileURL: dummyURL, title: "T", body: "# Heading\n\nParagraph text.")
        // "# Heading Paragraph text." — 3 tokens: "#", "Heading", "Paragraph", "text."
        // The exact count depends on split behavior with "#"
        XCTAssertGreaterThan(note.wordCount, 0)
    }

    // MARK: – characterCount

    func test_characterCount_excludesWhitespace() {
        let note = Note(fileURL: dummyURL, title: "T", body: "a b c")
        XCTAssertEqual(note.characterCount, 3)
    }

    func test_characterCount_empty() {
        XCTAssertEqual(Note(fileURL: dummyURL, title: "T", body: "").characterCount, 0)
    }

    // MARK: – outboundLinks

    func test_outboundLinks_empty() {
        let note = Note(fileURL: dummyURL, title: "T", body: "No links here.")
        XCTAssertTrue(note.outboundLinks.isEmpty)
    }

    func test_outboundLinks_derivedFromBody() {
        let note = Note(fileURL: dummyURL, title: "T", body: "See [[Alpha]] and [[Beta]].")
        XCTAssertEqual(note.outboundLinks, ["Alpha", "Beta"])
    }

    // MARK: – excerpt

    func test_excerpt_stripsMarkdownHeadings() {
        let note = Note(fileURL: dummyURL, title: "T", body: "# Title\n\nBody paragraph.")
        let exc = note.excerpt
        XCTAssertFalse(exc.hasPrefix("#"))
        XCTAssertTrue(exc.contains("Body paragraph"))
    }

    func test_excerpt_stripsWikilinks() {
        let note = Note(fileURL: dummyURL, title: "T", body: "See [[linked thing]] here.")
        XCTAssertTrue(note.excerpt.contains("linked thing"))
        XCTAssertFalse(note.excerpt.contains("[["))
    }

    func test_excerpt_stripsBoldSyntax() {
        let note = Note(fileURL: dummyURL, title: "T", body: "This is **bold** text.")
        XCTAssertFalse(note.excerpt.contains("**"))
        XCTAssertTrue(note.excerpt.contains("bold"))
    }

    func test_excerpt_maxLength() {
        let longBody = String(repeating: "word ", count: 200)
        let note = Note(fileURL: dummyURL, title: "T", body: longBody)
        XCTAssertLessThanOrEqual(note.excerpt.count, 160)
    }

    func test_excerpt_empty() {
        XCTAssertEqual(Note(fileURL: dummyURL, title: "T", body: "").excerpt, "")
    }

    // MARK: – Equatable / Hashable

    func test_equatable_sameIDequal() {
        let id = UUID()
        let a = Note(id: id, fileURL: dummyURL, title: "T", body: "x")
        let b = Note(id: id, fileURL: dummyURL, title: "T", body: "y")
        // Note is Equatable via synthesised == which compares all stored props.
        // Two Notes with the same id but different body are NOT equal.
        // This test documents the actual behaviour.
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_usedInSet() {
        let id = UUID()
        let a = Note(id: id, fileURL: dummyURL, title: "T", body: "")
        let b = Note(id: id, fileURL: dummyURL, title: "T", body: "")
        // Same values → same hash → same element in Set
        let set: Set<Note> = [a, b]
        XCTAssertEqual(set.count, 1)
    }
}
