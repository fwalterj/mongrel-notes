import Foundation
import SharedFoundation

// MARK: – Data model

/// A note template — either a built-in or a user-supplied `.md` file from `_templates/`.
struct NoteTemplate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let body: String      // raw Markdown body (may contain {{variables}})
    let icon: String      // SF Symbol name
    let isBuiltIn: Bool

    /// Substitutes `{{title}}`, `{{date}}`, `{{date-iso}}`, `{{time}}` in the body.
    func instantiate(title: String, date: Date = .now) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        let longDate = df.string(from: date)

        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        let time = tf.string(from: date)

        let iso = ISO8601DateFormatter.dailyNoteFormatter.string(from: date)

        return body
            .replacingOccurrences(of: "{{title}}", with: title)
            .replacingOccurrences(of: "{{date}}", with: longDate)
            .replacingOccurrences(of: "{{date-iso}}", with: iso)
            .replacingOccurrences(of: "{{time}}", with: time)
    }
}

// MARK: – Built-in templates

extension NoteTemplate {

    static let blank = NoteTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Blank",
        body: "# {{title}}\n\n",
        icon: "doc.text",
        isBuiltIn: true
    )

    static let builtIns: [NoteTemplate] = [
        blank,
        NoteTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Meeting Notes",
            body: """
            # {{title}}

            **Date:** {{date}}
            **Attendees:**

            ---

            ## Agenda
            -

            ## Discussion


            ## Decisions


            ## Action Items
            - [ ]

            """,
            icon: "person.2",
            isBuiltIn: true
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Project Plan",
            body: """
            # {{title}}

            **Started:** {{date}}

            ## Goal


            ## Context


            ## In Scope
            -

            ## Out of Scope
            -

            ## Milestones
            | Milestone | Target |
            |-----------|--------|
            |           |        |

            ## Risks
            -

            ## Resources
            -

            """,
            icon: "chart.bar.doc.horizontal",
            isBuiltIn: true
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Reading Notes",
            body: """
            # {{title}}

            **Source:**
            **Author:**
            **Date Read:** {{date}}

            ---

            ## Summary


            ## Key Ideas
            -

            ## Quotes
            >

            ## Takeaways
            -

            ## Links
            -

            """,
            icon: "book",
            isBuiltIn: true
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Retrospective",
            body: """
            # {{title}}

            **Date:** {{date}}

            ---

            ## What Went Well
            -

            ## What To Improve
            -

            ## Action Items
            - [ ]

            ## Shout-outs
            -

            """,
            icon: "arrow.clockwise",
            isBuiltIn: true
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "Standup",
            body: """
            # {{title}} – {{date}}

            ## Yesterday
            -

            ## Today
            -

            ## Blockers
            -

            """,
            icon: "person.wave.2",
            isBuiltIn: true
        ),
    ]
}

// MARK: – Template store

/// Loads custom templates from `{vaultRoot}/_templates/*.md` and merges them
/// with the built-in set. User templates override built-ins of the same name.
@MainActor
final class TemplateStore: ObservableObject {

    @Published private(set) var templates: [NoteTemplate] = NoteTemplate.builtIns

    private let templatesDir: URL

    init(vaultURL: URL) {
        self.templatesDir = vaultURL.appendingPathComponent("_templates")
        Task { await reload() }
    }

    // MARK: – Loading

    func reload() async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: templatesDir.path) else {
            templates = NoteTemplate.builtIns
            return
        }
        var loaded: [NoteTemplate] = []
        do {
            let files = try fm.contentsOfDirectory(
                at: templatesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for file in files where file.pathExtension == "md" {
                let name = file.deletingPathExtension().lastPathComponent
                let body = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let template = NoteTemplate(
                    id: deterministicID(for: file),
                    name: name,
                    body: body,
                    icon: "doc.badge.plus",
                    isBuiltIn: false
                )
                loaded.append(template)
            }
        } catch {
            print("[TemplateStore] Failed to read templates: \(error)")
        }
        // User-supplied templates shadow built-ins of the same name.
        var merged = NoteTemplate.builtIns.filter { bi in
            !loaded.contains(where: { $0.name.lowercased() == bi.name.lowercased() })
        }
        merged += loaded.sorted { $0.name < $1.name }
        templates = merged
    }

    // MARK: – Creation helper

    /// Scaffold the `_templates/` directory and write all built-in templates as
    /// `.md` files so the user can edit or extend them.
    func scaffoldBuiltIns() {
        let fm = FileManager.default
        try? fm.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        for template in NoteTemplate.builtIns where template != .blank {
            let dest = templatesDir.appendingPathComponent("\(template.name).md")
            if !fm.fileExists(atPath: dest.path) {
                try? template.body.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: – Helpers

    private func deterministicID(for url: URL) -> UUID {
        // Build a stable UUID from the last path component so reloads
        // don't regenerate the identity each time.
        let seed = url.lastPathComponent
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, char) in seed.utf8.enumerated() {
            bytes[i % 16] ^= char
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant 1
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
