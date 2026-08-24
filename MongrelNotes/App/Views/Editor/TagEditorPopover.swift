import SwiftUI
import SharedFoundation

/// Popover that lets the user add and remove `#tag` tokens from the current note.
///
/// Tags are stored inline in the Markdown body (e.g. `#swift #ios`) and parsed by
/// `WikilinkParser.extractTags`. This view mutates the body via `NoteEditorViewModel`
/// methods, which triggers the existing 500 ms auto-save cycle automatically.
struct TagEditorPopover: View {

    @ObservedObject var viewModel: NoteEditorViewModel

    @State private var newTagText: String = ""
    @FocusState private var isFieldFocused: Bool

    // Validate the pending tag name against the same character class as WikilinkParser.
    private var isValid: Bool {
        let t = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty
            && t.range(of: #"^[a-z][a-z0-9_/-]*$"#, options: .regularExpression) != nil
            && !viewModel.liveTags.contains(t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().foregroundStyle(DesignTokens.borderRim)
            tagList
            Divider().foregroundStyle(DesignTokens.borderRim)
            newTagRow
        }
        .frame(width: 230)
        .background(DesignTokens.glassDeep)
        .onAppear { isFieldFocused = true }
    }

    // MARK: – Header

    private var header: some View {
        HStack {
            Text("Tags")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
            Spacer()
            Text("\(viewModel.liveTags.count)")
                .font(.caption2)
                .foregroundStyle(DesignTokens.accent)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: – Tag list

    @ViewBuilder
    private var tagList: some View {
        if viewModel.liveTags.isEmpty {
            Text("No tags yet — type one below.")
                .font(.caption)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.liveTags, id: \.self) { tag in
                        tagRow(tag)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 160)
        }
    }

    private func tagRow(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Text("#\(tag)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.accent)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.removeTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove #\(tag)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: – New tag input row

    private var newTagRow: some View {
        HStack(spacing: 5) {
            Text("#")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.accent.opacity(0.65))

            TextField("new-tag", text: $newTagText)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(DesignTokens.chromeText)
                .focused($isFieldFocused)
                // Strip spaces and uppercase as the user types.
                .onChange(of: newTagText) { _, v in
                    let sanitised = v
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                    if sanitised != v { newTagText = sanitised }
                }
                .onSubmit { commitNewTag() }

            Button {
                commitNewTag()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        isValid ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
            .help("Add tag (Return)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: – Helpers

    private func commitNewTag() {
        let t = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        viewModel.addTag(t)
        newTagText = ""
    }
}
