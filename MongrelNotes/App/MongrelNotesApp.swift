import SwiftUI
import SharedFoundation
import CoreSpotlight
import AppKit

@main
struct MongrelNotesApp: App {

    @StateObject private var appState     = AppState()
    @StateObject private var encManager   = EncryptionManager()

    @SceneBuilder
    var body: some Scene {
        mainWindowScene
        settingsScene
    }

    private var mainWindowScene: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(encManager)
                .frame(minWidth: 900, minHeight: 600)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightContinuation(activity)
                }
                .onContinueUserActivity(Handoff.activityType) { activity in
                    handleHandoffContinuation(activity)
                }
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            AppCommands(appState: appState)
        }
    }

    private var settingsScene: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(encManager)
        }
    }

    private func handleSpotlightContinuation(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        appState.openNoteBySpotlightID(id)
    }

    private func handleHandoffContinuation(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[Handoff.noteIDKey] as? String else { return }
        appState.openNoteBySpotlightID(id)
    }

    private func handleOpenURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "md" else { return }
        guard let store = appState.activeVault else {
            appState.presentWorkflowAlert(
                title: "No Vault Open",
                message: "Open a vault before importing Markdown files."
            )
            return
        }
        if let note = store.importFile(at: url) {
            NotificationCenter.default.post(
                name: .mongrelOpenNote,
                object: nil,
                userInfo: ["note": note]
            )
        } else {
            appState.presentWorkflowAlert(
                title: "Import Failed",
                message: "MongrelNotes could not import that Markdown file."
            )
        }
    }
}

// MARK: – Spotlight continuation handler

extension MongrelNotesApp {
    /// Called when macOS hands off a Spotlight result to the app.
    /// Finds the note by UUID (stored as the Spotlight item's unique identifier)
    /// and makes it the selected note in the active vault.
    static func handleSpotlightActivity(_ activity: NSUserActivity) -> Note? {
        guard activity.activityType == CSSearchableItemActionType,
              let uuidString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let uuid = UUID(uuidString: uuidString) else { return nil }
        // AppState is a singleton-like shared object; look up across all vaults.
        // In practice you'd inject appState here, but the app scene handles this
        // via `.onContinueUserActivity` on the WindowGroup.
        return nil  // resolved by the scene handler below
    }
}

// MARK: – AppState Spotlight integration

extension AppState {
    // MARK: – Daily note

    // MARK: – Quick note

    /// Creates a note from plain text currently available on the clipboard.
    /// The first line becomes the title when possible, and the remaining text
    /// is used as the body.
    @discardableResult
    func createQuickNoteFromClipboard() -> Note? {
        guard let store = activeVault else {
            presentWorkflowAlert(
                title: "No Vault Open",
                message: "Open a vault before creating a quick note."
            )
            return nil
        }

        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentWorkflowAlert(
                title: "Clipboard Is Empty",
                message: "Copy text first, then run Quick Note from Clipboard."
            )
            return nil
        }

        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultTitle = "Quick Note \(DateFormatter.quickNoteTimestamp.string(from: Date()))"
        let title = firstLine.isEmpty ? defaultTitle : firstLine

        let remainingBody = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyContent = remainingBody.isEmpty ? normalized : remainingBody
        let body = "# \(title)\n\n\(bodyContent)"

        let note = store.createNote(title: title, body: body)
        NotificationCenter.default.post(
            name: .mongrelOpenNote,
            object: nil,
            userInfo: ["note": note]
        )
        return note
    }

    /// Opens today's daily note (YYYY-MM-DD.md), creating it if it doesn't exist.
    /// Posts `.mongrelOpenNote` so ContentView navigates to it automatically.
    @discardableResult
    func createOrOpenDailyNote() -> Note? {
        guard let store = activeVault else {
            presentWorkflowAlert(
                title: "No Vault Open",
                message: "Open a vault before creating a daily note."
            )
            return nil
        }
        let today = ISO8601DateFormatter.dailyNoteFormatter.string(from: Date())
        let title = today
        // Look for an existing note with this title.
        if let existing = store.notes.first(where: { $0.title == title }) {
            NotificationCenter.default.post(
                name: .mongrelOpenNote, object: nil, userInfo: ["note": existing]
            )
            return existing
        }
        // Create a new daily note with a template body.
        let body = """
        # \(today)

        ## Tasks
        - [ ]

        ## Notes


        ## Journal


        """
        let templated = store.createNote(title: title, body: body)
        NotificationCenter.default.post(
            name: .mongrelOpenNote, object: nil, userInfo: ["note": templated]
        )
        return templated
    }

    /// Find a note by UUID across all open vaults and make it active.
    func openNoteBySpotlightID(_ uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            presentWorkflowAlert(
                title: "Could Not Open Note",
                message: "The Spotlight item identifier is invalid."
            )
            return
        }
        for vault in openVaults {
            if let note = vault.notes.first(where: { $0.id == uuid }) {
                activeVault = vault
                // Post a notification that ContentView observes to select the note.
                NotificationCenter.default.post(
                    name: .mongrelOpenNote,
                    object: nil,
                    userInfo: ["note": note]
                )
                return
            }
        }
        presentWorkflowAlert(
            title: "Note Not Found",
            message: "That note is not available in currently open vaults."
        )
    }
}

struct WorkflowAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension Notification.Name {
    static let mongrelOpenNote      = Notification.Name("com.mongrel.notes.openNote")
    static let mongrelNewNote       = Notification.Name("com.mongrel.notes.newNote")
    static let mongrelToggleSidebar = Notification.Name("com.mongrel.notes.toggleSidebar")
}

// MARK: – Handoff constants

/// Shared constants for the Handoff `NSUserActivity` published while a note is open.
/// The activity type must also appear in `Info.plist` under `NSUserActivityTypes`.
enum Handoff {
    static let activityType = "com.mongrel.notes.editNote"
    static let noteIDKey    = "noteID"
    static let vaultURLKey  = "vaultPath"
}

extension ISO8601DateFormatter {
    /// Formatter that produces `YYYY-MM-DD` strings for daily note filenames.
    @MainActor
    static let dailyNoteFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}

extension DateFormatter {
    static let quickNoteTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()
}

// MARK: – App-wide state

@MainActor
final class AppState: ObservableObject {

    // MARK: – Vault management

    @Published var openVaults: [VaultStore] = []
    @Published var activeVault: VaultStore?
    @Published var workflowAlert: WorkflowAlert?

    // MARK: – Persistence of vault list

    private let vaultListKey = "com.mongrel.notes.vaultList"
    private let defaults: UserDefaults

    /// Standard initialiser — uses `UserDefaults.standard`.
    init() {
        self.defaults = .standard
        restoreVaults()
    }

    /// Testability initialiser — accepts an injected `UserDefaults` instance so
    /// unit tests can use an isolated suite without touching the real user defaults.
    init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
        // Do NOT restore vaults automatically in tests.
    }

    func openVault(at url: URL) async {
        let normalizedURL = url.standardizedFileURL

        if let existing = openVaults.first(where: { $0.vault.rootURL.standardizedFileURL == normalizedURL }) {
            activeVault = existing
            return
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDir), isDir.boolValue else {
            presentWorkflowAlert(
                title: "Vault Unavailable",
                message: "The selected folder no longer exists or is not a directory."
            )
            return
        }

        let vault = Vault(
            name: normalizedURL.lastPathComponent,
            rootURL: normalizedURL,
            isCloudBacked: normalizedURL.path.contains("Library/Mobile Documents")
        )
        let store = VaultStore(vault: vault)
        await store.loadVault()
        openVaults.append(store)
        activeVault = store
        persistVaultList()
    }

    func presentWorkflowAlert(title: String, message: String) {
        workflowAlert = WorkflowAlert(title: title, message: message)
    }

    func closeVault(_ store: VaultStore) {
        openVaults.removeAll { $0 === store }
        if activeVault === store {
            activeVault = openVaults.first
        }
        persistVaultList()
    }

    // MARK: – Persistence helpers

    private func persistVaultList() {
        let urls = openVaults.map(\.vault.rootURL.path)
        defaults.set(urls, forKey: vaultListKey)
    }

    private func restoreVaults() {
        guard let paths = defaults.stringArray(forKey: vaultListKey) else { return }
        Task {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                await openVault(at: url)
            }
        }
    }
}

// MARK: – Menu commands

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note…") {
                // Post to ContentView which owns the template picker sheet.
                NotificationCenter.default.post(name: .mongrelNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(appState.activeVault == nil)

            Button("Today's Daily Note") {
                appState.createOrOpenDailyNote()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(appState.activeVault == nil)

            Button("Quick Note from Clipboard") {
                appState.createQuickNoteFromClipboard()
            }
            .disabled(appState.activeVault == nil)

            Divider()

            Button("Open Vault…") {
                openVaultPanel()
            }
            .keyboardShortcut("O", modifiers: [.command, .shift])

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .mongrelToggleSidebar, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)
        }
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
