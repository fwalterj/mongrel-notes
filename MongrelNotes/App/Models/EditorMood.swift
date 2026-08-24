import SwiftUI
import AppKit

// MARK: – EditorMood

/// A visual theme applied to the Markdown editor surface.
/// Each mood specifies background, text, cursor and selection colours, an
/// optional paper-line overlay, and a display name + icon.
///
/// Moods are stored as a String key in `Prefs.editorMood` (`@AppStorage`).
/// The NSTextView reads the resolved `MoodStyle` every time `updateNSView`
/// fires, so switching mood is instantaneous without restarting the app.
struct EditorMood: Identifiable, Equatable {

    // MARK: – Identity

    let id: String          // raw AppStorage value
    let name: String
    let icon: String        // SF Symbol

    // MARK: – Colours (NSColor for NSTextView, Color for SwiftUI preview)

    let background:       NSColor
    let text:             NSColor
    let dimText:          NSColor   // headings etc. at lower opacity
    let accent:           NSColor   // cursor + links + wikilinks
    let selection:        NSColor   // selected text highlight (alpha < 1)
    let scrollBg:         NSColor   // NSScrollView background (slightly darker)

    // MARK: – Overlay

    /// When `true` the text view draws faint ruled lines behind text.
    let ruledLines:       Bool
    /// When `true` a subtle noise/grain texture is layered (drawing is no-op if false).
    let grain:            Bool

    // MARK: – SwiftUI accessors

    var swiftUIBackground: Color { Color(background) }
    var swiftUIText:       Color { Color(text) }
    var swiftUIAccent:     Color { Color(accent) }

    // MARK: – All built-in moods

    static let all: [EditorMood] = [glass, paper, parchment, midnight, sepia, forest, chalk, carbon]

    static func named(_ id: String) -> EditorMood {
        all.first { $0.id == id } ?? glass
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: – Mood definitions
    // ──────────────────────────────────────────────────────────────────────

    // Glass  ─ Mongrel deep-black canvas.
    // Background matches DesignTokens.glassDeep dark (≈ #060810).
    // Text is pure white — notes are the content, they should sing.
    static let glass = EditorMood(
        id: "glass", name: "Glass", icon: "sparkles",
        background:  NSColor(calibratedHue: 222/360, saturation: 0.42, brightness: 0.05, alpha: 1),
        text:        NSColor(calibratedWhite: 1.00, alpha: 1),
        dimText:     NSColor(calibratedWhite: 1.00, alpha: 0.45),
        accent:      NSColor(calibratedHue: 222/360, saturation: 0.85, brightness: 0.88, alpha: 1),
        selection:   NSColor(calibratedHue: 222/360, saturation: 0.70, brightness: 0.72, alpha: 0.34),
        scrollBg:    NSColor(calibratedHue: 222/360, saturation: 0.44, brightness: 0.03, alpha: 1),
        ruledLines:  false, grain: false
    )

    // Paper  ─ warm cream / dark slate ink — reading-friendly daytime mood
    static let paper = EditorMood(
        id: "paper", name: "Paper", icon: "doc.plaintext",
        background:  NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.90, alpha: 1),
        text:        NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.12, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.12, alpha: 0.50),
        accent:      NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.72, alpha: 1),
        selection:   NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.72, alpha: 0.22),
        scrollBg:    NSColor(calibratedRed: 0.93, green: 0.90, blue: 0.84, alpha: 1),
        ruledLines:  true, grain: true
    )

    // Parchment  ─ aged yellowed paper, sepia ink
    static let parchment = EditorMood(
        id: "parchment", name: "Parchment", icon: "scroll",
        background:  NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.76, alpha: 1),
        text:        NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.07, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.07, alpha: 0.50),
        accent:      NSColor(calibratedRed: 0.65, green: 0.32, blue: 0.10, alpha: 1),
        selection:   NSColor(calibratedRed: 0.65, green: 0.32, blue: 0.10, alpha: 0.22),
        scrollBg:    NSColor(calibratedRed: 0.90, green: 0.85, blue: 0.68, alpha: 1),
        ruledLines:  true, grain: true
    )

    // Midnight  ─ deep navy blue, soft light text
    static let midnight = EditorMood(
        id: "midnight", name: "Midnight", icon: "moon.stars",
        background:  NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.14, alpha: 1),
        text:        NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.95, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.95, alpha: 0.50),
        accent:      NSColor(calibratedRed: 0.38, green: 0.68, blue: 1.00, alpha: 1),
        selection:   NSColor(calibratedRed: 0.38, green: 0.68, blue: 1.00, alpha: 0.30),
        scrollBg:    NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.10, alpha: 1),
        ruledLines:  false, grain: false
    )

    // Sepia  ─ warm amber tones, low-contrast for late-night writing
    static let sepia = EditorMood(
        id: "sepia", name: "Sepia", icon: "cup.and.saucer",
        background:  NSColor(calibratedRed: 0.14, green: 0.10, blue: 0.06, alpha: 1),
        text:        NSColor(calibratedRed: 0.90, green: 0.80, blue: 0.62, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.90, green: 0.80, blue: 0.62, alpha: 0.50),
        accent:      NSColor(calibratedRed: 0.90, green: 0.60, blue: 0.25, alpha: 1),
        selection:   NSColor(calibratedRed: 0.90, green: 0.60, blue: 0.25, alpha: 0.28),
        scrollBg:    NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.04, alpha: 1),
        ruledLines:  false, grain: true
    )

    // Forest  ─ dark hunter green, pale sage text
    static let forest = EditorMood(
        id: "forest", name: "Forest", icon: "tree",
        background:  NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.07, alpha: 1),
        text:        NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.78, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.78, alpha: 0.50),
        accent:      NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1),
        selection:   NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.25),
        scrollBg:    NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.05, alpha: 1),
        ruledLines:  false, grain: false
    )

    // Chalk  ─ chalkboard: very dark green bg, chalk-white hand-drawn feel
    static let chalk = EditorMood(
        id: "chalk", name: "Chalk", icon: "pencil.and.outline",
        background:  NSColor(calibratedRed: 0.07, green: 0.14, blue: 0.11, alpha: 1),
        text:        NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.90, alpha: 1),
        dimText:     NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.90, alpha: 0.48),
        accent:      NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.34, alpha: 1),
        selection:   NSColor(calibratedRed: 0.96, green: 0.82, blue: 0.34, alpha: 0.25),
        scrollBg:    NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.08, alpha: 1),
        ruledLines:  true, grain: true
    )

    // Carbon  ─ pure near-black, high contrast white — focused distraction-free writing
    static let carbon = EditorMood(
        id: "carbon", name: "Carbon", icon: "rectangle.fill",
        background:  NSColor(calibratedWhite: 0.05, alpha: 1),
        text:        NSColor(calibratedWhite: 0.92, alpha: 1),
        dimText:     NSColor(calibratedWhite: 0.92, alpha: 0.48),
        accent:      NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.35, alpha: 1),
        selection:   NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.35, alpha: 0.28),
        scrollBg:    NSColor(calibratedWhite: 0.02, alpha: 1),
        ruledLines:  false, grain: false
    )
}

// MARK: – Ruled-line / grain drawing helper

/// Draws a ruled-line and/or grain overlay into a given NSView.
/// Called from a custom NSScrollView subclass's `drawBackground(in:)`.
enum MoodOverlayRenderer {

    static func drawRuledLines(in rect: NSRect, lineHeight: CGFloat, textColor: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setStrokeColor(textColor.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(0.5)
        let startY = (rect.minY / lineHeight).rounded(.up) * lineHeight
        var y = startY
        while y <= rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += lineHeight
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func drawGrain(in rect: NSRect, opacity: CGFloat = 0.03) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // Cheap grain: random dots using a seeded pseudo-random walk
        ctx.setAlpha(opacity)
        ctx.setFillColor(NSColor.white.cgColor)
        let stride: CGFloat = 3
        var x = rect.minX
        var seed: UInt64 = 0xDEADBEEF
        while x < rect.maxX {
            var y = rect.minY
            while y < rect.maxY {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                if (seed >> 62) == 0 {
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
                y += stride
            }
            x += stride
        }
        ctx.restoreGState()
    }
}
