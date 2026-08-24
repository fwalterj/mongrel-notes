# MongrelNotes – Setup Guide

Apple Notes simplicity meets Obsidian power. macOS 14+, Apple Silicon-optimized, local-first.

MongrelNotes targets direct distribution. The app is intentionally not sandboxed because persistent access to arbitrary vault folders and optional command-line export tools are core behavior, not edge cases.

---

## Quick Start

### Prerequisites

```bash
# Homebrew
brew install xcodegen

# Xcode 15+
```

### Generate & open the Xcode project

```bash
cd MongrelNotes
xcodegen generate
open MongrelNotes.xcodeproj
```

Press **⌘R** to build and run.

---

## Project Structure

```
MongrelNotes/
├── SharedFoundation/          Swift package – models, parsing, persistence, UI tokens
│   └── Sources/SharedFoundation/
│       ├── Models/            Note.swift · Vault.swift · LinkGraph.swift
│       ├── Parsing/           WikilinkParser.swift
│       ├── Persistence/       VaultStore.swift
│       └── UI/                DesignTokens.swift · GlassChrome.swift
│
├── App/                       Main macOS application target
│   ├── MongrelNotesApp.swift  @main entry point, AppState, menu commands
│   ├── ContentView.swift      NavigationSplitView root, EditorHostView, WelcomeView
│   ├── Views/
│   │   ├── SidebarView.swift       Vault/folder/tag browser
│   │   ├── NoteListView.swift      Search, sort, note rows
│   │   ├── Editor/
│   │   │   ├── NoteEditorView.swift        SwiftUI host with backlinks panel + status bar
│   │   │   ├── MarkdownEditorNSView.swift  NSTextView wrapper + syntax highlighting
│   │   │   └── MarkdownPreviewView.swift   WKWebView HTML renderer
│   │   ├── Graph/
│   │   │   └── GraphView.swift     Force-directed link graph (SwiftUI Canvas)
│   │   ├── Canvas/
│   │   │   └── CanvasView.swift    Freeform drawing (NSBezierPath + Catmull-Rom)
│   │   └── SettingsView.swift
│   ├── ViewModels/
│   │   ├── VaultViewModel.swift
│   │   ├── NoteEditorViewModel.swift
│   │   └── GraphViewModel.swift
│   ├── Info.plist
│   ├── MongrelNotes.entitlements
│   └── Resources/
│
├── project.yml                XcodeGen specification
└── SETUP.md                   This file
```

---

## Design System

All visual tokens live in `DesignTokens.swift` and `GlassChrome.swift` and derive from `userChrome-glass.css`.

| Token | Value | Usage |
|---|---|---|
| `energyHue` | 196° (teal/cyan) | Brand colour base |
| `glassBase` | `hsla(196, 88%, 18%, 0.62)` | Sidebar, panels |
| `glassDeep` | `hsla(196, 92%, 12%, 0.74)` | Toolbar, editor bg |
| `glassHotSpot` | `hsla(196, 95%, 76%, 0.20)` | Radial specular |
| `borderRim` | `hsla(196, 100%, 90%, 0.28)` | All borders |
| `accent` | `hsl(196, 85%, 80%)` | Links, buttons, cursor |

Apply glass chrome to any view:
```swift
myView.glassChromeBackground(style: .base)   // panels
myView.glassChromeBackground(style: .deep)   // toolbars
myView.hoverBloom()                          // hover state
myView.selectedRowBackground(isSelected: x) // list rows
```

---

## Feature Map

| Feature | File | Status |
|---|---|---|
| File-based vault (plain `.md`) | `VaultStore.swift` | ✅ |
| iCloud Drive folder compatibility | `VaultStore.swift` | ✅ (ordinary filesystem folder) |
| `[[wikilinks]]` parsing | `WikilinkParser.swift` | ✅ |
| Backlinks panel | `NoteEditorView.swift` | ✅ |
| `#tag` extraction | `WikilinkParser.swift` | ✅ |
| Markdown syntax highlighting | `MarkdownEditorNSView.swift` | ✅ |
| Live preview | `MarkdownPreviewView.swift` | ✅ |
| Split editor | `NoteEditorView.swift` | ✅ |
| Force-directed graph | `GraphView.swift` + `GraphViewModel.swift` | ✅ |
| Freeform canvas | `CanvasView.swift` | ✅ |
| Full-text search | `VaultStore.search()` | ✅ |
| Auto-save (1.5s debounce) | `NoteEditorViewModel.swift` | ✅ |
| File-system watcher | `VaultStore.startWatching()` | ✅ |
| Word/char count | `NoteEditorViewModel.swift` | ✅ |
| Pin notes | `VaultStore`, `NoteListView` | ✅ |
| Daily note (⌘⇧D) | `AppState.createOrOpenDailyNote()` | ✅ |
| Command palette (⌘P) | `CommandPaletteView.swift` | ✅ |
| Spotlight indexing | `VaultStore` + `CSSearchableItem` | ✅ |
| Templates | `TemplateStore` + `NewNoteSheet` | ✅ |
| File drop (Finder → app) | `NoteListView.dropDestination` + `onOpenURL` | ✅ |
| CommonMark preview | `MarkdownHTMLConverter` (swift-markdown) | ✅ |
| Handoff / Continuity hooks | `NoteEditorView.userActivity` | ✅ (requires compatible signing) |
| PDF / HTML / Markdown export | `ExportManager.swift` | ✅ |
| DOCX / CSS / code export | `ExportManager.swift` | ✅ |
| Plugin system | _Planned v1.2_ | 🔜 |

---

## Next Steps

1. **Release packaging** – add a reproducible Developer ID archive and notarization script.
2. **Vault recovery** – expose missing or moved vaults at launch with a relink workflow.
3. **Contextual wikilink navigation** – clicking `[[links]]` in the preview navigates to that note.
4. **Plugin system** – define an external-tool protocol without coupling vault storage to plugins.

---

## Distribution and signing

Unsigned local builds require no Apple Developer account. `CODE_SIGNING_ALLOWED=NO` is supported by the smoke-test workflow. For sharing builds outside the development machine, use a Developer ID Application certificate and notarization; the Hardened Runtime setting is already enabled for that path.

The empty entitlements file is intentional. Keychain access works through the app's default keychain namespace, while vaults and iCloud Drive folders use normal filesystem access. Do not re-enable App Sandbox unless vault persistence is redesigned around security-scoped bookmarks and every external-tool workflow is replaced or brokered.
