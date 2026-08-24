import Foundation

/// Represents an Obsidian-style vault: a directory of Markdown files.
public struct Vault: Identifiable, Equatable, Codable, Sendable {

    public let id: UUID
    /// User-visible name (defaults to the directory name).
    public var name: String
    /// Absolute URL of the root directory.
    public var rootURL: URL
    /// Whether the vault is stored inside iCloud Drive.
    public var isCloudBacked: Bool
    /// Date the vault was first opened in MongrelNotes.
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rootURL: URL,
        isCloudBacked: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.isCloudBacked = isCloudBacked
        self.addedAt = addedAt
    }
}

// MARK: – Folder model

/// A logical grouping of notes within a vault (maps to a subdirectory).
public struct NoteFolder: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var directoryURL: URL
    public var parentID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        directoryURL: URL,
        parentID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.parentID = parentID
    }
}
