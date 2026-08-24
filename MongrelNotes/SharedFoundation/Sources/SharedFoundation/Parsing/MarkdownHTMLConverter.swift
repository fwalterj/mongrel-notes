import Foundation
import Markdown

// MARK: – Public API

/// Converts a Markdown string to an HTML fragment (no `<html>`/`<body>` wrapper)
/// using the `swift-markdown` parser for standards-compliant CommonMark rendering.
///
/// MongrelNotes extensions beyond CommonMark:
///   - `[[wikilink]]` and `[[wikilink|alias]]` → `<span class="wikilink">`
///   - `#tag` → `<span class="tag">`
public enum MarkdownHTMLConverter {

    /// Convert Markdown to an HTML body fragment.
    public static func html(from markdown: String) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor()
        let raw = visitor.visit(document)
        // Post-process: wikilinks and tags live in raw text nodes
        return raw
    }
}

// MARK: – Visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    // Concatenate children by default.
    mutating func defaultVisit(_ markup: any Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: Block elements

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined(separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let n = max(1, min(6, heading.level))
        let inner = heading.children.map { visit($0) }.joined()
        return "<h\(n)>\(inner)</h\(n)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let inner = paragraph.children.map { visit($0) }.joined()
        return "<p>\(inner)</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let inner = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\n\(inner)</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language.map { " class=\"language-\($0)\"" } ?? ""
        let code = escapeHTML(codeBlock.code)
        return "<pre><code\(lang)>\(code)</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    // MARK: – Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let inner = unorderedList.children.map { visit($0) }.joined()
        return "<ul>\n\(inner)</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        let inner = orderedList.children.map { visit($0) }.joined()
        return "<ol\(start)>\n\(inner)</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        // Render checkbox if the list item has a checkbox state.
        var checkboxHTML = ""
        if let cb = listItem.checkbox {
            let checked = cb == .checked ? " checked" : ""
            checkboxHTML = "<input type=\"checkbox\" disabled\(checked)> "
        }
        let inner = listItem.children.map { visit($0) }.joined()
        return "<li>\(checkboxHTML)\(inner)</li>\n"
    }

    // MARK: – Tables

    mutating func visitTable(_ table: Table) -> String {
        let inner = table.children.map { visit($0) }.joined()
        return "<table>\n\(inner)</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        var cellsHTML = ""
        for cell in tableHead.cells {
            let inner = cell.children.map { visit($0) }.joined()
            cellsHTML += "<th>\(inner)</th>"
        }
        return "<thead><tr>\(cellsHTML)</tr></thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        let inner = tableBody.children.map { visit($0) }.joined()
        return "<tbody>\n\(inner)</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        var cellsHTML = ""
        for cell in tableRow.cells {
            let inner = cell.children.map { visit($0) }.joined()
            cellsHTML += "<td>\(inner)</td>"
        }
        return "<tr>\(cellsHTML)</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        let inner = tableCell.children.map { visit($0) }.joined()
        return "<td>\(inner)</td>"
    }

    // MARK: – Inline elements

    mutating func visitText(_ text: Text) -> String {
        // Apply wikilink and tag substitution to raw text content.
        var s = escapeHTML(text.string)
        s = applyWikilinks(to: s)
        s = applyTags(to: s)
        return s
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let inner = strong.children.map { visit($0) }.joined()
        return "<strong>\(inner)</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let inner = emphasis.children.map { visit($0) }.joined()
        return "<em>\(inner)</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = link.destination ?? "#"
        let inner = link.children.map { visit($0) }.joined()
        return "<a href=\"\(escapeAttr(href))\">\(inner)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = image.source ?? ""
        let alt = image.title ?? ""
        return "<img src=\"\(escapeAttr(src))\" alt=\"\(escapeAttr(alt))\">"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>" }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    // MARK: – Helpers

    private func escapeHTML(_ s: String) -> String {
        s   .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeAttr(_ s: String) -> String {
        s   .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Replace `[[wikilink]]` and `[[wikilink|alias]]` with styled spans.
    /// Uses two passes: aliased links first, then plain links.
    private func applyWikilinks(to s: String) -> String {
        // Pass 1: [[target|alias]] → display alias
        let step1 = s.replacingOccurrences(
            of: #"\[\[([^\]|]+?)\|([^\]]+?)\]\]"#,
            with: "<span class=\"wikilink\">$2</span>",
            options: .regularExpression
        )
        // Pass 2: [[target]] → display target
        return step1.replacingOccurrences(
            of: #"\[\[([^\]]+?)\]\]"#,
            with: "<span class=\"wikilink\">$1</span>",
            options: .regularExpression
        )
    }

    /// Replace `#tag` with styled spans. Only matches tags at word boundaries.
    private func applyTags(to s: String) -> String {
        s.replacingOccurrences(
            of: #"(?<![&\w])#([A-Za-z][A-Za-z0-9_/-]*)"#,
            with: "<span class=\"tag\">#$1</span>",
            options: .regularExpression
        )
    }
}
