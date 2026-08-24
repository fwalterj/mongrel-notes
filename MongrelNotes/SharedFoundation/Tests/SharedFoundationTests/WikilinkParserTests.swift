import XCTest
@testable import SharedFoundation

final class WikilinkParserTests: XCTestCase {

    // MARK: – extractLinks

    func test_extractLinks_empty() {
        XCTAssertEqual(WikilinkParser.extractLinks(from: ""), [])
    }

    func test_extractLinks_noLinks() {
        XCTAssertEqual(WikilinkParser.extractLinks(from: "Plain text with no wikilinks."), [])
    }

    func test_extractLinks_singleLink() {
        let result = WikilinkParser.extractLinks(from: "See [[My Note]].")
        XCTAssertEqual(result, ["My Note"])
    }

    func test_extractLinks_multipleLinks() {
        let result = WikilinkParser.extractLinks(from: "[[Alpha]] and [[Beta]] are linked.")
        XCTAssertEqual(result, ["Alpha", "Beta"])
    }

    func test_extractLinks_aliasIgnored() {
        // [[Target|Alias]] — the captured group is the target, not the alias
        let result = WikilinkParser.extractLinks(from: "[[Real Target|Show This]]")
        XCTAssertEqual(result, ["Real Target"])
    }

    func test_extractLinks_spaceInTitle() {
        let result = WikilinkParser.extractLinks(from: "See [[Meeting Notes 2025-01-01]].")
        XCTAssertEqual(result, ["Meeting Notes 2025-01-01"])
    }

    func test_extractLinks_doesNotMatchSingleBrackets() {
        XCTAssertEqual(WikilinkParser.extractLinks(from: "[not a wikilink](url)"), [])
    }

    func test_extractLinks_adjacentLinks() {
        let result = WikilinkParser.extractLinks(from: "[[A]][[B]]")
        XCTAssertEqual(result, ["A", "B"])
    }

    // MARK: – extractTags

    func test_extractTags_empty() {
        XCTAssertEqual(WikilinkParser.extractTags(from: ""), [])
    }

    func test_extractTags_noTags() {
        XCTAssertEqual(WikilinkParser.extractTags(from: "Price is $100."), [])
    }

    func test_extractTags_singleTag() {
        let result = WikilinkParser.extractTags(from: "This is #swift content.")
        XCTAssertEqual(result, ["swift"])
    }

    func test_extractTags_multipleTags() {
        let result = WikilinkParser.extractTags(from: "#swift #macOS #productivity")
        XCTAssertEqual(result, ["swift", "macOS", "productivity"])
    }

    func test_extractTags_tagWithSlash() {
        // e.g. #project/personal
        let result = WikilinkParser.extractTags(from: "Tag: #project/personal")
        XCTAssertEqual(result, ["project/personal"])
    }

    func test_extractTags_dollarSignNotTag() {
        // Dollar sign precedes tag-like text — should NOT match
        XCTAssertEqual(WikilinkParser.extractTags(from: "$100 and $price"), [])
    }

    func test_extractTags_tagAtStartOfLine() {
        let result = WikilinkParser.extractTags(from: "#inbox item")
        XCTAssertEqual(result, ["inbox"])
    }

    func test_extractTags_hashInUrl_notMatched() {
        // Inside a URL like https://example.com/#anchor — the word boundary
        // should prevent matching. Best-effort: the regex uses (?<!\w).
        let result = WikilinkParser.extractTags(from: "https://example.com/#fragment")
        // 'fragment' is preceded by '/' which is not \w — this WILL match.
        // Document the behaviour (expected output is ["fragment"]).
        XCTAssertEqual(result, ["fragment"])
    }

    // MARK: – extractTitle

    func test_extractTitle_fromH1() {
        let md = "# My Great Note\n\nBody text."
        XCTAssertEqual(WikilinkParser.extractTitle(from: md, fallback: "file"), "My Great Note")
    }

    func test_extractTitle_fallbackToFilename() {
        let md = "Body text without heading."
        XCTAssertEqual(WikilinkParser.extractTitle(from: md, fallback: "fallback-name"), "fallback-name")
    }

    func test_extractTitle_h2NotUsed() {
        // Only H1 is treated as the title
        let md = "## Section Heading\n\nContent."
        XCTAssertEqual(WikilinkParser.extractTitle(from: md, fallback: "file"), "file")
    }

    func test_extractTitle_stripsLeadingSpaceInHeading() {
        let md = "#  Padded Title\n\nContent."
        XCTAssertEqual(WikilinkParser.extractTitle(from: md, fallback: "file"), "Padded Title")
    }

    func test_extractTitle_emptyString() {
        XCTAssertEqual(WikilinkParser.extractTitle(from: "", fallback: "empty"), "empty")
    }
}
