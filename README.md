# Mongrel Notes

A fast, local-first macOS notes application — part of the Mongrel app suite.

## Overview

Mongrel Notes is a native Swift notes app with an ominous-glass interface, plain Markdown vaults, wikilinks, backlinks, encryption, graph navigation, and practical document export. It is built with TextKit 2 and favors direct file ownership over service lock-in.

> **Work in progress:** the application is under active development. This repository is for source review, collaboration, and development builds rather than production use.

## Distribution direction

Mongrel Notes is being developed as a direct-distribution macOS app, not around App Store sandbox constraints. Vault folders remain available across relaunches, external tools such as Pandoc can participate in export workflows, and iCloud Drive works as an ordinary user-controlled folder rather than a proprietary sync backend. Hardened Runtime remains enabled so signed and notarized builds remain possible later.

## Stack

- **Language:** Swift
- **UI:** SwiftUI + AppKit
- **Build:** XcodeGen (`project.yml`)
- **Editor:** TextKit 2 with native Markdown syntax highlighting
- **Storage:** ordinary folders containing plain `.md` files

## Structure

```
MongrelNotes/
├── App/                  # SwiftUI/AppKit application target
├── SharedFoundation/     # Models, parsing, persistence, encryption, and UI tokens
├── Tests/                # Application unit tests
├── Scripts/              # Smoke tests and tooling
├── SETUP.md              # Local-development guide
└── project.yml           # XcodeGen project definition
```

## Current capabilities

- Multiple local vaults with relaunch persistence and file-system watching
- Markdown editing, preview, tags, wikilinks, backlinks, and full-text search
- Daily notes, templates, quick capture, pinning, Spotlight indexing, and Handoff hooks
- Optional per-note encryption backed by the macOS Keychain
- Link graph and freeform canvas views
- PDF, HTML, Markdown, DOCX, CSS, Python, and JavaScript export

## Build status

**BUILD SUCCEEDED** — verified on macOS with `CODE_SIGNING_ALLOWED=NO`.

The full smoke suite passes: 98 `SharedFoundation` tests, the app build, and 42 application tests.

## Build command

```bash
cd mongrel-notes/MongrelNotes
xcodegen generate
xcodebuild -project MongrelNotes.xcodeproj \
           -scheme MongrelNotes \
           -destination 'platform=macOS' \
           CODE_SIGNING_ALLOWED=NO build
```

## Source status

The source is visible during active development, but a formal open-source license has not been selected. No reuse license is granted yet; that boundary should be made explicit rather than implied by a public repository.
