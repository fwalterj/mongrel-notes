import Foundation

/// An in-memory directed graph of note links, rebuilt whenever the vault changes.
public final class LinkGraph: Sendable {

    // MARK: – Types

    public struct Node: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        /// Exists = the file is present; orphan nodes represent unresolved links.
        public let exists: Bool
    }

    public struct Edge: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceID: UUID
        public let targetID: UUID
    }

    // MARK: – Storage

    private let _nodes: [UUID: Node]
    private let _edges: [Edge]
    /// Maps note title (lowercased) → UUID for fast link resolution.
    private let _titleIndex: [String: UUID]

    // MARK: – Init

    public init(notes: [Note]) {
        var nodes: [UUID: Node] = [:]
        var titleIndex: [String: UUID] = [:]

        for note in notes {
            let node = Node(id: note.id, title: note.title, exists: true)
            nodes[note.id] = node
            titleIndex[note.title.lowercased()] = note.id
        }

        var edges: [Edge] = []

        for note in notes {
            for linkTitle in note.outboundLinks {
                let key = linkTitle.lowercased()
                if let targetID = titleIndex[key] {
                    edges.append(Edge(id: UUID(), sourceID: note.id, targetID: targetID))
                } else {
                    // Orphan node – referenced but doesn't exist yet.
                    let orphanID = UUID()
                    let orphan = Node(id: orphanID, title: linkTitle, exists: false)
                    nodes[orphanID] = orphan
                    titleIndex[key] = orphanID
                    edges.append(Edge(id: UUID(), sourceID: note.id, targetID: orphanID))
                }
            }
        }

        _nodes = nodes
        _edges = edges
        _titleIndex = titleIndex
    }

    // MARK: – Queries

    public var nodes: [Node] { Array(_nodes.values) }
    public var edges: [Edge] { _edges }

    public func node(for id: UUID) -> Node? { _nodes[id] }

    public func outboundEdges(from id: UUID) -> [Edge] {
        _edges.filter { $0.sourceID == id }
    }

    public func inboundEdges(to id: UUID) -> [Edge] {
        _edges.filter { $0.targetID == id }
    }

    /// Returns the UUIDs of all notes that link TO the given note.
    public func backlinks(for noteID: UUID) -> [UUID] {
        inboundEdges(to: noteID).map(\.sourceID)
    }

    /// Resolve a wikilink title to a note UUID.
    public func resolve(title: String) -> UUID? {
        _titleIndex[title.lowercased()]
    }
}
