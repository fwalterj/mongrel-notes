import SwiftUI
import AppKit
import CoreSpotlight
import SharedFoundation

// MARK: – Preference keys (single source of truth, shared across app)

enum Prefs {
    // Editor
    static let editorFontFamily  = "editorFontFamily"   // String  → "monospaced" | "serif" | "sansSerif" | custom name
    static let editorFontSize    = "editorFontSize"      // Double  → 11…22
    static let editorLineHeight  = "editorLineHeight"    // Double  → 1.2…2.2
    static let editorMaxWidth    = "editorMaxWidth"      // Double  → 480…960
    static let autoSaveDelay     = "autoSaveDelay"       // Double  → 0.5…5
    static let showWordCount     = "showWordCount"       // Bool
    static let showCharCount     = "showCharCount"       // Bool
    static let spellCheck        = "spellCheck"          // Bool
    static let smartPunctuation  = "smartPunctuation"    // Bool
    static let defaultSplitMode  = "defaultSplitMode"   // String  → "source" | "split" | "preview"
    // Graph
    static let graphNodeRadius   = "graphNodeRadius"     // Double  → 4…14
    static let graphLinkOpacity  = "graphLinkOpacity"   // Double  → 0.05…1.0
    // Appearance
    static let editorMood        = "editorMood"         // String  → EditorMood.id
    // Advanced
    static let spotlightEnabled  = "spotlightEnabled"   // Bool
}

// MARK: – Main settings window

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            EditorSettingsPane()
                .tabItem { Label("Editor", systemImage: "pencil") }
            VaultsSettingsPane()
                .environmentObject(appState)
                .tabItem { Label("Vaults", systemImage: "folder") }
            GraphSettingsPane()
                .tabItem { Label("Graph", systemImage: "circle.hexagongrid") }
            AdvancedSettingsPane()
                .environmentObject(appState)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 440)
        .background(DesignTokens.glassDeep.ignoresSafeArea())
    }
}

// MARK: – Editor pane

private struct EditorSettingsPane: View {

    @AppStorage(Prefs.editorFontFamily) private var fontFamily: String = "monospaced"
    @AppStorage(Prefs.editorFontSize)   private var fontSize:   Double = 14
    @AppStorage(Prefs.editorLineHeight) private var lineHeight: Double = 1.6
    @AppStorage(Prefs.editorMaxWidth)   private var maxWidth:   Double = 740
    @AppStorage(Prefs.autoSaveDelay)    private var autoSave:   Double = 1.5
    @AppStorage(Prefs.showWordCount)    private var showWords:  Bool   = true
    @AppStorage(Prefs.showCharCount)    private var showChars:  Bool   = false
    @AppStorage(Prefs.spellCheck)       private var spell:      Bool   = true
    @AppStorage(Prefs.smartPunctuation) private var smartPunct: Bool   = false
    @AppStorage(Prefs.defaultSplitMode) private var splitMode:  String = "source"
    @AppStorage(Prefs.editorMood)       private var moodID:     String = "glass"

    // Font browser state
    @State private var fontSearch: String = ""
    @State private var showFontBrowser = false

    private var previewFont: Font {
        switch fontFamily {
        case "serif":     return .system(size: fontSize, design: .serif)
        case "sansSerif": return .system(size: fontSize, design: .default)
        default:          return .system(size: fontSize, design: .monospaced)
        }
    }

    private var mood: EditorMood { EditorMood.named(moodID) }

    var body: some View {
        Form {
            // ── Mood / Paper ──────────────────────────────────────────────
            Section("Mood") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EditorMood.all) { m in
                            MoodSwatch(mood: m, isSelected: moodID == m.id) {
                                moodID = m.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Mini preview
                ZStack(alignment: .topLeading) {
                    // Paper/ruled-lines overlay
                    if mood.ruledLines {
                        Canvas { ctx, size in
                            let lh = CGFloat(lineHeight) * CGFloat(fontSize) + 4
                            var y = lh + 10
                            while y < size.height {
                                var p = Path()
                                p.move(to: CGPoint(x: 12, y: y))
                                p.addLine(to: CGPoint(x: size.width - 12, y: y))
                                ctx.stroke(p, with: .color(Color(mood.text).opacity(0.07)), lineWidth: 0.5)
                                y += lh
                            }
                        }
                    }
                    Text("The quick brown fox jumps over the lazy dog.\n[[WikiLink]] **bold** *italic* `code` #tag")
                        .font(previewFont)
                        .lineSpacing((lineHeight - 1.0) * fontSize)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color(mood.text))
                }
                .frame(height: 72)
                .background(Color(mood.background))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.glassBorder, lineWidth: 0.5))
            }

            // ── Font ──────────────────────────────────────────────────────
            Section("Font") {
                HStack {
                    // Current font display
                    Text(displayNameFor(fontFamily))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Browse…") { showFontBrowser = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .sheet(isPresented: $showFontBrowser) {
                    SystemFontBrowser(selectedFamily: $fontFamily)
                }

                LabeledSlider(label: "Size",         value: $fontSize,  range: 11...22,  step: 1,   display: "\(Int(fontSize)) pt")
                LabeledSlider(label: "Line height",  value: $lineHeight, range: 1.2...2.2, step: 0.1, display: String(format: "%.1f×", lineHeight))
                LabeledSlider(label: "Reading width", value: $maxWidth,  range: 480...960, step: 20,  display: "\(Int(maxWidth)) pt")
            }

            // ── Behaviour ─────────────────────────────────────────────────
            Section("Behaviour") {
                LabeledSlider(label: "Auto-save delay", value: $autoSave, range: 0.5...5, step: 0.5,
                              display: String(format: "%.1f s", autoSave))
                Picker("Default view", selection: $splitMode) {
                    Text("Source").tag("source")
                    Text("Split").tag("split")
                    Text("Preview").tag("preview")
                }
                .pickerStyle(.segmented)
                Toggle("Spell checking", isOn: $spell)
                Toggle("Smart punctuation (\"quotes\" and — dashes)", isOn: $smartPunct)
            }

            // ── Status bar ────────────────────────────────────────────────
            Section("Status bar") {
                Toggle("Show word count", isOn: $showWords)
                Toggle("Show character count", isOn: $showChars)
            }
        }
        .padding()
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func displayNameFor(_ family: String) -> String {
        switch family {
        case "monospaced": return "Monospaced System"
        case "serif":      return "Serif System"
        case "sansSerif":  return "Sans-Serif System"
        default:           return family
        }
    }
}

// MARK: – Mood swatch chip

private struct MoodSwatch: View {
    let mood: EditorMood
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(mood.background))
                    .frame(width: 44, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color(mood.accent) : DesignTokens.glassBorder,
                                    lineWidth: isSelected ? 2 : 0.5)
                    )
                Image(systemName: mood.icon)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color(mood.accent))
            }
            .scaleEffect(hovered ? 1.08 : 1)
            .animation(.spring(response: 0.2), value: hovered)

            Text(mood.name)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.5))
        }
        .onTapGesture(perform: onTap)
        .onHover { hovered = $0 }
    }
}

// MARK: – System font browser sheet

private struct SystemFontBrowser: View {
    @Binding var selectedFamily: String
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""
    @State private var localSelection: String

    // Pull every family from NSFontManager once
    private let systemFamilies: [String] = {
        let mgr = NSFontManager.shared
        return (mgr.availableFontFamilies as [String]).sorted()
    }()

    private let pinned: [String] = ["monospaced", "serif", "sansSerif"]

    init(selectedFamily: Binding<String>) {
        _selectedFamily = selectedFamily
        _localSelection = State(initialValue: selectedFamily.wrappedValue)
    }

    private var filteredFamilies: [String] {
        let q = search.lowercased()
        let sys = systemFamilies.filter { q.isEmpty || $0.lowercased().contains(q) }
        if search.isEmpty { return sys }
        return sys
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("System Fonts")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.chromeText)
                Spacer()
                Button("Done") {
                    selectedFamily = localSelection
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider().foregroundStyle(DesignTokens.glassBorder)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                TextField("Search fonts…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignTokens.glassBase.opacity(0.3))

            Divider().foregroundStyle(DesignTokens.glassBorder)

            // Font list
            ScrollViewReader { proxy in
                List(selection: $localSelection) {
                    if search.isEmpty {
                        Section("System Styles") {
                            FontFamilyRow(family: "monospaced", displayName: "Monospaced System",
                                         isSelected: localSelection == "monospaced")
                            FontFamilyRow(family: "serif",      displayName: "Serif System",
                                         isSelected: localSelection == "serif")
                            FontFamilyRow(family: "sansSerif",  displayName: "Sans-Serif System",
                                         isSelected: localSelection == "sansSerif")
                        }
                        Section("All Fonts (\(systemFamilies.count))") {
                            ForEach(systemFamilies, id: \.self) { fam in
                                FontFamilyRow(family: fam, displayName: fam,
                                             isSelected: localSelection == fam)
                            }
                        }
                    } else {
                        ForEach(filteredFamilies, id: \.self) { fam in
                            FontFamilyRow(family: fam, displayName: fam,
                                         isSelected: localSelection == fam)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(localSelection, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
        .background(DesignTokens.glassDeep)
    }
}

private struct FontFamilyRow: View {
    let family: String
    let displayName: String
    let isSelected: Bool

    private var sampleFont: NSFont {
        switch family {
        case "serif":     return NSFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13)
        case "sansSerif": return .systemFont(ofSize: 13)
        default:
            return NSFont(name: family, size: 13)
                ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText)
                // Render a brief glyph sample in the actual font
                Text("Aa Bb 1234")
                    .font(Font(sampleFont))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.45))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            }
        }
        .contentShape(Rectangle())
        .tag(family)
    }
}

// Reusable slider row
private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            Slider(value: $value, in: range, step: step)
                .frame(width: 160)
            Text(display)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
        }
    }
}

// MARK: – Vaults pane

private struct VaultsSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var indexingVaultID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(appState.openVaults, id: \.vault.id) { store in
                    VaultRow(
                        store: store,
                        isIndexing: indexingVaultID == store.vault.id,
                        onClose: { appState.closeVault(store) },
                        onReindex: {
                            Task {
                                indexingVaultID = store.vault.id
                                store.reindexAll()
                                try? await Task.sleep(nanoseconds: 900_000_000)
                                if indexingVaultID == store.vault.id { indexingVaultID = nil }
                            }
                        }
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.glassBase.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignTokens.glassBorder, lineWidth: 0.5)
            )

            HStack {
                Button {
                    openVaultPanel()
                } label: {
                    Label("Open Vault…", systemImage: "folder.badge.plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.accent)
                .padding(.vertical, 10)

                Spacer()

                if !appState.openVaults.isEmpty {
                    let total = appState.openVaults.reduce(0) { $0 + $1.notes.count }
                    Text("\(appState.openVaults.count) vault\(appState.openVaults.count == 1 ? "" : "s") · \(total) notes")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                }
            }
            .padding(.horizontal, 4)
        }
        .padding()
    }

    private func openVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to use as a MongrelNotes vault"
        panel.prompt = "Open Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.openVault(at: url) }
    }
}

private struct VaultRow: View {
    let store: VaultStore
    let isIndexing: Bool
    let onClose: () -> Void
    let onReindex: () -> Void
    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignTokens.accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: store.vault.isCloudBacked ? "icloud" : "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignTokens.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.vault.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DesignTokens.chromeText)
                Text(store.vault.rootURL.abbreviatingWithTilde)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Note count badge
            Text("\(store.notes.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(DesignTokens.accent.opacity(0.12))
                .clipShape(Capsule())

            // Spotlight re-index
            Button(action: onReindex) {
                if isIndexing {
                    ProgressView().controlSize(.small).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
            .help("Re-index in Spotlight")

            // Close
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.chromeText.opacity(closeHovered ? 0.55 : 0.2))
            }
            .buttonStyle(.plain)
            .help("Close vault")
            .onHover { closeHovered = $0 }
        }
        .padding(.vertical, 4)
    }
}

// MARK: – Graph pane

private struct GraphSettingsPane: View {
    @AppStorage(Prefs.graphNodeRadius)  private var nodeRadius:  Double = 6
    @AppStorage(Prefs.graphLinkOpacity) private var linkOpacity: Double = 0.4

    var body: some View {
        Form {
            Section("Nodes") {
                LabeledSlider(
                    label: "Node radius",
                    value: $nodeRadius, range: 4...14, step: 1,
                    display: "\(Int(nodeRadius)) pt"
                )
            }

            Section("Edges") {
                LabeledSlider(
                    label: "Link opacity",
                    value: $linkOpacity, range: 0.05...1.0, step: 0.05,
                    display: String(format: "%.0f%%", linkOpacity * 100)
                )
            }

            Section("Preview") {
                GraphPreviewCanvas(nodeRadius: nodeRadius, linkOpacity: linkOpacity)
                    .frame(height: 110)
                    .background(DesignTokens.glassBase.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct GraphPreviewCanvas: View {
    let nodeRadius: Double
    let linkOpacity: Double

    private let positions: [(CGFloat, CGFloat, Bool)] = [
        (0.50, 0.45, true),
        (0.20, 0.25, false),
        (0.75, 0.22, false),
        (0.30, 0.72, false),
        (0.68, 0.72, false),
    ]
    private let edges = [(0,1),(0,2),(0,3),(0,4),(1,3)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r  = CGFloat(nodeRadius)
            let pts = positions.map { CGPoint(x: $0.0 * w, y: $0.1 * h) }

            Canvas { ctx, _ in
                for (a, b) in edges {
                    var path = Path()
                    path.move(to: pts[a])
                    path.addLine(to: pts[b])
                    ctx.stroke(path,
                               with: .color(DesignTokens.accent.opacity(linkOpacity)),
                               lineWidth: 1)
                }
                for (i, pt) in pts.enumerated() {
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Circle().path(in: rect),
                             with: .color(DesignTokens.accent.opacity(i == 0 ? 1.0 : 0.55)))
                }
            }
        }
        .padding(12)
    }
}

// MARK: – Advanced pane

private struct AdvancedSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(Prefs.spotlightEnabled) private var spotlightEnabled: Bool = true
    @State private var isReindexing = false
    @State private var reindexDone  = false

    var body: some View {
        Form {
            // ── Spotlight ────────────────────────────────────────────────
            Section("Spotlight") {
                Toggle("Index notes in Spotlight", isOn: $spotlightEnabled)
                    .onChange(of: spotlightEnabled) { _, enabled in
                        if !enabled {
                            CSSearchableIndex.default().deleteAllSearchableItems { _ in }
                        }
                    }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Re-index all vaults")
                        Text("Forces a full rebuild of the Spotlight index for every open vault.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.38))
                    }
                    Spacer()
                    Group {
                        if reindexDone {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        } else if isReindexing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Re-index") { reindexAll() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!spotlightEnabled)
                        }
                    }
                    .font(.callout)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Spotlight index")
                        Text("Removes all MongrelNotes entries from Spotlight.")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.38))
                    }
                    Spacer()
                    Button("Clear") {
                        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            // ── Keyboard shortcuts ────────────────────────────────────────
            Section("Keyboard shortcuts") {
                ShortcutRow(key: "⌘N",   label: "New note")
                ShortcutRow(key: "⌘⇧D",  label: "Today's daily note")
                ShortcutRow(key: "⌘⇧O",  label: "Open vault…")
                ShortcutRow(key: "⌘P",   label: "Command palette")
                ShortcutRow(key: "⌘S",   label: "Save now")
                ShortcutRow(key: "⌘⇧B",  label: "Toggle backlinks panel")
                ShortcutRow(key: "⌘\\",  label: "Toggle sidebar")
            }

            // ── Reset ─────────────────────────────────────────────────────
            Section {
                HStack {
                    Spacer()
                    Button("Reset All Settings to Defaults") { resetDefaults() }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding()
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func reindexAll() {
        isReindexing = true
        reindexDone  = false
        appState.openVaults.forEach { $0.reindexAll() }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isReindexing = false
            withAnimation { reindexDone = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { reindexDone = false }
        }
    }

    private func resetDefaults() {
        [Prefs.editorFontFamily, Prefs.editorFontSize, Prefs.editorLineHeight,
         Prefs.editorMaxWidth, Prefs.autoSaveDelay, Prefs.showWordCount,
         Prefs.showCharCount, Prefs.spellCheck, Prefs.smartPunctuation,
         Prefs.defaultSplitMode, Prefs.editorMood,
         Prefs.graphNodeRadius, Prefs.graphLinkOpacity,
         Prefs.spotlightEnabled]
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

private struct ShortcutRow: View {
    let key: String
    let label: String
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.85))
            Spacer()
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DesignTokens.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(DesignTokens.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

// MARK: – About pane

private struct AboutPane: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [DesignTokens.accent.opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 44))
                    .frame(width: 88, height: 88)
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(
                        colors: [DesignTokens.accent, DesignTokens.glassHotSpot],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(spacing: 4) {
                Text("MongrelNotes")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText)
                Text("Version \(version) (\(build))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
            }

            Text("Apple Notes simplicity · Obsidian power\nLocal-first · iCloud Drive compatible · Plain Markdown")
                .font(.callout)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Divider()
                .frame(width: 180)

            HStack(spacing: 28) {
                AboutLink(label: "Privacy", icon: "hand.raised") {
                    NSWorkspace.shared.open(URL(string: "https://anthropic.com/privacy")!)
                }
                AboutLink(label: "Licenses", icon: "doc.text") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/apple/swift-markdown")!)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct AboutLink: View {
    let label: String
    let icon: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .light))
                Text(label).font(.caption)
            }
            .foregroundStyle(hovered ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.4))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }
}

// MARK: – URL helper

private extension URL {
    var abbreviatingWithTilde: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
