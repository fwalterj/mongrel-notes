import SwiftUI

/// Design language tokens for the MongrelNotes glass design system.
///
/// The palette is anchored to the Mongrel suite's signature deep-navy hue (222°).
/// This is the same atmospheric indigo-blue visible in the Mongrel browser's
/// new-tab page — the colour of deep ocean water lit from within, not from above.
///
/// Surfaces are slabs of coloured glass suspended in that dark space.  Light
/// catches the top edge, scatters into a diffused glow, and dies at the base
/// in a cool chromatic bleed.  All other apps in the Mongrel suite share this
/// vocabulary.
public enum DesignTokens {

    // MARK: – Energy hue

    /// Primary brand hue: 222° — deep indigo-navy.
    /// This is the defining colour of the Mongrel suite, matching the atmospheric
    /// midnight-blue of the Mongrel browser's canvas.
    public static let energyHue: Double = 222 / 360

    // MARK: – Glass palette
    //
    // Dark-mode values are FULLY OPAQUE (alpha 1.0) so they completely
    // cover macOS NavigationSplitView's system sidebar material.
    // Brightness is kept very low (0.05 – 0.18) to achieve the deep-black
    // canvas the Mongrel suite requires.

    /// Standard panels and sidebars.
    /// Dark: rich near-black with a whisper of the brand blue — ≈ #0a0c14
    public static var glassBase: Color {
        Color(light: .init(hue: energyHue, saturation: 0.50, brightness: 0.86, alpha: 1.0),
              dark:  .init(hue: energyHue, saturation: 0.38, brightness: 0.09, alpha: 1.0))
    }

    /// Window canvas / toolbar floor — the darkest surface in the hierarchy.
    /// Dark: ≈ #060810 — the void the glass sits in.
    public static var glassDeep: Color {
        Color(light: .init(hue: energyHue, saturation: 0.45, brightness: 0.68, alpha: 1.0),
              dark:  .init(hue: energyHue, saturation: 0.42, brightness: 0.05, alpha: 1.0))
    }

    /// Floating sheets, command palettes, popovers — notably lighter than base
    /// to communicate elevation.  Dark: ≈ #121726
    public static var glassElevated: Color {
        Color(light: .init(hue: energyHue, saturation: 0.40, brightness: 0.82, alpha: 1.0),
              dark:  .init(hue: energyHue, saturation: 0.48, brightness: 0.17, alpha: 0.97))
    }

    /// Note-list card surface — one step above the sidebar floor.
    /// Dark: ≈ #0d1020
    public static var glassCard: Color {
        Color(light: .init(hue: energyHue, saturation: 0.40, brightness: 0.94, alpha: 1.0),
              dark:  .init(hue: energyHue, saturation: 0.44, brightness: 0.13, alpha: 1.0))
    }

    // MARK: – Specular / light-catch

    /// Top-edge specular capture line (~1 pt) — the brightest point where the
    /// overhead light source strikes the glass slab.
    public static var specularCapture: Color {
        Color(light: .init(hue: energyHue, saturation: 0.25, brightness: 1.00, alpha: 0.70),
              dark:  .init(hue: energyHue, saturation: 0.45, brightness: 1.00, alpha: 0.50))
    }

    /// Broader edge-catch glow (~8–12 pt) — diffused light bleeding down from
    /// the specular line.
    public static var glassEdgeCatch: Color {
        Color(light: .init(hue: energyHue, saturation: 0.55, brightness: 0.99, alpha: 0.40),
              dark:  .init(hue: energyHue, saturation: 0.65, brightness: 0.90, alpha: 0.26))
    }

    /// Off-centre radial hot-spot (upper-left) — simulates a point-light source
    /// raking across the glass surface.
    public static var glassHotSpot: Color {
        Color(hue: energyHue, saturation: 0.90, brightness: 0.78, opacity: 0.14)
    }

    /// Subtle inner glow on hover / focus.
    public static var glassInnerGlow: Color {
        Color(hue: energyHue, saturation: 0.88, brightness: 0.68, opacity: 0.10)
    }

    // MARK: – Borders

    /// Standard 0.5 pt border rim, hue-matched.
    public static var borderRim: Color {
        Color(light: .init(hue: energyHue, saturation: 0.40, brightness: 0.55, alpha: 0.38),
              dark:  .init(hue: energyHue, saturation: 0.90, brightness: 0.90, alpha: 0.20))
    }

    /// Stronger border for elevated / selected surfaces.
    public static var glassBorder: Color {
        Color(light: .init(hue: energyHue, saturation: 0.55, brightness: 0.65, alpha: 0.52),
              dark:  .init(hue: energyHue, saturation: 0.95, brightness: 0.95, alpha: 0.32))
    }

    // MARK: – Ambient glow (depth / lift)

    /// Drop shadow for floating panels — the hue-matched "energy leak" beneath
    /// the glass, as if the panel is self-illuminated.
    public static var panelGlow: Color {
        Color(hue: energyHue, saturation: 0.88, brightness: 0.58, opacity: 0.28)
    }

    /// Stronger glow for selected / active cards.
    public static var activeCardGlow: Color {
        Color(hue: energyHue, saturation: 0.85, brightness: 0.70, opacity: 0.40)
    }

    // MARK: – Hover / interaction

    /// Background on hover (button / list row bloom).
    public static var hoverBloom: Color {
        Color(light: .init(hue: energyHue, saturation: 0.55, brightness: 0.78, alpha: 0.26),
              dark:  .init(hue: energyHue, saturation: 0.80, brightness: 0.68, alpha: 0.16))
    }

    // MARK: – Text

    /// UI chrome text — off-white with the faintest blue tint.
    /// Note body text uses a separate, purer white (see `EditorMood.glass`).
    public static var chromeText: Color {
        Color(light: .init(hue: energyHue, saturation: 0.35, brightness: 0.10, alpha: 1),
              dark:  .init(hue: energyHue, saturation: 0.10, brightness: 0.88, alpha: 1))
    }

    /// Accent for interactive elements — a bright, saturated version of the
    /// brand blue, analogous to the Mongrel browser's active-state blue.
    public static var accent: Color {
        Color(hue: energyHue, saturation: 0.85, brightness: 0.88)
    }

    /// Accent at reduced intensity — secondary interactive labels.
    public static var accentDim: Color {
        Color(hue: energyHue, saturation: 0.70, brightness: 0.68, opacity: 0.80)
    }

    // MARK: – Typography

    public static let editorFont: Font = .system(.body, design: .monospaced)
    public static let uiFont: Font     = .system(.body, design: .rounded)

    // MARK: – Geometry

    public static let sidebarWidth:  CGFloat = 220
    public static let listWidth:     CGFloat = 280
    public static let cornerRadius:  CGFloat = 10
    public static let cardRadius:    CGFloat = 8
    public static let borderWidth:   CGFloat = 0.5
}

// MARK: – Adaptive Color helper

extension Color {
    /// Creates a colour that uses `light` in light mode and `dark` in dark mode.
    init(light: NSColor, dark: NSColor) {
        self = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }
}
