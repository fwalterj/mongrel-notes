import SwiftUI
import SharedFoundation

/// Left-most column: vault switcher, folder tree, tags, and quick filters.
struct SidebarView: View {

    @EnvironmentObject private var appState: AppState
    @Binding var selectedFolder: NoteFolder?
    @Binding var selectedTag: String?
    @Binding var activeMode: ContentView.EditorMode
    @State private var showTagFilter: Bool = true

    var body: some View {
        // Plain List (no selection: binding) so our custom SidebarRowView
        // button actions control selection without fighting the List's own
        // built-in selection mechanism.
        List {
            ForEach(appState.openVaults, id: \.vault.id) { store in
                vaultSection(store)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.glassBase.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomToolbar }
        .toolbar { sidebarToolbar }
    }

    // MARK: – Vault section

    /// Wrapper that holds an @ObservedObject reference to the store so that
    /// published properties like `isLoading`, `notes`, and `folders` correctly
    /// trigger SwiftUI redraws inside the section.
    @ViewBuilder
    private func vaultSection(_ store: VaultStore) -> some View {
        ObservingVaultSection(
            store: store,
            selectedFolder: $selectedFolder,
            selectedTag: $selectedTag,
            showTagFilter: showTagFilter,
            isActive: appState.activeVault === store
        ) { store in
            appState.activeVault = store
        }
    }

    // MARK: – Bottom toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 4) {
            Button {
                NotificationCenter.default.post(name: .mongrelNewNote, object: nil)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText)
            .hoverBloom()
            .help("New Note… (⌘N)")

            Button {
                appState.createOrOpenDailyNote()
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText)
            .hoverBloom()
            .help("Today's Daily Note (⌘⇧D)")

            Spacer()

            Button {
                openVaultPanel()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText)
            .hoverBloom()
            .help("Open Vault…")
        }
        .padding(8)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    // MARK: – Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
    }

    private func openVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.openVault(at: url) }
    }
}

// MARK: – Observed vault section
// A separate View that holds @ObservedObject so published changes in VaultStore
// (isLoading, notes, folders) properly invalidate this subtree.

private struct ObservingVaultSection: View {
    @ObservedObject var store: VaultStore
    @Binding var selectedFolder: NoteFolder?
    @Binding var selectedTag: String?
    let showTagFilter: Bool
    let isActive: Bool
    let onActivate: (VaultStore) -> Void

    var body: some View {
        Section {
            SidebarRowView(
                label: "All Notes",
                icon: "note.text",
                isSelected: selectedFolder == nil && selectedTag == nil && isActive
            ) {
                onActivate(store)
                selectedFolder = nil
                selectedTag = nil
            }

            ForEach(store.folders) { folder in
                SidebarRowView(
                    label: folder.name,
                    icon: "folder",
                    isSelected: selectedFolder == folder && selectedTag == nil
                ) {
                    onActivate(store)
                    selectedFolder = folder
                    selectedTag = nil
                }
            }

            if showTagFilter {
                let tags = Array(Set(store.notes.flatMap(\.tags))).sorted()
                if !tags.isEmpty {
                    DisclosureGroup("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            SidebarRowView(
                                label: "#\(tag)",
                                icon: "tag",
                                isSelected: selectedTag == tag
                            ) {
                                onActivate(store)
                                selectedFolder = nil
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .disclosureGroupStyle(.sidebar)
                }
            }
        } header: {
            HStack {
                Text(store.vault.name)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
                    .textCase(nil)
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.mini)
                } else if store.vault.isCloudBacked {
                    Image(systemName: "icloud")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.accent.opacity(0.7))
                }
            }
        }
    }
}

// MARK: – Sidebar row

struct SidebarRowView: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.7))
                Text(label)
                    .font(DesignTokens.uiFont)
                    .foregroundStyle(isSelected ? DesignTokens.chromeText : DesignTokens.chromeText.opacity(0.8))
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .selectedRowBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: – DisclosureGroup sidebar style

struct SidebarDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                    configuration.label
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.6))
                        .font(.system(.caption, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content.padding(.leading, 12)
            }
        }
    }
}

extension DisclosureGroupStyle where Self == SidebarDisclosureGroupStyle {
    static var sidebar: SidebarDisclosureGroupStyle { SidebarDisclosureGroupStyle() }
}
