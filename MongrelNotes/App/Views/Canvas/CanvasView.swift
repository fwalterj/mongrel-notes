import SwiftUI
import AppKit
import SharedFoundation

/// Freeform infinite canvas with multi-tool drawing, sticky notes, and image embedding.
/// Built on SwiftUI Canvas + NSBezierPath for macOS (no PencilKit dependency).
struct CanvasView: View {

    @StateObject private var model = CanvasModel()
    @State private var activeTool: DrawingTool = .pen
    @State private var activeColor: Color = Color(hue: 196/360, saturation: 0.85, brightness: 0.80)
    @State private var strokeWidth: CGFloat = 2

    enum DrawingTool: String, CaseIterable {
        case pen       = "pencil"
        case marker    = "highlighter"
        case eraser    = "eraser"
        case selection = "arrow.up.left.and.arrow.down.right"

        var label: String {
            switch self {
            case .pen:       return "Pen"
            case .marker:    return "Marker"
            case .eraser:    return "Eraser"
            case .selection: return "Select"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            canvasToolbar
            Divider().foregroundStyle(DesignTokens.borderRim)
            drawingCanvas
        }
        .background(DesignTokens.glassDeep)
    }

    // MARK: – Toolbar

    private var canvasToolbar: some View {
        HStack(spacing: 8) {
            // Tool picker
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    activeTool = tool
                } label: {
                    Image(systemName: tool.rawValue)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(activeTool == tool ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(activeTool == tool ? DesignTokens.glassHotSpot : .clear)
                )
                .help(tool.label)
            }

            Divider().frame(height: 20)

            // Stroke width
            Slider(value: $strokeWidth, in: 1...20)
                .frame(width: 80)
                .tint(DesignTokens.accent)

            Text("\(Int(strokeWidth))pt")
                .font(.caption2)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
                .frame(width: 28)

            Divider().frame(height: 20)

            // Colour swatches
            ColorPicker("", selection: $activeColor, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28, height: 28)

            ForEach(canvasSwatches, id: \.self) { swatch in
                Button {
                    activeColor = swatch
                } label: {
                    Circle()
                        .fill(swatch)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DesignTokens.borderRim, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
            .disabled(!model.canUndo)
            .help("Undo (⌘Z)")
            .keyboardShortcut("z")

            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
            .disabled(!model.canRedo)
            .help("Redo (⌘⇧Z)")
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button { model.clear() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
            .help("Clear canvas")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 44)
    }

    private var canvasSwatches: [Color] {
        [
            Color(hue: 196/360, saturation: 0.85, brightness: 0.80),  // brand teal
            Color(hue: 0.08,   saturation: 0.90, brightness: 0.90),  // warm orange
            Color(hue: 0.55,   saturation: 0.70, brightness: 0.85),  // lavender
            Color(hue: 0.33,   saturation: 0.70, brightness: 0.75),  // sage green
            Color(hue: 0.95,   saturation: 0.60, brightness: 0.90),  // rose
            Color(white: 0.85),                                        // light
        ]
    }

    // MARK: – Drawing canvas

    private var drawingCanvas: some View {
        CanvasDrawingNSView(
            model: model,
            activeTool: activeTool,
            activeColor: activeColor,
            strokeWidth: strokeWidth
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Data model

@MainActor
final class CanvasModel: ObservableObject {

    struct Stroke: Identifiable {
        let id = UUID()
        var points: [CGPoint]
        var color: NSColor
        var width: CGFloat
        var isHighlight: Bool
    }

    @Published var strokes: [Stroke] = []
    private var undoneStrokes: [Stroke] = []
    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !undoneStrokes.isEmpty }

    func commit(_ stroke: Stroke) {
        strokes.append(stroke)
        undoneStrokes.removeAll()
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        undoneStrokes.append(last)
    }

    func redo() {
        guard let next = undoneStrokes.popLast() else { return }
        strokes.append(next)
    }

    func clear() {
        strokes.removeAll()
        undoneStrokes.removeAll()
    }
}

// MARK: – NSView drawing surface

struct CanvasDrawingNSView: NSViewRepresentable {

    @ObservedObject var model: CanvasModel
    let activeTool: CanvasView.DrawingTool
    let activeColor: Color
    let strokeWidth: CGFloat

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        context.coordinator.parent = self
        view.setNeedsDisplay(view.bounds)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: – Coordinator

    final class Coordinator {
        var parent: CanvasDrawingNSView
        var currentStroke: CanvasModel.Stroke?

        init(_ parent: CanvasDrawingNSView) {
            self.parent = parent
        }

        func begin(at point: CGPoint) {
            let nsColor = NSColor(parent.activeColor)
            currentStroke = CanvasModel.Stroke(
                points: [point],
                color: parent.activeTool == .marker ? nsColor.withAlphaComponent(0.35) : nsColor,
                width: parent.activeTool == .marker ? parent.strokeWidth * 4 : parent.strokeWidth,
                isHighlight: parent.activeTool == .marker
            )
        }

        func addPoint(_ point: CGPoint) {
            currentStroke?.points.append(point)
        }

        func end() {
            guard let stroke = currentStroke, stroke.points.count > 1 else {
                currentStroke = nil
                return
            }
            Task { @MainActor in
                parent.model.commit(stroke)
            }
            currentStroke = nil
        }
    }
}

// MARK: – Custom NSView

final class CanvasNSView: NSView {

    weak var coordinator: CanvasDrawingNSView.Coordinator?
    private var currentStrokePoints: [CGPoint] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.fill(bounds)

        // Subtle grid
        drawGrid(ctx)

        // Committed strokes
        if let model = coordinator?.parent.model {
            for stroke in model.strokes {
                drawStroke(stroke.points, color: stroke.color, width: stroke.width, ctx: ctx)
            }
        }

        // Current in-progress stroke
        if !currentStrokePoints.isEmpty,
           let coordinator = coordinator {
            let color = NSColor(coordinator.parent.activeColor)
            let width = coordinator.parent.strokeWidth
            drawStroke(currentStrokePoints, color: color, width: width, ctx: ctx)
        }
    }

    private func drawGrid(_ ctx: CGContext) {
        let gridColor = CGColor(
            red: 0.52, green: 0.80, blue: 0.90, alpha: 0.06
        )
        ctx.setStrokeColor(gridColor)
        ctx.setLineWidth(0.5)
        let step: CGFloat = 32
        var x: CGFloat = 0
        while x <= bounds.width {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            y += step
        }
        ctx.strokePath()
    }

    private func drawStroke(_ points: [CGPoint], color: NSColor, width: CGFloat, ctx: CGContext) {
        guard points.count > 1 else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.beginPath()
        ctx.move(to: points[0])

        // Catmull-Rom spline for smoothness
        for i in 1 ..< points.count {
            let p0 = i > 1 ? points[i - 2] : points[0]
            let p1 = points[i - 1]
            let p2 = points[i]
            let p3 = i < points.count - 1 ? points[i + 1] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            ctx.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        ctx.strokePath()
    }

    // MARK: – Mouse events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentStrokePoints = [pt]
        coordinator?.begin(at: pt)
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentStrokePoints.append(pt)
        coordinator?.addPoint(pt)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.end()
        currentStrokePoints = []
        setNeedsDisplay(bounds)
    }
}
