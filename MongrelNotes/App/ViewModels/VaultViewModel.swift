import SwiftUI
import Combine
import SharedFoundation

/// ViewModel for the sidebar + note list, bridging `VaultStore` to SwiftUI views.
@MainActor
final class VaultViewModel: ObservableObject {

    // MARK: – Published

    @Published var visibleNotes: [Note] = []
    @Published var selectedNote: Note?
    @Published var sortOrder: SortOrder = .updatedAt
    @Published var filterTag: String?
    @Published var searchQuery: String = "" {
        didSet { debounceSearch() }
    }

    // MARK: – Dependencies

    let store: VaultStore
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: – Types

    enum SortOrder: String, CaseIterable, Identifiable {
        case updatedAt = "Last edited"
        case createdAt = "Created"
        case title    = "Title"
        var id: String { rawValue }
    }

    // MARK: – Init

    init(store: VaultStore) {
        self.store = store

        store.$notes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildVisible() }
            .store(in: &cancellables)
    }

    // MARK: – Actions

    func createNote(in folder: NoteFolder? = nil) {
        let note = store.createNote(title: "Untitled", in: folder)
        selectedNote = note
        rebuildVisible()
    }

    func deleteNote(_ note: Note) {
        store.delete(note)
        if selectedNote?.id == note.id { selectedNote = nil }
    }

    func pinNote(_ note: Note) {
        var updated = note
        updated = Note(
            id: note.id,
            fileURL: note.fileURL,
            title: note.title,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            isPinned: !note.isPinned,
            tags: note.tags
        )
        store.save(updated)
    }

    func backlinks(for note: Note) -> [Note] {
        store.backlinks(for: note)
    }

    // MARK: – Filtering / sorting

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            rebuildVisible()
        }
    }

    private func rebuildVisible() {
        var result = searchQuery.isEmpty
            ? store.notes
            : store.search(query: searchQuery)

        if let tag = filterTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        switch sortOrder {
        case .updatedAt:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            result.sort { $0.createdAt > $1.createdAt }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

        // Pinned notes float to the top.
        let pinned = result.filter(\.isPinned)
        let unpinned = result.filter { !$0.isPinned }
        visibleNotes = pinned + unpinned
    }

    // MARK: – All tags

    var allTags: [String] {
        Array(Set(store.notes.flatMap(\.tags))).sorted()
    }
}
