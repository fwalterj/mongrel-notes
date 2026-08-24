import XCTest
@testable import SharedFoundation

/// Tests for MarkdownHTMLConverter — the swift-markdown-powered renderer.
/// These verify the HTML output for correctness without depending on a browser.
final class MarkdownHTMLConverterTests: XCTestCase {

    private func html(_ md: String) -> String {
        MarkdownHTMLConverter.html(from: md)
    }

    // MARK: – Headings

    func test_h1() {
        let out = html("# Hello")
        XCTAssertTrue(out.contains("<h1>Hello</h1>"), "Expected <h1>, got: \(out)")
    }

    func test_h2() {
        XCTAssertTrue(html("## Section").contains("<h2>Section</h2>"))
    }

    func test_h3() {
        XCTAssertTrue(html("### Sub").contains("<h3>Sub</h3>"))
    }

    // MARK: – Paragraphs

    func test_paragraph() {
        XCTAssertTrue(html("Hello world.").contains("<p>Hello world.</p>"))
    }

    func test_multipleParagraphs() {
        let out = html("First.\n\nSecond.")
        XCTAssertTrue(out.contains("<p>First.</p>"))
        XCTAssertTrue(out.contains("<p>Second.</p>"))
    }

    // MARK: – Inline formatting

    func test_bold() {
        XCTAssertTrue(html("**bold**").contains("<strong>bold</strong>"))
    }

    func test_italic() {
        XCTAssertTrue(html("*italic*").contains("<em>italic</em>"))
    }

    func test_inlineCode() {
        XCTAssertTrue(html("`code`").contains("<code>code</code>"))
    }

    // MARK: – Code block

    func test_fencedCodeBlock() {
        let out = html("```swift\nlet x = 1\n```")
        XCTAssertTrue(out.contains("<pre>"), "Expected <pre>, got: \(out)")
        XCTAssertTrue(out.contains("<code"))
        XCTAssertTrue(out.contains("let x = 1"))
    }

    func test_fencedCodeBlock_language() {
        let out = html("```python\nprint('hi')\n```")
        XCTAssertTrue(out.contains("language-python"), "Got: \(out)")
    }

    // MARK: – Lists

    func test_unorderedList() {
        let out = html("- one\n- two\n- three")
        XCTAssertTrue(out.contains("<ul>"))
        XCTAssertTrue(out.contains("<li>"))
        XCTAssertTrue(out.contains("one"))
        XCTAssertTrue(out.contains("two"))
    }

    func test_orderedList() {
        let out = html("1. first\n2. second")
        XCTAssertTrue(out.contains("<ol>"))
        XCTAssertTrue(out.contains("<li>"))
    }

    func test_taskListChecked() {
        let out = html("- [x] done")
        XCTAssertTrue(out.contains("checkbox"), "Expected checkbox, got: \(out)")
        XCTAssertTrue(out.contains("checked"))
    }

    func test_taskListUnchecked() {
        let out = html("- [ ] todo")
        XCTAssertTrue(out.contains("checkbox"))
        XCTAssertFalse(out.contains(" checked"))
    }

    // MARK: – Links

    func test_markdownLink() {
        let out = html("[Click me](https://example.com)")
        XCTAssertTrue(out.contains("<a href=\"https://example.com\">Click me</a>"), "Got: \(out)")
    }

    // MARK: – Blockquote

    func test_blockquote() {
        let out = html("> Quote text")
        XCTAssertTrue(out.contains("<blockquote>"))
        XCTAssertTrue(out.contains("Quote text"))
    }

    // MARK: – Horizontal rule

    func test_thematicBreak() {
        XCTAssertTrue(html("---").contains("<hr>"))
    }

    // MARK: – HTML escaping

    func test_htmlEscaping_lt() {
        let out = html("Use `a < b`.")
        XCTAssertTrue(out.contains("&lt;"), "Got: \(out)")
    }

    func test_htmlEscaping_amp() {
        let out = html("A & B")
        XCTAssertTrue(out.contains("&amp;"), "Got: \(out)")
    }

    func test_htmlEscaping_gt() {
        let out = html("a > b in prose.")
        XCTAssertTrue(out.contains("&gt;"), "Got: \(out)")
    }

    // MARK: – Wikilinks extension

    func test_wikilink_plain() {
        let out = html("See [[My Note]] for details.")
        XCTAssertTrue(out.contains("<span class=\"wikilink\">My Note</span>"), "Got: \(out)")
    }

    func test_wikilink_withAlias() {
        let out = html("[[Target Note|Show This]]")
        XCTAssertTrue(out.contains("<span class=\"wikilink\">Show This</span>"), "Got: \(out)")
        XCTAssertFalse(out.contains("Target Note"), "Alias should hide target, got: \(out)")
    }

    func test_wikilink_multipleOnOneLine() {
        let out = html("[[A]] and [[B]] are linked.")
        XCTAssertTrue(out.contains("class=\"wikilink\">A<"))
        XCTAssertTrue(out.contains("class=\"wikilink\">B<"))
    }

    // MARK: – Tag extension

    func test_tag_singleHashtag() {
        let out = html("Tagged as #swift here.")
        XCTAssertTrue(out.contains("<span class=\"tag\">#swift</span>"), "Got: \(out)")
    }

    func test_tag_doesNotMatchDollar() {
        let out = html("Price: $100")
        XCTAssertFalse(out.contains("class=\"tag\""), "Dollar should not produce a tag, got: \(out)")
    }

    // MARK: – Empty / edge cases

    func test_empty() {
        XCTAssertEqual(html("").trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func test_onlyNewlines() {
        let out = html("\n\n\n")
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    // MARK: – Table

    func test_table_producesTableTag() {
        let md = """
        | Col A | Col B |
        |-------|-------|
        | 1     | 2     |
        """
        let out = html(md)
        XCTAssertTrue(out.contains("<table>"), "Got: \(out)")
        XCTAssertTrue(out.contains("<th>"))
        XCTAssertTrue(out.contains("<td>"))
    }
}
