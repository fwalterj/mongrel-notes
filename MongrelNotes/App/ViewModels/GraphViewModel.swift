import SwiftUI
import Combine
import SharedFoundation

/// Force-directed graph layout simulation for the graph view.
@MainActor
final class GraphViewModel: ObservableObject {

    // MARK: – Types

    struct LayoutNode: Identifiable {
        let id: UUID
        let title: String
        let exists: Bool
        var position: CGPoint
        var velocity: CGPoint = .zero
        var isFocused: Bool = false
    }

    struct LayoutEdge: Identifiable {
        let id: UUID
        let sourceID: UUID
        let targetID: UUID
    }

    // MARK: – Published

    @Published var layoutNodes: [UUID: LayoutNode] = [:]
    @Published var layoutEdges: [LayoutEdge] = []
    @Published var hoveredNodeID: UUID?

    // MARK: – Constants (force-directed params)

    private let repulsion: CGFloat   = 2800
    private let attraction: CGFloat  = 0.04
    private let damping: CGFloat     = 0.88
    private let minVelocity: CGFloat = 0.2
    private let timeStep: CGFloat    = 0.016  // ~60 fps

    // MARK: – Dependencies

    private let store: VaultStore
    private var storeSubscription: AnyCancellable?
    private var simulationTimer: AnyCancellable?
    var focusedNoteID: UUID?

    // MARK: – Init

    init(store: VaultStore, focusedNoteID: UUID? = nil) {
        self.store = store
        self.focusedNoteID = focusedNoteID

        storeSubscription = store.$linkGraph
            .receive(on: RunLoop.main)
            .sink { [weak self] graph in
                self?.buildLayout(from: graph)
            }

        buildLayout(from: store.linkGraph)
    }

    // MARK: – Simulation control

    func startSimulation() {
        guard simulationTimer == nil else { return }
        simulationTimer = Timer.publish(every: timeStep, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stopSimulation() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    // MARK: – Drag

    func drag(nodeID: UUID, to point: CGPoint) {
        layoutNodes[nodeID]?.position = point
        layoutNodes[nodeID]?.velocity = .zero
    }

    // MARK: – Private

    private func buildLayout(from graph: LinkGraph) {
        var newNodes: [UUID: LayoutNode] = [:]
        let canvasCenter = CGPoint(x: 400, y: 300)

        for node in graph.nodes {
            if let existing = layoutNodes[node.id] {
                // Keep existing position so the layout doesn't jump.
                newNodes[node.id] = LayoutNode(
                    id: node.id,
                    title: node.title,
                    exists: node.exists,
                    position: existing.position,
                    velocity: existing.velocity,
                    isFocused: node.id == focusedNoteID
                )
            } else {
                // Place new nodes in a circle around the centre.
                let angle = CGFloat.random(in: 0 ..< .pi * 2)
                let radius = CGFloat.random(in: 60 ..< 200)
                let pos = CGPoint(
                    x: canvasCenter.x + cos(angle) * radius,
                    y: canvasCenter.y + sin(angle) * radius
                )
                newNodes[node.id] = LayoutNode(
                    id: node.id, title: node.title, exists: node.exists,
                    position: pos,
                    isFocused: node.id == focusedNoteID
                )
            }
        }

        layoutNodes = newNodes
        layoutEdges = graph.edges.map {
            LayoutEdge(id: $0.id, sourceID: $0.sourceID, targetID: $0.targetID)
        }
    }

    private func tick() {
        var nodes = layoutNodes

        // Repulsion between all node pairs (O(n²) – fine for <500 nodes).
        let ids = Array(nodes.keys)
        for i in 0 ..< ids.count {
            for j in (i + 1) ..< ids.count {
                guard let a = nodes[ids[i]], let b = nodes[ids[j]] else { continue }
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = repulsion / (dist * dist)
                let fx = force * dx / dist
                let fy = force * dy / dist
                nodes[ids[i]]?.velocity.x += fx
                nodes[ids[i]]?.velocity.y += fy
                nodes[ids[j]]?.velocity.x -= fx
                nodes[ids[j]]?.velocity.y -= fy
            }
        }

        // Spring attraction along edges.
        for edge in layoutEdges {
            guard var a = nodes[edge.sourceID], var b = nodes[edge.targetID] else { continue }
            let dx = b.position.x - a.position.x
            let dy = b.position.y - a.position.y
            let fx = dx * attraction
            let fy = dy * attraction
            nodes[edge.sourceID]?.velocity.x += fx
            nodes[edge.sourceID]?.velocity.y += fy
            nodes[edge.targetID]?.velocity.x -= fx
            nodes[edge.targetID]?.velocity.y -= fy
        }

        // Integrate + dampen.
        for id in ids {
            guard var node = nodes[id] else { continue }
            node.velocity.x *= damping
            node.velocity.y *= damping
            node.position.x += node.velocity.x * timeStep * 60
            node.position.y += node.velocity.y * timeStep * 60
            nodes[id] = node
        }

        // Stop when kinetic energy is negligible.
        let energy = nodes.values.reduce(0.0) {
            $0 + $1.velocity.x * $1.velocity.x + $1.velocity.y * $1.velocity.y
        }
        if energy < Double(minVelocity) * Double(minVelocity) * Double(nodes.count) {
            stopSimulation()
        }

        layoutNodes = nodes
    }
}
