import Foundation

// MARK: – DocxGenerator
// Generates a valid .docx (Office Open XML) from Markdown source
// using only Swift + Foundation + the system `zip` command.
// No third-party dependencies required.
//
// The output targets Word 2016+ / LibreOffice 6+.
// Structure created:
//   [Content_Types].xml
//   _rels/.rels
//   word/document.xml
//   word/styles.xml
//   word/settings.xml
//   word/_rels/document.xml.rels
//   docProps/core.xml
//   docProps/app.xml

enum DocxGenerator {

    // MARK: – Public API

    /// Generate a .docx file at `outputURL` from Markdown `source`.
    /// - Parameters:
    ///   - source: Raw Markdown text
    ///   - title: Note title (used in document properties)
    ///   - outputURL: Destination file path (must end in `.docx`)
    static func generate(from source: String, title: String, outputURL: URL) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mongrel_docx_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tmp) }

        // ── Build directory tree ────────────────────────────────────────
        let wordDir    = tmp.appendingPathComponent("word")
        let relsDir    = tmp.appendingPathComponent("_rels")
        let wordRels   = wordDir.appendingPathComponent("_rels")
        let docProps   = tmp.appendingPathComponent("docProps")
        for dir in [wordDir, relsDir, wordRels, docProps] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let now = ISO8601DateFormatter().string(from: Date())

        // ── Write files ─────────────────────────────────────────────────
        try contentTypes.write(to: tmp.appendingPathComponent("[Content_Types].xml"), encoding: .utf8)
        try rootRels.write(to: relsDir.appendingPathComponent(".rels"), encoding: .utf8)
        try styles.write(to: wordDir.appendingPathComponent("styles.xml"), encoding: .utf8)
        try settings.write(to: wordDir.appendingPathComponent("settings.xml"), encoding: .utf8)
        try documentRels.write(to: wordRels.appendingPathComponent("document.xml.rels"), encoding: .utf8)
        try coreProps(title: title, date: now)
            .write(to: docProps.appendingPathComponent("core.xml"), encoding: .utf8)
        try appProps(title: title)
            .write(to: docProps.appendingPathComponent("app.xml"), encoding: .utf8)
        try buildDocument(from: source)
            .write(to: wordDir.appendingPathComponent("document.xml"), encoding: .utf8)

        // ── Zip into .docx ──────────────────────────────────────────────
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // zip must be run from inside the tmp directory
        let result = Process.runCommand(
            "/usr/bin/zip",
            args: ["-r", outputURL.path, "."],
            environment: ["PWD": tmp.path]
        )
        // Try with chdir approach if direct path fails
        if !result.succeeded {
            // Fallback: use a shell script approach
            let script = "cd \"\(tmp.path)\" && zip -r \"\(outputURL.path)\" ."
            Process.runCommand("/bin/sh", args: ["-c", script])
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw DocxError.zipFailed(result.stderr)
        }
    }

    enum DocxError: LocalizedError {
        case zipFailed(String)
        var errorDescription: String? {
            switch self { case .zipFailed(let msg): return "zip failed: \(msg)" }
        }
    }

    // MARK: – Document body builder

    private static func buildDocument(from markdown: String) -> String {
        let body = parseMarkdownToOOXML(markdown)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document
          xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
          xmlns:cx="http://schemas.microsoft.com/office/drawing/2014/chartex"
          xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
          xmlns:o="urn:schemas-microsoft-com:office:office"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
          xmlns:v="urn:schemas-microsoft-com:vml"
          xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
          xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
          xmlns:w10="urn:schemas-microsoft-com:office:word"
          xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
          xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml"
          xmlns:w16cid="http://schemas.microsoft.com/office/word/2016/wordml/cid"
          xmlns:w16se="http://schemas.microsoft.com/office/word/2015/wordml/symex"
          xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
          xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
          xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
          xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
          mc:Ignorable="w14 w15 w16se w16cid wp14">
          <w:body>
        \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
                       w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    // MARK: – Markdown → OOXML

    private static func parseMarkdownToOOXML(_ md: String) -> String {
        let lines  = md.components(separatedBy: "\n")
        var result = ""
        var i      = 0
        var inCode = false
        var codeLines: [String] = []

        while i < lines.count {
            let line = lines[i]

            // ── Code fence ────────────────────────────────────────────
            if line.hasPrefix("```") {
                if inCode {
                    result += codeBlock(codeLines)
                    codeLines = []
                    inCode    = false
                } else {
                    inCode = true
                }
                i += 1; continue
            }
            if inCode { codeLines.append(line); i += 1; continue }

            // ── Blank line ────────────────────────────────────────────
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1; continue
            }

            // ── Headings ──────────────────────────────────────────────
            if      line.hasPrefix("# ")    { result += heading(String(line.dropFirst(2)),  level: 1) }
            else if line.hasPrefix("## ")   { result += heading(String(line.dropFirst(3)),  level: 2) }
            else if line.hasPrefix("### ")  { result += heading(String(line.dropFirst(4)),  level: 3) }
            else if line.hasPrefix("#### ") { result += heading(String(line.dropFirst(5)),  level: 4) }

            // ── Block quote ───────────────────────────────────────────
            else if line.hasPrefix("> ") {
                result += para(String(line.dropFirst(2)), style: "Quote")
            }

            // ── Unordered list item ───────────────────────────────────
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result += listItem(String(line.dropFirst(2)), ordered: false, num: 1)
            }

            // ── Ordered list item ─────────────────────────────────────
            else if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let content = String(line[match.upperBound...])
                let num = Int(line[line.startIndex..<match.lowerBound]
                    .trimmingCharacters(in: .init(charactersIn: ". "))) ?? 1
                result += listItem(content, ordered: true, num: num)
            }

            // ── HR ────────────────────────────────────────────────────
            else if line == "---" || line == "***" {
                result += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"auto\"/></w:pBdr></w:pPr></w:p>\n"
            }

            // ── Normal paragraph ──────────────────────────────────────
            else {
                result += para(line, style: "Normal")
            }

            i += 1
        }

        if inCode { result += codeBlock(codeLines) }
        return result
    }

    // MARK: – OOXML building blocks

    private static func heading(_ text: String, level: Int) -> String {
        let style = "Heading\(level)"
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr>\(runs(text))</w:p>\n"
    }

    private static func para(_ text: String, style: String = "Normal") -> String {
        let styleTag = style == "Normal" ? "" :
            "<w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr>"
        return "<w:p>\(styleTag)\(runs(text))</w:p>\n"
    }

    private static func listItem(_ text: String, ordered: Bool, num: Int) -> String {
        let numId = ordered ? 2 : 1
        return """
        <w:p>
          <w:pPr>
            <w:pStyle w:val="ListParagraph"/>
            <w:numPr>
              <w:ilvl w:val="0"/>
              <w:numId w:val="\(numId)"/>
            </w:numPr>
          </w:pPr>
          \(runs(text))
        </w:p>\n
        """
    }

    private static func codeBlock(_ lines: [String]) -> String {
        let content = lines.map { xmlEscape($0) }.joined(separator: "&#13;")
        return """
        <w:p>
          <w:pPr><w:pStyle w:val="CodeBlock"/></w:pPr>
          <w:r>
            <w:rPr><w:rStyle w:val="CodeChar"/></w:rPr>
            <w:t xml:space="preserve">\(content)</w:t>
          </w:r>
        </w:p>\n
        """
    }

    /// Convert a Markdown inline span to OOXML run elements.
    private static func runs(_ text: String) -> String {
        // Pattern: **bold**, *italic*, `code`, [[wikilink]], [link](url), plain
        var result = ""
        var s      = text

        // Process each recognised inline pattern
        while !s.isEmpty {
            // Bold
            if let r = s.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let before  = String(s[s.startIndex..<r.lowerBound])
                let content = s[r].dropFirst(2).dropLast(2)
                if !before.isEmpty { result += plainRun(String(before)) }
                result += boldRun(String(content))
                s = String(s[r.upperBound...])
                continue
            }
            // Italic
            if let r = s.range(of: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, options: .regularExpression) {
                let before  = String(s[s.startIndex..<r.lowerBound])
                let content = s[r].dropFirst().dropLast()
                if !before.isEmpty { result += plainRun(String(before)) }
                result += italicRun(String(content))
                s = String(s[r.upperBound...])
                continue
            }
            // Inline code
            if let r = s.range(of: #"`(.+?)`"#, options: .regularExpression) {
                let before  = String(s[s.startIndex..<r.lowerBound])
                let content = s[r].dropFirst().dropLast()
                if !before.isEmpty { result += plainRun(String(before)) }
                result += codeRun(String(content))
                s = String(s[r.upperBound...])
                continue
            }
            // No more patterns — dump remaining as plain text
            result += plainRun(s)
            break
        }
        return result
    }

    private static func plainRun(_ text: String) -> String {
        "<w:r><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }
    private static func boldRun(_ text: String) -> String {
        "<w:r><w:rPr><w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }
    private static func italicRun(_ text: String) -> String {
        "<w:r><w:rPr><w:i/><w:iCs/></w:rPr><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }
    private static func codeRun(_ text: String) -> String {
        "<w:r><w:rPr><w:rStyle w:val=\"CodeChar\"/></w:rPr><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: – Static XML files

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml"  ContentType="application/xml"/>
      <Override PartName="/word/document.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/word/settings.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
      <Override PartName="/docProps/core.xml"
        ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml"
        ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
    </Relationships>
    """

    private static let settings = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:defaultTabStop w:val="720"/>
      <w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>
    </w:settings>
    """

    private static func coreProps(title: String, date: String) -> String {
        let escaped = title.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties
          xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escaped)</dc:title>
          <dc:creator>MongrelNotes</dc:creator>
          <cp:lastModifiedBy>MongrelNotes</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(date)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(date)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func appProps(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
          <Application>MongrelNotes</Application>
          <DocSecurity>0</DocSecurity>
          <ScaleCrop>false</ScaleCrop>
          <LinksUpToDate>false</LinksUpToDate>
          <SharedDoc>false</SharedDoc>
          <HyperlinksChanged>false</HyperlinksChanged>
          <AppVersion>1.0</AppVersion>
        </Properties>
        """
    }

    // Styles: Normal, Heading1-4, CodeBlock, CodeChar, Quote, ListParagraph
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
              xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
      <w:docDefaults>
        <w:rPrDefault><w:rPr>
          <w:rFonts w:ascii="-apple-system" w:hAnsi="-apple-system"/>
          <w:sz w:val="28"/><w:szCs w:val="28"/>
        </w:rPr></w:rPrDefault>
      </w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/>
        <w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading1">
        <w:name w:val="heading 1"/>
        <w:basedOn w:val="Normal"/>
        <w:next w:val="Normal"/>
        <w:pPr><w:outlineLvl w:val="0"/>
          <w:spacing w:before="480" w:after="120"/>
        </w:pPr>
        <w:rPr><w:b/><w:sz w:val="52"/><w:szCs w:val="52"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2">
        <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:outlineLvl w:val="1"/><w:spacing w:before="360" w:after="80"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading3">
        <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:outlineLvl w:val="2"/><w:spacing w:before="240" w:after="60"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading4">
        <w:name w:val="heading 4"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:outlineLvl w:val="3"/><w:spacing w:before="200" w:after="40"/></w:pPr>
        <w:rPr><w:b/><w:i/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Quote">
        <w:name w:val="Quote"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:ind w:left="720"/>
          <w:pBdr><w:left w:val="single" w:sz="6" w:space="9" w:color="AAAAAA"/></w:pBdr>
        </w:pPr>
        <w:rPr><w:i/><w:color w:val="666666"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="CodeBlock">
        <w:name w:val="Code Block"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/>
          <w:ind w:left="360" w:right="360"/>
          <w:spacing w:before="120" w:after="120" w:line="240" w:lineRule="exact"/>
        </w:pPr>
        <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/>
          <w:sz w:val="22"/><w:szCs w:val="22"/><w:color w:val="3A3A3A"/>
        </w:rPr>
      </w:style>
      <w:style w:type="character" w:styleId="CodeChar">
        <w:name w:val="Code Char"/>
        <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/>
          <w:sz w:val="22"/><w:color w:val="3A3A3A"/>
          <w:shd w:val="clear" w:color="auto" w:fill="F0F0F0"/>
        </w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="ListParagraph">
        <w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:ind w:left="720"/></w:pPr>
      </w:style>
    </w:styles>
    """
}

// MARK: – String write helper

private extension String {
    func write(to url: URL, encoding: String.Encoding) throws {
        try write(to: url, atomically: true, encoding: encoding)
    }
}
