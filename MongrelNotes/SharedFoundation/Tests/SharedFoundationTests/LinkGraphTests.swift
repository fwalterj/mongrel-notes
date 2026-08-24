import XCTest
@testable import SharedFoundation

final class LinkGraphTests: XCTestCase {

    // MARK: – Helpers

    private func makeNote(title: String, body: String = "") -> Note {
        Note(fileURL: URL(fileURLWithPath: "/tmp/\(title.replacingOccurrences(of: " ", with: "_")).md"),
             title: title,
             body: body)
    }

    // MARK: – Empty graph

    func test_emptyGraph_hasNoNodes() {
        let graph = LinkGraph(notes: [])
        XCTAssertTrue(graph.nodes.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    // MARK: – Nodes

    func test_singleNote_createsOneExistingNode() {
        let note = makeNote(title: "Alpha")
        let graph = LinkGraph(notes: [note])
        let nodes = graph.nodes
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.title, "Alpha")
        XCTAssertTrue(nodes.first?.exists == true)
    }

    // MARK: – Edges (existing links)

    func test_linkedNotes_createEdge() {
        let a = makeNote(title: "Alpha", body: "Links to [[Beta]].")
        let b = makeNote(title: "Beta")
        let graph = LinkGraph(notes: [a, b])
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges.first?.sourceID, a.id)
        XCTAssertEqual(graph.edges.first?.targetID, b.id)
    }

    func test_multipleLinksFromOneNote() {
        let a = makeNote(title: "Hub", body: "See [[Alpha]] and [[Beta]].")
        let b = makeNote(title: "Alpha")
        let c = makeNote(title: "Beta")
        let graph = LinkGraph(notes: [a, b, c])
        let outbound = graph.outboundEdges(from: a.id)
        XCTAssertEqual(outbound.count, 2)
        let targets = Set(outbound.map(\.targetID))
        XCTAssertTrue(targets.contains(b.id))
        XCTAssertTrue(targets.contains(c.id))
    }

    func test_multipleNotesLinkingToOne() {
        let hub  = makeNote(title: "Hub")
        let src1 = makeNote(title: "Source1", body: "See [[Hub]].")
        let src2 = makeNote(title: "Source2", body: "Also [[Hub]].")
        let graph = LinkGraph(notes: [hub, src1, src2])
        XCTAssertEqual(graph.backlinks(for: hub.id).count, 2)
    }

    // MARK: – Orphan nodes

    func test_unresolvedLink_createsOrphanNode() {
        let a = makeNote(title: "Alpha", body: "[[NonExistent]]")
        let graph = LinkGraph(notes: [a])
        // Should have 2 nodes: Alpha (exists) + NonExistent (orphan)
        XCTAssertEqual(graph.nodes.count, 2)
        let orphan = graph.nodes.first(where: { !$0.exists })
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.title, "NonExistent")
    }

    func test_orphanNodeHasEdge() {
        let a = makeNote(title: "Alpha", body: "[[Ghost]]")
        let graph = LinkGraph(notes: [a])
        XCTAssertEqual(graph.edges.count, 1)
        let target = graph.edges.first.flatMap { graph.node(for: $0.targetID) }
        XCTAssertEqual(target?.exists, false)
    }

    // MARK: – Backlinks

    func test_backlinks_returnCorrectSources() {
        let hub  = makeNote(title: "Hub")
        let a    = makeNote(title: "A", body: "[[Hub]]")
        let b    = makeNote(title: "B", body: "[[Hub]]")
        let graph = LinkGraph(notes: [hub, a, b])
        let bl = Set(graph.backlinks(for: hub.id))
        XCTAssertTrue(bl.contains(a.id))
        XCTAssertTrue(bl.contains(b.id))
    }

    func test_backlinks_emptyForIsolatedNote() {
        let a = makeNote(title: "A")
        let graph = LinkGraph(notes: [a])
        XCTAssertTrue(graph.backlinks(for: a.id).isEmpty)
    }

    // MARK: – Resolve

    func test_resolve_caseInsensitive() {
        let note = makeNote(title: "Meeting Notes")
        let graph = LinkGraph(notes: [note])
        XCTAssertEqual(graph.resolve(title: "meeting notes"), note.id)
        XCTAssertEqual(graph.resolve(title: "MEETING NOTES"), note.id)
        XCTAssertEqual(graph.resolve(title: "Meeting Notes"), note.id)
    }

    func test_resolve_nonExistent_returnsNil() {
        let graph = LinkGraph(notes: [makeNote(title: "Alpha")])
        XCTAssertNil(graph.resolve(title: "Zeta"))
    }

    // MARK: – Self-links

    func test_selfLink_isAllowed() {
        // A note linking to itself is valid but unusual.
        let a = makeNote(title: "Self", body: "[[Self]]")
        let graph = LinkGraph(notes: [a])
        let edges = graph.outboundEdges(from: a.id)
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges.first?.targetID, a.id)
    }
}
