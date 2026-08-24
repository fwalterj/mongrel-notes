import SwiftUI
import WebKit
import SharedFoundation

/// Renders Markdown as styled HTML in a WKWebView, matching the glass chrome aesthetic.
struct MarkdownPreviewView: NSViewRepresentable {

    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(buildHTML(markdown), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(buildHTML(markdown), baseURL: nil)
    }

    // MARK: – HTML generation

    private func buildHTML(_ markdown: String) -> String {
        let body = markdownToHTML(markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(previewCSS)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Convert Markdown to an HTML body fragment using the `swift-markdown` CommonMark parser.
    /// Handles the full CommonMark spec plus MongrelNotes extensions: `[[wikilinks]]` and `#tags`.
    private func markdownToHTML(_ md: String) -> String {
        MarkdownHTMLConverter.html(from: md)
    }

    // MARK: – CSS

    private var previewCSS: String {
        """
        :root {
          --hue: 222;
          --text: hsl(var(--hue), 10%, 92%);
          --muted: hsl(var(--hue), 10%, 60%);
          --accent: hsl(var(--hue), 85%, 70%);
          --wikilink: hsl(calc(var(--hue) + 30), 80%, 72%);
          --code-bg: hsla(var(--hue), 60%, 15%, 0.5);
          --bg: transparent;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
          font-size: 15px;
          line-height: 1.7;
          color: var(--text);
          background: var(--bg);
          padding: 24px 32px;
          max-width: 740px;
          margin: 0 auto;
        }
        h1 { font-size: 2em; font-weight: 700; color: hsl(var(--hue), 45%, 92%); margin: 0.6em 0 0.3em; }
        h2 { font-size: 1.5em; font-weight: 600; color: hsl(var(--hue), 40%, 88%); margin: 0.8em 0 0.3em; }
        h3 { font-size: 1.2em; font-weight: 500; color: hsl(var(--hue), 35%, 82%); margin: 0.8em 0 0.2em; }
        p { margin: 0.6em 0; }
        a { color: var(--accent); text-decoration: underline; text-decoration-color: hsla(var(--hue), 85%, 70%, 0.4); }
        code {
          font-family: 'SF Mono', Menlo, monospace;
          font-size: 0.88em;
          background: var(--code-bg);
          border: 1px solid hsla(var(--hue), 60%, 60%, 0.2);
          border-radius: 4px;
          padding: 0.1em 0.4em;
          color: hsl(var(--hue), 80%, 80%);
        }
        pre { background: var(--code-bg); border-radius: 8px; padding: 1em; overflow-x: auto; margin: 1em 0; }
        pre code { background: none; border: none; padding: 0; }
        .wikilink {
          color: var(--wikilink);
          border-bottom: 1px dotted hsla(calc(var(--hue)+30), 80%, 72%, 0.5);
          cursor: pointer;
        }
        .tag { color: var(--accent); }
        blockquote {
          border-left: 3px solid hsla(var(--hue), 60%, 60%, 0.4);
          padding-left: 1em;
          color: var(--muted);
          margin: 0.8em 0;
        }
        hr { border: none; border-top: 1px solid hsla(var(--hue), 50%, 60%, 0.2); margin: 1.5em 0; }
        """
    }
}
