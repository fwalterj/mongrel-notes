import SwiftUI
import SharedFoundation

/// Root three-column layout: sidebar (vaults/folders) | note list | editor/canvas.
struct ContentView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedFolder: NoteFolder?
    @State private var selectedNote: Note?
    @State private var searchQuery = ""
    @State private var selectedTag: String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showCommandPalette = false
    @State private var showNewNoteSheet = false

    // Seed the default editor mode from the user's Settings preference.
    @AppStorage(Prefs.defaultSplitMode) private var defaultSplitMode: String = "source"
    @State private var activeMode: EditorMode = .editor

    enum EditorMode: String, CaseIterable {
        case editor = "Editor"
        case preview = "Preview"
        case split = "Split"
        case graph = "Graph"
        case canvas = "Canvas"
    }

    var body: some View {
        Group {
            if appState.openVaults.isEmpty {
                WelcomeView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        selectedFolder: $selectedFolder,
                        selectedTag: $selectedTag,
                        activeMode: $activeMode
                    )
                    .navigationSplitViewColumnWidth(
                        min: 160,
                        ideal: DesignTokens.sidebarWidth,
                        max: 300
                    )
                } content: {
                    NoteListView(
                        selectedNote: $selectedNote,
                        folder: selectedFolder,
                        searchQuery: $searchQuery,
                        selectedTag: $selectedTag
                    )
                    .navigationSplitViewColumnWidth(
                        min: 220,
                        ideal: DesignTokens.listWidth,
                        max: 400
                    )
                } detail: {
                    EditorHostView(
                        note: $selectedNote,
                        mode: $activeMode
                    )
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background(DesignTokens.glassDeep.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Force the NSWindow background to deep black so NavigationSplitView's
        // system sidebar material can't bleed through our column backgrounds.
        .onAppear {
            switch defaultSplitMode {
            case "split":   activeMode = .split
            case "preview": activeMode = .preview
            default:        activeMode = .editor
            }
            DispatchQueue.main.async {
                NSApp.windows.forEach { window in
                    window.backgroundColor = NSColor(
                        calibratedHue: 222/360,
                        saturation: 0.42,
                        brightness: 0.05,
                        alpha: 1
                    )
                }
            }
        }
        // ── Command palette overlay ──────────────────────────────────────────
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(selectedNote: $selectedNote)
                .environmentObject(appState)
        }
        .alert(item: $appState.workflowAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        // ── New note sheet (template picker) ─────────────────────────────────
        .sheet(isPresented: $showNewNoteSheet) {
            if let store = appState.activeVault {
                NewNoteSheet(isPresented: $showNewNoteSheet, store: store) { note in
                    selectedNote = note
                    activeMode = .editor
                }
            }
        }
        // ── Keyboard shortcuts ───────────────────────────────────────────────
        .onKeyPress(.init("p"), phases: .down) { press in
            if press.modifiers == .command {
                showCommandPalette.toggle()
                return .handled
            }
            return .ignored
        }
        // ── Spotlight continuation (from AppState.openNoteBySpotlightID) ────
        .onReceive(NotificationCenter.default.publisher(for: .mongrelOpenNote)) { notif in
            guard let note = notif.userInfo?["note"] as? Note else { return }
            selectedFolder = nil
            selectedTag = nil
            searchQuery = ""
            selectedNote = note
            activeMode = .editor
        }
        // ── New note from menu / toolbar ──────────────────────────────────────
        .onReceive(NotificationCenter.default.publisher(for: .mongrelNewNote)) { _ in
            guard appState.activeVault != nil else { return }
            showNewNoteSheet = true
        }
        // ── Mode switch from command palette ─────────────────────────────────
        .onReceive(NotificationCenter.default.publisher(for: .mongrelSwitchMode)) { notif in
            guard let modeStr = notif.object as? String,
                  let mode = EditorMode(rawValue: modeStr.capitalized) else { return }
            activeMode = mode
        }
        // ── Sidebar toggle (⌘\) ──────────────────────────────────────────────
        .onReceive(NotificationCenter.default.publisher(for: .mongrelToggleSidebar)) { _ in
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onChange(of: appState.activeVault?.vault.id) { _, _ in
            selectedNote = nil
            selectedFolder = nil
            selectedTag = nil
            searchQuery = ""
        }
    }
}

// MARK: – Editor mode host

/// Switches between the markdown editor, live preview, split view, graph, and canvas.
struct EditorHostView: View {

    @Binding var note: Note?
    @Binding var mode: ContentView.EditorMode
    @EnvironmentObject private var appState: AppState

    private var activeVault: VaultStore? {
        appState.activeVault
    }

    private var selectedNoteInActiveVault: Note? {
        guard let activeVault, let note else { return nil }
        return activeVault.notes.first(where: { $0.id == note.id })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker toolbar strip
            HStack {
                Spacer()
                Picker("Mode", selection: $mode) {
                    ForEach(ContentView.EditorMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .padding(.horizontal)
            }
            .frame(height: 36)
            .glassChromeBackground(style: .deep, cornerRadius: 0)

            Divider()
                .foregroundStyle(DesignTokens.borderRim)

            // Content area
            // `.id(note?.id)` tears down and rebuilds the editor's @StateObject
            // each time a different note is selected, which is the correct SwiftUI
            // pattern when the child's @StateObject must be seeded from a prop.
            Group {
                if let vault = activeVault {
                    switch mode {
                    case .editor:
                        if let note = selectedNoteInActiveVault {
                            NoteEditorView(note: note, store: vault)
                                .id(note.id)
                        } else {
                            EmptyDetailPlaceholder()
                        }
                    case .preview:
                        if let note = selectedNoteInActiveVault {
                            MarkdownPreviewView(markdown: note.body)
                                .id(note.id)
                        } else {
                            EmptyDetailPlaceholder()
                        }
                    case .split:
                        if let note = selectedNoteInActiveVault {
                            SplitEditorView(note: note, store: vault)
                                .id(note.id)
                        } else {
                            EmptyDetailPlaceholder()
                        }
                    case .graph:
                        GraphView(store: vault, focusedNoteID: selectedNoteInActiveVault?.id)
                    case .canvas:
                        CanvasView()
                    }
                } else {
                    EmptyDetailPlaceholder()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: – Placeholder

struct EmptyDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.3))
            Text("Select a note or create a new one")
                .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                .font(DesignTokens.uiFont)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.glassDeep.ignoresSafeArea())
    }
}

// MARK: – Welcome screen

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DesignTokens.accent, DesignTokens.glassHotSpot],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("MongrelNotes")
                    .font(.system(size: 32, weight: .thin, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText)
                Text("Your local-first, Obsidian-compatible notes app")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
            }

            VStack(spacing: 16) {
                Button {
                    openVaultPanel()
                } label: {
                    Label("Open Vault…", systemImage: "folder.badge.plus")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .keyboardShortcut("O", modifiers: [.command, .shift])

                Button {
                    createNewVault()
                } label: {
                    Label("New Vault…", systemImage: "folder.badge.questionmark")
                        .frame(width: 200)
                }
                .buttonStyle(.bordered)
            }

            Text("Vaults are plain folders of .md files — compatible with Obsidian, iA Writer, and any text editor.")
                .font(.caption)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    private func openVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.openVault(at: url) }
    }

    private func createNewVault() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My Vault"
        panel.canCreateDirectories = true
        panel.prompt = "Create Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        Task { await appState.openVault(at: url) }
    }
}
