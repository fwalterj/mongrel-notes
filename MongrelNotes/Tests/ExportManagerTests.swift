import XCTest
@testable import MongrelNotes
import SharedFoundation

@MainActor
final class ExportManagerTests: XCTestCase {

    func test_exportFormatsUseUniqueExtensions() {
        let extensions = ExportFormat.allCases.map(\.fileExtension)
        XCTAssertEqual(Set(extensions).count, extensions.count)
        XCTAssertFalse(extensions.contains("pages"))
    }

    func test_extractCodeBlocksMatchesExactFenceLanguage() {
        let markdown = """
        ```python
        print("kept")
        ```
        ```pythonish
        print("rejected")
        ```
        ```
        print("unlabelled")
        ```
        """

        let blocks = ExportManager().extractCodeBlocks(from: markdown, language: "python")

        XCTAssertEqual(blocks, ["print(\"kept\")"])
    }

    func test_pythonExportAcceptsPyFence() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MongrelNotes-Export-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let note = Note(
            fileURL: URL(fileURLWithPath: "/tmp/code-note.md"),
            title: "Code Note",
            body: """
            ```py
            print("alias works")
            ```
            """
        )
        let manager = ExportManager()
        let completion = expectation(description: "Python export completed")
        var exportResult: Result<URL, Error>?

        manager.export(note, format: .python, to: outputURL) { result in
            exportResult = result
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 3)

        _ = try exportResult?.get()
        let output = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(output.contains("print(\"alias works\")"))
    }
}
