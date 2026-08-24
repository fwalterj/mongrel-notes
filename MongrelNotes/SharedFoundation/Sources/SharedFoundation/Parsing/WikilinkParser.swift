import Foundation

/// Parses Obsidian-style `[[wikilinks]]` and `#tags` from Markdown text.
public enum WikilinkParser {

    // MARK: – Patterns (compiled once at load time)

    private static let wikilinkRegex: NSRegularExpression = {
        // Matches [[Link Title]] and [[Link Title|Display Text]]
        try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#, options: [])
    }()

    private static let tagRegex: NSRegularExpression = {
        // Matches #tag-name (not inside code blocks – best-effort)
        try! NSRegularExpression(pattern: #"(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)"#, options: [])
    }()

    // MARK: – Public API

    /// Returns all wikilink titles found in `text` (in order of appearance).
    public static func extractLinks(from text: String) -> [String] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return wikilinkRegex.matches(in: text, options: [], range: range).map {
            nsText.substring(with: $0.range(at: 1))
        }
    }

    /// Returns all `#tag` values found in `text`.
    public static func extractTags(from text: String) -> [String] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return tagRegex.matches(in: text, options: [], range: range).map {
            nsText.substring(with: $0.range(at: 1))
        }
    }

    /// Replaces `[[Title]]` tokens in `text` with resolved hrefs.
    /// `resolver` maps a title to a URL string (or nil for unresolved).
    public static func renderLinks(
        in text: String,
        resolver: (String) -> String?
    ) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text
        var offset = 0

        for match in wikilinkRegex.matches(in: text, options: [], range: range).reversed() {
            let fullRange = Range(match.range, in: text)!
            let titleRange = Range(match.range(at: 1), in: text)!
            let title = String(text[titleRange])
            let replacement: String
            if let href = resolver(title) {
                replacement = "[\(title)](\(href))"
            } else {
                replacement = "**\(title)**"   // orphan — bold, no link
            }
            result.replaceSubrange(fullRange, with: replacement)
        }
        _ = offset  // silence unused-variable warning
        return result
    }

    // MARK: – Title extraction helper

    /// Derives a note title from the first H1 in `markdown`, or falls back to `filename`.
    public static func extractTitle(from markdown: String, fallback filename: String) -> String {
        let lines = markdown.split(separator: "\n", maxSplits: 10, omittingEmptySubsequences: true)
        for line in lines {
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return filename
    }
}
