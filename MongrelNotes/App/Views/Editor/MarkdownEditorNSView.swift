import SwiftUI
import AppKit
import SharedFoundation

// MARK: – MongrelTextView

/// Custom NSTextView subclass that:
///  • Converts RTF/HTML clipboard content to Markdown on paste
///  • Exposes a callback for requesting inline text colour insertion
final class MongrelTextView: NSTextView {

    /// Called when the user pastes rich content that was converted to Markdown.
    var onPasteMarkdown: ((String) -> Void)?

    // ── Paste override ────────────────────────────────────────────────────

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // 1. Try HTML first (richer semantics than RTF)
        if let html = pb.string(forType: .html),
           let md = RichPasteConverter.htmlToMarkdown(html), !md.isEmpty {
            insertMarkdown(md)
            return
        }

        // 2. Fall back to RTF
        if let rtfData = pb.data(forType: .rtf),
           let attrStr = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           !attrStr.string.isEmpty {
            let md = RichPasteConverter.attributedStringToMarkdown(attrStr)
            if md != attrStr.string {          // only intercept if we added markup
                insertMarkdown(md)
                return
            }
        }

        // 3. Plain text — default behaviour
        super.paste(sender)
    }

    private func insertMarkdown(_ md: String) {
        // Replace selected range (or insert at cursor) like a normal paste.
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: md) {
            replaceCharacters(in: range, with: md)
            didChangeText()
        }
    }
}

// MARK: – Rich paste converter

enum RichPasteConverter {

    // ── HTML → Markdown ───────────────────────────────────────────────────

    static func htmlToMarkdown(_ html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attrStr = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return nil }
        return attributedStringToMarkdown(attrStr)
    }

    // ── NSAttributedString → Markdown ────────────────────────────────────
    // Walks the attributed string span-by-span, emitting Markdown for known
    // attributes and falling back to plain text for anything else.

    static func attributedStringToMarkdown(_ attrStr: NSAttributedString) -> String {
        var result = ""
        let full = NSRange(location: 0, length: attrStr.length)

        attrStr.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            var span = (attrStr.string as NSString).substring(with: range)

            // ── Detect inline colour (preserve as HTML span) ───────────
            var colorTag: (open: String, close: String) = ("", "")
            if let fg = attrs[.foregroundColor] as? NSColor {
                // Only emit a colour tag if it's meaningfully non-white / non-black
                let (r, g, b, _) = fg.sRGBComponents
                let isBlack = r < 0.15 && g < 0.15 && b < 0.15
                let isWhite = r > 0.85 && g > 0.85 && b > 0.85
                if !isBlack && !isWhite {
                    let hex = String(format: "#%02X%02X%02X",
                                     Int(r * 255), Int(g * 255), Int(b * 255))
                    colorTag = (open: "<span style=\"color:\(hex)\">", close: "</span>")
                }
            }

            // ── Bold / Italic ──────────────────────────────────────────
            var bold   = false
            var italic = false
            if let font = attrs[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                bold   = traits.contains(.boldFontMask)
                italic = traits.contains(.italicFontMask)
            }

            // ── Link ────────────────────────────────────────────────────
            var linkOpen  = ""
            var linkClose = ""
            if let link = attrs[.link] as? URL {
                linkOpen  = "["
                linkClose = "](\(link.absoluteString))"
            } else if let link = attrs[.link] as? String {
                linkOpen  = "["
                linkClose = "](\(link))"
            }

            // ── Heading (detect via font size ratio) ────────────────────
            var headingPrefix = ""
            if let font = attrs[.font] as? NSFont {
                let pt = font.pointSize
                if pt >= 22 { headingPrefix = "# " }
                else if pt >= 18 { headingPrefix = "## " }
                else if pt >= 15 { headingPrefix = "### " }
            }

            // ── Assemble ─────────────────────────────────────────────────
            span = headingPrefix + colorTag.open + linkOpen
                + (bold   ? "**" : "")
                + (italic ? "*"  : "")
                + span
                + (italic ? "*"  : "")
                + (bold   ? "**" : "")
                + linkClose + colorTag.close
            result += span
        }

        // Clean up artefacts from HTML whitespace normalisation
        result = result
            .replacingOccurrences(of: "\u{FFFC}", with: "")   // object-replacement chars
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
            .joined(separator: "\n")

        // Collapse 3+ blank lines → 2
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .newlines)
    }
}

// NSColor sRGB helper
extension NSColor {
    var sRGBComponents: (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard let srgb = usingColorSpace(.sRGB) else { return (0,0,0,1) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

// MARK: – MarkdownEditorNSView

/// SwiftUI wrapper around `MongrelTextView` with:
///  • Live syntax highlighting
///  • EditorMood theming (background, text, cursor, selection)
///  • RTF/HTML paste → Markdown conversion
///  • All user preferences (font, size, line height, width, spell check)
struct MarkdownEditorNSView: NSViewRepresentable {

    @Binding var text: String

    // Settings-driven properties — SwiftUI calls updateNSView on any change.
    @AppStorage(Prefs.editorFontFamily) private var fontFamily: String = "monospaced"
    @AppStorage(Prefs.editorFontSize)   private var fontSize:   Double = 14
    @AppStorage(Prefs.editorLineHeight) private var lineHeight: Double = 1.6
    @AppStorage(Prefs.editorMaxWidth)   private var maxWidth:   Double = 740
    @AppStorage(Prefs.spellCheck)       private var spell:      Bool   = true
    @AppStorage(Prefs.smartPunctuation) private var smartPunct: Bool   = false
    @AppStorage(Prefs.editorMood)       private var moodID:     String = "glass"

    private var mood: EditorMood { EditorMood.named(moodID) }

    // Resolve the NSFont from the family preference.
    private var resolvedFont: NSFont {
        let size = CGFloat(fontSize)
        switch fontFamily {
        case "serif":
            return NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
        case "sansSerif":
            return NSFont.systemFont(ofSize: size)
        case let name where !["monospaced","serif","sansSerif"].contains(name):
            return NSFont(name: name, size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Use the custom subclass so paste(_:) works correctly.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(DesignTokens.glassDeep)

        let textView = MongrelTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)

        let container = NSTextContainer(size: NSSize(width: CGFloat(maxWidth),
                                                     height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        let layoutMgr = NSLayoutManager()
        let storage   = NSTextStorage()
        storage.addLayoutManager(layoutMgr)
        layoutMgr.addTextContainer(container)
        textView.replaceTextContainer(container)

        scrollView.documentView = textView
        configure(textView: textView, coordinator: context.coordinator)
        context.coordinator.textView = textView   // weak back-reference for colour insertion
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MongrelTextView else { return }
        let m = mood

        // ── Mood colours ───────────────────────────────────────────────
        textView.backgroundColor        = .clear
        textView.drawsBackground        = false
        textView.insertionPointColor    = m.accent
        textView.selectedTextAttributes = [.backgroundColor: m.selection]
        scrollView.backgroundColor      = NSColor(DesignTokens.glassDeep)
        scrollView.drawsBackground      = true

        // ── Font ───────────────────────────────────────────────────────
        let font = resolvedFont
        if textView.font != font { textView.font = font }

        // ── Reading width ──────────────────────────────────────────────
        let containerWidth = CGFloat(maxWidth)
        if textView.textContainer?.containerSize.width != containerWidth {
            textView.textContainer?.containerSize = CGSize(
                width: containerWidth, height: .greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
        }

        // ── Spell check / smart punctuation ───────────────────────────
        textView.isContinuousSpellCheckingEnabled    = spell
        textView.isAutomaticQuoteSubstitutionEnabled = smartPunct
        textView.isAutomaticDashSubstitutionEnabled  = smartPunct

        // ── Sync text content ──────────────────────────────────────────
        let theme = MarkdownSyntaxHighlighter.Theme.current(
            fontSize: CGFloat(fontSize), fontFamily: fontFamily,
            lineHeight: CGFloat(lineHeight), mood: m
        )
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            MarkdownSyntaxHighlighter.apply(to: textView.textStorage!, theme: theme)
        } else {
            let tag = "\(fontFamily)-\(Int(fontSize))-\(lineHeight)-\(moodID)"
            if context.coordinator.lastThemeTag != tag {
                context.coordinator.lastThemeTag = tag
                MarkdownSyntaxHighlighter.apply(to: textView.textStorage!, theme: theme)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: – Configuration

    private func configure(textView: MongrelTextView, coordinator: Coordinator) {
        textView.delegate     = coordinator
        textView.isEditable   = true
        textView.isSelectable = true
        textView.isRichText   = false
        textView.allowsUndo   = true
        textView.usesFindBar  = true

        // Substitutions — synced by updateNSView
        textView.isAutomaticSpellingCorrectionEnabled  = false
        textView.isAutomaticQuoteSubstitutionEnabled   = false
        textView.isAutomaticDashSubstitutionEnabled    = false
        textView.isAutomaticTextReplacementEnabled     = true
        textView.isContinuousSpellCheckingEnabled      = true
        textView.isGrammarCheckingEnabled              = false

        // Font — synced by updateNSView
        textView.font = resolvedFont

        // Mood colours — synced by updateNSView; set defaults here to avoid
        // a white flash before the first updateNSView call.
        let m = mood
        textView.backgroundColor        = .clear
        textView.drawsBackground        = false
        textView.insertionPointColor    = m.accent
        textView.selectedTextAttributes = [.backgroundColor: m.selection]

        // Margins
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.textContainer?.lineFragmentPadding = 0

        // Paste callback — not needed directly but wires the hook
        textView.onPasteMarkdown = { [weak coordinator] _ in
            coordinator?.parent.text = textView.string
        }
    }

    // MARK: – Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorNSView
        var lastThemeTag: String = ""
        private var isUpdating = false
        private var observerToken: Any?
        weak var textView: MongrelTextView?

        init(_ parent: MarkdownEditorNSView) {
            self.parent = parent
            super.init()
            // Listen for inline-colour-span insertion requests from the toolbar.
            observerToken = NotificationCenter.default.addObserver(
                forName: .mongrelInsertColorSpan,
                object: nil, queue: .main
            ) { [weak self] note in
                self?.handleColorSpanInsertion(note)
            }
        }

        deinit {
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? MongrelTextView else { return }
            isUpdating = true
            parent.text = textView.string
            let theme = MarkdownSyntaxHighlighter.Theme.current(
                fontSize:   CGFloat(parent.fontSize),
                fontFamily: parent.fontFamily,
                lineHeight: CGFloat(parent.lineHeight),
                mood:       parent.mood
            )
            MarkdownSyntaxHighlighter.apply(to: textView.textStorage!, theme: theme)
            isUpdating = false
        }

        // MARK: – Colour span insertion

        private func handleColorSpanInsertion(_ note: Notification) {
            guard let tv = textView,
                  let open  = note.userInfo?["open"]  as? String,
                  let close = note.userInfo?["close"] as? String else { return }
            let sel = tv.selectedRange()
            if sel.length > 0 {
                // Wrap selected text
                let selected = (tv.string as NSString).substring(with: sel)
                let wrapped  = open + selected + close
                if tv.shouldChangeText(in: sel, replacementString: wrapped) {
                    tv.replaceCharacters(in: sel, with: wrapped)
                    tv.didChangeText()
                }
            } else {
                // Insert placeholder at cursor
                let placeholder = open + "text" + close
                let cursor = NSRange(location: sel.location, length: 0)
                if tv.shouldChangeText(in: cursor, replacementString: placeholder) {
                    tv.replaceCharacters(in: cursor, with: placeholder)
                    tv.didChangeText()
                    // Select the "text" placeholder for easy replacement
                    let textStart = sel.location + open.utf16.count
                    tv.setSelectedRange(NSRange(location: textStart, length: 4))
                }
            }
        }
    }
}

// MARK: – Markdown syntax highlighting

struct MarkdownSyntaxHighlighter {

    struct Theme {
        var bodyFont: NSFont
        var monoFont: NSFont
        var bodyColor: NSColor
        var heading1Color: NSColor
        var heading2Color: NSColor
        var heading3Color: NSColor
        var boldColor: NSColor
        var italicColor: NSColor
        var codeColor: NSColor
        var codeBackground: NSColor
        var linkColor: NSColor
        var wikilinkColor: NSColor
        var punctuationColor: NSColor

        /// Build a theme driven by the current EditorMood + font preferences.
        /// All colours are derived from the mood's palette so switching mood
        /// instantly recolours the editor's syntax highlighting.
        static func current(fontSize: CGFloat, fontFamily: String,
                            lineHeight: CGFloat, mood: EditorMood = .glass) -> Theme {
            let bodyNSFont: NSFont = {
                switch fontFamily {
                case "serif":     return NSFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize)
                case "sansSerif": return .systemFont(ofSize: fontSize)
                case let n where !["monospaced","serif","sansSerif"].contains(n):
                    return NSFont(name: n, size: fontSize)
                        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                default:          return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
                }
            }()
            let monoNSFont = NSFont.monospacedSystemFont(ofSize: max(fontSize - 1, 10), weight: .regular)

            // Derive highlight colours from the mood's text + accent colours.
            // For light moods (paper, parchment) we darken the accent;
            // for dark moods we lighten / saturate it.
            let base   = mood.text
            let accent = mood.accent
            let dim    = mood.dimText

            return Theme(
                bodyFont:         bodyNSFont,
                monoFont:         monoNSFont,
                bodyColor:        base,
                heading1Color:    accent,
                heading2Color:    accent.withAlphaComponent(0.85),
                heading3Color:    accent.withAlphaComponent(0.70),
                boldColor:        base,
                italicColor:      dim,
                codeColor:        accent,
                codeBackground:   accent.withAlphaComponent(0.12),
                linkColor:        accent,
                wikilinkColor:    accent.withAlphaComponent(0.90),
                punctuationColor: dim.withAlphaComponent(0.45)
            )
        }

        /// Convenience default using standard 14 pt monospaced font and Glass mood.
        static var `default`: Theme { .current(fontSize: 14, fontFamily: "monospaced", lineHeight: 1.6) }
    }

    static func apply(to storage: NSTextStorage, theme: Theme) {
        guard let text = storage.string as String? else { return }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        storage.beginEditing()

        // Reset to base body style
        storage.addAttributes([
            .font: theme.bodyFont,
            .foregroundColor: theme.bodyColor,
        ], range: fullRange)

        // Apply per-pattern rules
        for rule in highlightRules(theme: theme) {
            rule.regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match else { return }
                for (i, attrs) in rule.groupAttributes.enumerated() {
                    let groupIdx = i + 1
                    if groupIdx < match.numberOfRanges {
                        let r = match.range(at: groupIdx)
                        if r.location != NSNotFound {
                            storage.addAttributes(attrs, range: r)
                        }
                    }
                }
                if let baseAttrs = rule.baseAttributes {
                    storage.addAttributes(baseAttrs, range: match.range)
                }
            }
        }

        storage.endEditing()

        // Second pass: apply actual hex colours for <span style="color:…"> spans.
        applyInlineColours(to: storage)
    }

    // MARK: – Rule definitions

    private struct HighlightRule {
        let regex: NSRegularExpression
        let baseAttributes: [NSAttributedString.Key: Any]?
        let groupAttributes: [[NSAttributedString.Key: Any]]
    }

    private static func highlightRules(theme: Theme) -> [HighlightRule] {
        func re(_ pattern: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: opts)
        }

        let base = theme.bodyFont.pointSize
        let italic: NSFont = NSFontManager.shared.font(
            withFamily: theme.bodyFont.familyName ?? "Menlo",
            traits: .italicFontMask, weight: 5, size: base
        ) ?? theme.bodyFont

        return [
            // H1
            HighlightRule(
                regex: re(#"^(#{1}\s)(.+)$"#, .anchorsMatchLines),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.punctuationColor],
                    [.foregroundColor: theme.heading1Color,
                     .font: NSFont.systemFont(ofSize: base + 6, weight: .bold)]
                ]
            ),
            // H2
            HighlightRule(
                regex: re(#"^(#{2}\s)(.+)$"#, .anchorsMatchLines),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.punctuationColor],
                    [.foregroundColor: theme.heading2Color,
                     .font: NSFont.systemFont(ofSize: base + 3, weight: .semibold)]
                ]
            ),
            // H3
            HighlightRule(
                regex: re(#"^(#{3}\s)(.+)$"#, .anchorsMatchLines),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.punctuationColor],
                    [.foregroundColor: theme.heading3Color,
                     .font: NSFont.systemFont(ofSize: base + 1, weight: .medium)]
                ]
            ),
            // Bold **text**
            HighlightRule(
                regex: re(#"(\*\*|__)(.+?)(\*\*|__)"#),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.punctuationColor],
                    [.foregroundColor: theme.boldColor,
                     .font: NSFont.monospacedSystemFont(ofSize: base, weight: .bold)],
                    [.foregroundColor: theme.punctuationColor]
                ]
            ),
            // Italic *text*
            HighlightRule(
                regex: re(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.italicColor, .font: italic]
                ]
            ),
            // Inline code `code`
            HighlightRule(
                regex: re(#"`([^`]+)`"#),
                baseAttributes: [.backgroundColor: theme.codeBackground],
                groupAttributes: [
                    [.foregroundColor: theme.codeColor, .font: theme.monoFont]
                ]
            ),
            // [[Wikilinks]]
            HighlightRule(
                regex: re(#"\[\[([^\]]+)\]\]"#),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.wikilinkColor,
                     .underlineStyle: NSUnderlineStyle.single.rawValue]
                ]
            ),
            // [Links](url)
            HighlightRule(
                regex: re(#"\[([^\]]+)\]\(([^)]+)\)"#),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.linkColor,
                     .underlineStyle: NSUnderlineStyle.single.rawValue],
                    [.foregroundColor: theme.punctuationColor]
                ]
            ),
            // #Tags
            HighlightRule(
                regex: re(#"(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)"#),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.wikilinkColor]
                ]
            ),
            // HTML colour span punctuation: dim the <span …> and </span> tags
            HighlightRule(
                regex: re(#"(<span\s+style="color:[^"]*">)(.*?)(</span>)"#,
                          [.dotMatchesLineSeparators]),
                baseAttributes: nil,
                groupAttributes: [
                    [.foregroundColor: theme.punctuationColor],
                    [:],   // content — coloured by the live-colour pass below
                    [.foregroundColor: theme.punctuationColor]
                ]
            ),
        ]
    }

    // MARK: – Live inline-colour pass

    /// Second pass: for each `<span style="color:#RRGGBB">…</span>` in the
    /// storage, apply the actual hex colour to the inner text span.
    /// This is separate from the rule-based pass because the colour value
    /// is dynamic and can't be expressed as a fixed attribute set.
    static func applyInlineColours(to storage: NSTextStorage) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        guard let regex = try? NSRegularExpression(
            pattern: #"<span\s+style="color:(#[0-9A-Fa-f]{3,6})">(.+?)</span>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return }

        storage.beginEditing()
        regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match,
                  match.numberOfRanges == 3 else { return }
            let hexRange     = match.range(at: 1)
            let contentRange = match.range(at: 2)
            guard hexRange.location != NSNotFound,
                  contentRange.location != NSNotFound else { return }
            let hex = text.substring(with: hexRange)
            if let colour = NSColor(hexString: hex) {
                storage.addAttribute(.foregroundColor, value: colour, range: contentRange)
            }
        }
        storage.endEditing()
    }
}

// MARK: – NSColor hex initialiser

// MARK: – Notification names

extension Notification.Name {
    /// Posted by the editor toolbar's colour button to request a `<span style="color:…">` insertion.
    static let mongrelInsertColorSpan = Notification.Name("com.mongrel.notes.insertColorSpan")
}

// MARK: – SwiftUI Color → hex string

extension Color {
    /// Returns a CSS `#RRGGBB` hex string for this colour (ignoring alpha).
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X",
                      Int(r.clamped(0, 1) * 255),
                      Int(g.clamped(0, 1) * 255),
                      Int(b.clamped(0, 1) * 255))
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.max(lo, Swift.min(hi, self)) }
}

// MARK: – NSColor hex initialiser

extension NSColor {
    /// Initialises an `NSColor` from a CSS hex string: `#RGB`, `#RRGGBB`.
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        let len = hex.count
        guard len == 3 || len == 6,
              let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b: CGFloat
        if len == 3 {
            r = CGFloat((value >> 8) & 0xF) / 15.0
            g = CGFloat((value >> 4) & 0xF) / 15.0
            b = CGFloat( value       & 0xF) / 15.0
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255.0
            g = CGFloat((value >>  8) & 0xFF) / 255.0
            b = CGFloat( value        & 0xFF) / 255.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
