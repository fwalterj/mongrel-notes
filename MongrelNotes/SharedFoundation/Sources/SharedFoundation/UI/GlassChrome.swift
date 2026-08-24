import SwiftUI

// MARK: – Glass background modifier

/// Applies the signature "energy encased in glass" background.
///
/// Layer stack (bottom → top):
///   1. `.ultraThinMaterial`   — system frosted-glass blur
///   2. Tinted colour overlay  — energy-hue wash
///   3. Radial hot-spot        — upper-left point-light specular
///   4. Top-edge specular      — crisp 1 pt bright line + 10 pt diffused catch
///   5. Bottom-edge cooldown   — faint darker gradient (chromatic bend)
///   6. Stroke border          — thin bright rim
///
/// The whole surface sits on top of a hue-matched ambient glow shadow, so
/// panels appear to emit a soft energy onto the surface below them.
public struct GlassChromeBackground: ViewModifier {

    public enum Style {
        /// Standard panel / sidebar surface.
        case base
        /// Toolbars and deeply-inset secondary panels.
        case deep
        /// Note list cards and selectable rows.
        case card
        /// Floating sheets, command palettes, popovers.  Appears slightly
        /// lifted and brighter than `base`.
        case elevated
    }

    public let style:        Style
    public let cornerRadius: CGFloat
    /// When `true` an accent-hued drop shadow is added beneath the panel.
    public let glowShadow:   Bool

    public init(style: Style = .base,
                cornerRadius: CGFloat = DesignTokens.cornerRadius,
                glowShadow: Bool = false) {
        self.style        = style
        self.cornerRadius = cornerRadius
        self.glowShadow   = glowShadow
    }

    public func body(content: Content) -> some View {
        content
            .background(glassStack)
            .overlay(borderOverlay)
            // Hue-matched ambient glow beneath the panel
            .shadow(color: glowShadow ? DesignTokens.panelGlow : .clear,
                    radius: 18, x: 0, y: 6)
            .shadow(color: glowShadow ? DesignTokens.panelGlow.opacity(0.4) : .clear,
                    radius: 40, x: 0, y: 14)
    }

    // MARK: – Glass stack

    private var glassStack: some View {
        ZStack {
            // 1. System material (blur) — only on elevated floating surfaces.
            //    Applying blur to every note card is the primary CPU hog at idle;
            //    solid dark fills look identical against our near-black canvas.
            if style == .elevated {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }

            // 2. Tinted colour wash (solid dark fill for non-elevated styles)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)

            // 3. Radial hot-spot — upper-left point light
            RadialGradient(
                colors: [DesignTokens.glassHotSpot, .clear],
                center: .init(x: 0.28, y: 0.02),
                startRadius: 0,
                endRadius: style == .card ? 120 : 200
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // 4a. Top-edge specular — crisp 1 pt capture line
            VStack(spacing: 0) {
                DesignTokens.specularCapture
                    .frame(height: 1)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // 4b. Top-edge diffused catch — broader glow bleeding downward
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [DesignTokens.glassEdgeCatch, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // 5. Bottom-edge chromatic cooldown (light bends around the bottom)
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear,
                             Color(hue: DesignTokens.energyHue,
                                   saturation: 0.60,
                                   brightness: 0.05,
                                   opacity: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    // MARK: – Border overlay

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: DesignTokens.borderWidth)
    }

    // MARK: – Per-style values

    private var fillColor: Color {
        switch style {
        case .base:     return DesignTokens.glassBase
        case .deep:     return DesignTokens.glassDeep
        case .card:     return DesignTokens.glassCard
        case .elevated: return DesignTokens.glassElevated
        }
    }

    private var borderColor: Color {
        switch style {
        case .elevated: return DesignTokens.glassBorder
        default:        return DesignTokens.borderRim
        }
    }
}

// MARK: – View extension

public extension View {
    func glassChromeBackground(
        style: GlassChromeBackground.Style = .base,
        cornerRadius: CGFloat = DesignTokens.cornerRadius,
        glowShadow: Bool = false
    ) -> some View {
        modifier(GlassChromeBackground(style: style,
                                       cornerRadius: cornerRadius,
                                       glowShadow: glowShadow))
    }
}

// MARK: – Hover bloom modifier

/// Paints the hover-bloom background on pointer-enter and lifts the view
/// with a tiny spring scale to give buttons and rows a physical feel.
public struct HoverBloomModifier: ViewModifier {
    @State private var isHovered = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? DesignTokens.hoverBloom : .clear)
            )
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

public extension View {
    func hoverBloom() -> some View {
        modifier(HoverBloomModifier())
    }
}

// MARK: – Selected row background

/// Selection style for list rows.  A selected row gains:
///   • Glass-deep background fill
///   • Left-edge accent stripe (1.5 pt)
///   • Hot-spot radial glow
///   • Hue-matched drop shadow (lift effect)
///   • Bright border rim
public struct SelectedRowBackground: ViewModifier {
    public let isSelected: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if isSelected {
                        ZStack(alignment: .leading) {
                            // Glass fill
                            RoundedRectangle(cornerRadius: DesignTokens.cardRadius,
                                             style: .continuous)
                                .fill(DesignTokens.glassDeep)

                            // Hot-spot
                            RadialGradient(
                                colors: [DesignTokens.glassHotSpot, .clear],
                                center: .init(x: 0.28, y: 0),
                                startRadius: 0,
                                endRadius: 110
                            )
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius,
                                                        style: .continuous))

                            // Left accent stripe
                            HStack(spacing: 0) {
                                DesignTokens.accent
                                    .frame(width: 2)
                                    .clipShape(
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: DesignTokens.cardRadius,
                                            bottomLeadingRadius: DesignTokens.cardRadius,
                                            bottomTrailingRadius: 0,
                                            topTrailingRadius: 0,
                                            style: .continuous
                                        )
                                    )
                                Spacer()
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.cardRadius,
                                             style: .continuous)
                                .strokeBorder(
                                    DesignTokens.glassBorder,
                                    lineWidth: DesignTokens.borderWidth
                                )
                        )
                        // Lifted shadow — accent-hued glow
                        .shadow(color: DesignTokens.activeCardGlow,
                                radius: 10, x: 0, y: 3)
                        .shadow(color: DesignTokens.panelGlow.opacity(0.5),
                                radius: 24, x: 0, y: 8)
                    }
                }
            )
            .scaleEffect(isSelected ? 1.003 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.72), value: isSelected)
    }
}

public extension View {
    func selectedRowBackground(isSelected: Bool) -> some View {
        modifier(SelectedRowBackground(isSelected: isSelected))
    }
}

// MARK: – Glass card modifier

/// A self-contained glass card that combines background, border, and shadow.
/// Intended for `NoteRowView` and similar floating content blocks.
public struct GlassCardModifier: ViewModifier {
    @State private var isHovered = false
    public let isSelected: Bool

    public func body(content: Content) -> some View {
        content
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? DesignTokens.glassBorder : DesignTokens.borderRim,
                                  lineWidth: DesignTokens.borderWidth)
            )
            .shadow(color: isSelected
                    ? DesignTokens.activeCardGlow
                    : (isHovered ? DesignTokens.panelGlow.opacity(0.5) : .clear),
                    radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 4 : 2)
            .scaleEffect(isHovered && !isSelected ? 1.008 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
            .onHover { isHovered = $0 }
    }

    private var cardBackground: some View {
        ZStack {
            // Solid fill only — no material blur per card (CPU cost is prohibitive)
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(isSelected ? DesignTokens.glassDeep : DesignTokens.glassCard)
            // Top-edge specular
            VStack(spacing: 0) {
                DesignTokens.specularCapture.opacity(isSelected ? 0.7 : 0.45)
                    .frame(height: 1)
                LinearGradient(
                    colors: [DesignTokens.glassEdgeCatch.opacity(isSelected ? 0.55 : 0.30),
                             .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 9)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius,
                                        style: .continuous))
        }
    }
}

public extension View {
    func glassCard(isSelected: Bool = false) -> some View {
        modifier(GlassCardModifier(isSelected: isSelected))
    }
}
