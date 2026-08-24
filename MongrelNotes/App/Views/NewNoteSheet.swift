import SwiftUI
import SharedFoundation

/// Sheet shown by ⌘N that lets the user pick a template before creating a note.
///
/// Layout:
///   ┌─────────────────────────────────────────────┐
///   │  Title field                                 │
///   ├─────────────────────────────────────────────┤
///   │  Template grid (3 columns)                   │
///   │  ┌──────────┐ ┌──────────┐ ┌──────────┐    │
///   │  │  Blank   │ │ Meeting  │ │ Project  │    │
///   │  └──────────┘ └──────────┘ └──────────┘    │
///   ├─────────────────────────────────────────────┤
///   │  Preview pane (first 8 lines of template)    │
///   ├─────────────────────────────────────────────┤
///   │  [Cancel]                      [Create Note] │
///   └─────────────────────────────────────────────┘
struct NewNoteSheet: View {

    @Binding var isPresented: Bool
    var store: VaultStore
    /// Called with the newly created note so ContentView can select it.
    var onCreated: (Note) -> Void

    @StateObject private var templateStore: TemplateStore
    @State private var selected: NoteTemplate
    @State private var title: String = ""
    @FocusState private var titleFocused: Bool

    // Three columns, auto-sized.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    init(isPresented: Binding<Bool>, store: VaultStore, onCreated: @escaping (Note) -> Void) {
        _isPresented = isPresented
        self.store = store
        self.onCreated = onCreated
        let ts = TemplateStore(vaultURL: store.vault.rootURL)
        _templateStore = StateObject(wrappedValue: ts)
        _selected = State(initialValue: NoteTemplate.blank)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("New Note")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(DesignTokens.chromeText)

                TextField("Note title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(.body))
                    .foregroundStyle(DesignTokens.chromeText)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignTokens.glassBase)
                            .strokeBorder(DesignTokens.borderRim, lineWidth: 1)
                    )
                    .focused($titleFocused)
                    .onSubmit { createNote() }
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 16)

            Divider()
                .foregroundStyle(DesignTokens.borderRim)

            // ── Template grid ────────────────────────────────────────────────
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(templateStore.templates) { template in
                        TemplateCard(
                            template: template,
                            isSelected: selected == template
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selected = template
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(height: 220)

            Divider()
                .foregroundStyle(DesignTokens.borderRim)

            // ── Preview ──────────────────────────────────────────────────────
            TemplatePreview(template: selected)
                .frame(height: 130)

            Divider()
                .foregroundStyle(DesignTokens.borderRim)

            // ── Buttons ──────────────────────────────────────────────────────
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.6))

                Spacer()

                Button {
                    createNote()
                } label: {
                    Label("Create Note", systemImage: "plus")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .disabled(effectiveTitle.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560)
        .glassChromeBackground(style: .deep, cornerRadius: 12)
        .onAppear { titleFocused = true }
    }

    // MARK: – Helpers

    private var effectiveTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? "" : title.trimmingCharacters(in: .whitespaces)
    }

    private func createNote() {
        let resolvedTitle = effectiveTitle.isEmpty ? "Untitled" : effectiveTitle
        let body = selected.instantiate(title: resolvedTitle)
        let filled = store.createNote(title: resolvedTitle, body: body)
        isPresented = false
        onCreated(filled)
    }
}

// MARK: – Template card

private struct TemplateCard: View {
    let template: NoteTemplate
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: template.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.7))

            Text(template.name)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? DesignTokens.accent.opacity(0.18)
                      : (isHovered ? DesignTokens.glassBase.opacity(0.7) : DesignTokens.glassBase.opacity(0.4)))
                .strokeBorder(isSelected
                              ? DesignTokens.accent.opacity(0.6)
                              : DesignTokens.borderRim.opacity(isHovered ? 0.8 : 0.4),
                              lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

// MARK: – Template preview

private struct TemplatePreview: View {
    let template: NoteTemplate

    private var previewLines: String {
        let lines = template.body.components(separatedBy: "\n")
        return lines.prefix(8).joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                Text(previewLines)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(DesignTokens.glassBase.opacity(0.3))
    }
}
