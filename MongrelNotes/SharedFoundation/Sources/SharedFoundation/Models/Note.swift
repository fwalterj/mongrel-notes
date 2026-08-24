import Foundation

/// A single note stored as a plain Markdown file on disk.
/// The file name (minus extension) is the canonical identifier;
/// `id` is a stable UUID encoded in the file's extended attributes
/// so renaming the file doesn't break backlinks.
public struct Note: Identifiable, Equatable, Hashable, Sendable {

    // MARK: – Identity

    public let id: UUID
    /// Absolute URL of the .md file in the vault.
    public var fileURL: URL

    // MARK: – Content

    /// The first H1 heading, or the filename stem if none exists.
    public var title: String
    /// Raw Markdown source.
    public var body: String

    // MARK: – Metadata

    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    /// Tags extracted from `#tag` patterns in the body.
    public var tags: [String]

    // MARK: – Derived

    /// Titles referenced with `[[wikilink]]` syntax.
    public var outboundLinks: [String] {
        WikilinkParser.extractLinks(from: body)
    }

    /// Whether this note's body is stored in encrypted form on disk.
    /// Encrypted notes have a special sentinel header written by `NoteEncryptionService`.
    public var isEncrypted: Bool {
        body.hasPrefix(NoteEncryptionService.encryptedHeader)
    }

    // MARK: – Init

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        title: String,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.tags = tags
    }
}

public extension Note {
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id &&
        lhs.fileURL == rhs.fileURL &&
        lhs.title == rhs.title &&
        lhs.body == rhs.body &&
        lhs.isPinned == rhs.isPinned &&
        lhs.tags == rhs.tags
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(fileURL)
        hasher.combine(title)
        hasher.combine(body)
        hasher.combine(isPinned)
        hasher.combine(tags)
    }
}

// MARK: – Convenience

public extension Note {
    /// The word count of the body, fast-computed without full tokenisation.
    var wordCount: Int {
        body.split { $0.isWhitespace }.count
    }

    /// Character count excluding whitespace.
    var characterCount: Int {
        body.filter { !$0.isWhitespace }.count
    }

    /// Returns a plain-text excerpt suitable for note list previews.
    var excerpt: String {
        let stripped = body
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*{1,2}([^*]+)\*{1,2}"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(160))
    }
}
