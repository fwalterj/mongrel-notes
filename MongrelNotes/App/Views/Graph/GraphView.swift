import SwiftUI
import SharedFoundation

/// Interactive force-directed graph of note links.
/// Rendered with SwiftUI Canvas (no Metal dependency for < 500 nodes).
struct GraphView: View {

    let store: VaultStore
    let focusedNoteID: UUID?

    @StateObject private var viewModel: GraphViewModel
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnification: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var draggingNodeID: UUID?
    @State private var nodeInDrag: UUID?

    // Settings
    @AppStorage(Prefs.graphNodeRadius)  private var prefNodeRadius:  Double = 6
    @AppStorage(Prefs.graphLinkOpacity) private var prefLinkOpacity: Double = 0.4

    init(store: VaultStore, focusedNoteID: UUID? = nil) {
        self.store = store
        self.focusedNoteID = focusedNoteID
        _viewModel = StateObject(wrappedValue: GraphViewModel(store: store, focusedNoteID: focusedNoteID))
    }

    var body: some View {
        // GeometryReader captures the canvas size without mutating state
        // inside a drawing closure (which would cause an infinite render loop).
        GeometryReader { geo in
            let size = geo.size
            ZStack {
            // Canvas layer
            Canvas { ctx, _ in
                let transform = CGAffineTransform(translationX: size.width / 2 + offset.width + dragOffset.width,
                                                  y: size.height / 2 + offset.height + dragOffset.height)
                    .scaledBy(x: scale * magnification, y: scale * magnification)

                ctx.concatenate(transform)
                drawEdges(ctx)
                drawNodes(ctx)
            }
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .updating($magnification) { val, state, _ in state = val }
                        .onEnded { val in scale = min(max(scale * val, 0.15), 8) },
                    DragGesture()
                        .updating($dragOffset) { val, state, _ in
                            guard draggingNodeID == nil else { return }
                            state = val.translation
                        }
                        .onEnded { val in
                            guard draggingNodeID == nil else { return }
                            offset.width += val.translation.width
                            offset.height += val.translation.height
                        }
                )
            )
            .background(DesignTokens.glassDeep)
            .onAppear { viewModel.startSimulation() }
            .onDisappear { viewModel.stopSimulation() }

            // Node labels overlay (avoids canvas text anti-aliasing limitations)
            ForEach(Array(viewModel.layoutNodes.values)) { node in
                nodeOverlay(node)
            }
            .scaleEffect(scale * magnification)
            .offset(x: offset.width + dragOffset.width,
                    y: offset.height + dragOffset.height)
            } // end ZStack
        } // end GeometryReader
        .toolbar { graphToolbar }
    }

    // MARK: – Canvas drawing

    private func drawEdges(_ ctx: GraphicsContext) {
        for edge in viewModel.layoutEdges {
            guard let src = viewModel.layoutNodes[edge.sourceID],
                  let dst = viewModel.layoutNodes[edge.targetID] else { continue }
            var path = Path()
            path.move(to: src.position)
            path.addLine(to: dst.position)
            let isActive = viewModel.hoveredNodeID == edge.sourceID ||
                           viewModel.hoveredNodeID == edge.targetID
            let alpha: CGFloat = isActive ? min(prefLinkOpacity * 1.8, 1.0) : CGFloat(prefLinkOpacity)
            ctx.stroke(
                path,
                with: .color(Color(hue: DesignTokens.energyHue, saturation: 0.70, brightness: 0.75, opacity: alpha)),
                lineWidth: 1
            )
        }
    }

    private func drawNodes(_ ctx: GraphicsContext) {
        for node in viewModel.layoutNodes.values {
            let baseR = CGFloat(prefNodeRadius)
            let radius: CGFloat = node.isFocused ? baseR * 1.6 : (node.exists ? baseR : baseR * 0.65)
            let rect = CGRect(
                x: node.position.x - radius,
                y: node.position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let isHovered = viewModel.hoveredNodeID == node.id

            // Fill
            ctx.fill(
                Path(ellipseIn: rect),
                with: .color(nodeColor(node: node, hovered: isHovered))
            )

            // Halo for hovered / focused nodes
            if isHovered || node.isFocused {
                ctx.fill(
                    Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                    with: .color(nodeColor(node: node, hovered: true).opacity(0.25))
                )
            }
        }
    }

    private func nodeColor(node: GraphViewModel.LayoutNode, hovered: Bool) -> Color {
        if node.isFocused {
            return Color(hue: DesignTokens.energyHue, saturation: 0.95, brightness: 0.95)
        }
        if !node.exists {
            return Color(hue: DesignTokens.energyHue, saturation: 0.30, brightness: 0.50)
        }
        return hovered
            ? Color(hue: DesignTokens.energyHue, saturation: 0.90, brightness: 0.90)
            : Color(hue: DesignTokens.energyHue, saturation: 0.70, brightness: 0.72)
    }

    // MARK: – Node label overlays

    @ViewBuilder
    private func nodeOverlay(_ node: GraphViewModel.LayoutNode) -> some View {
        let isHovered = viewModel.hoveredNodeID == node.id
        let shouldShowLabel = isHovered || node.isFocused ||
            viewModel.layoutNodes.count < 60

        if shouldShowLabel {
            Text(node.title)
                .font(.system(size: 10 / (scale * magnification), weight: node.isFocused ? .semibold : .regular))
                .foregroundStyle(DesignTokens.chromeText.opacity(isHovered ? 1 : 0.7))
                .fixedSize()
                .offset(
                    x: node.position.x,
                    y: node.position.y + 14 / (scale * magnification)
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var graphToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                withAnimation(.spring()) {
                    scale = 1.0
                    offset = .zero
                }
                viewModel.startSimulation()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset layout")
        }
        ToolbarItem {
            Text("\(viewModel.layoutNodes.count) notes · \(viewModel.layoutEdges.count) links")
                .font(.caption2)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
        }
    }
}
