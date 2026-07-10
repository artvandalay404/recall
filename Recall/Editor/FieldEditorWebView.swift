import SwiftUI
import WebKit

/// Sends formatting/insertion commands to a `FieldEditorWebView`'s live
/// contenteditable document. Handed to the note editor via
/// `onControllerReady` so a single toolbar living outside the per-field web
/// views can act on whichever field currently has focus.
@MainActor
final class FieldEditorController {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func toggleBold() { exec("bold") }
    func toggleItalic() { exec("italic") }
    func toggleUnderline() { exec("underline") }

    func insertHTML(_ html: String) {
        webView?.evaluateJavaScript("rc_insertHTML(\(FieldEditorWebView.jsStringLiteral(html)))")
    }

    /// Wraps the current selection as `prefix<selection>suffix` (e.g. a cloze
    /// deletion's `"{{c3::"` / `"}}"`). A no-op if nothing is selected.
    func wrapSelection(prefix: String, suffix: String) {
        webView?.evaluateJavaScript(
            "rc_wrapSelection(\(FieldEditorWebView.jsStringLiteral(prefix)), \(FieldEditorWebView.jsStringLiteral(suffix)))"
        )
    }

    private func exec(_ command: String) {
        webView?.evaluateJavaScript("rc_exec(\(FieldEditorWebView.jsStringLiteral(command)))")
    }
}

/// A single note field's rich-text editing surface: a `contenteditable` div
/// in a `WKWebView`, mirroring how the field's HTML actually renders during
/// study (PRD §7.5) — bold/italic/underline via `document.execCommand`,
/// cloze-wrapping and media insertion via small JS helpers, bridged back to
/// SwiftUI through a `WKScriptMessageHandler`. Toggling to "HTML source" mode
/// swaps this view out for a plain `TextEditor` on the same bound string
/// rather than trying to keep both in sync live.
struct FieldEditorWebView: UIViewRepresentable {
    let initialHTML: String
    let mediaBaseURL: URL?
    let onChange: @MainActor (String) -> Void
    let onFocus: @MainActor () -> Void
    let onControllerReady: @MainActor (FieldEditorController) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onFocus: onFocus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "fieldChanged")
        configuration.userContentController.add(context.coordinator, name: "fieldFocused")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.pendingInitialHTML = initialHTML
        webView.loadHTMLString(Self.shellHTML, baseURL: mediaBaseURL)

        onControllerReady(FieldEditorController(webView: webView))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Content flows one-way, JS -> Swift, via the coordinator's message
        // handler while this view is on screen. Re-syncing a manually-edited
        // HTML-source string back in happens by recreating this view (its
        // identity changes when the editor toggles out of source mode), not here.
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    /// Encodes `string` as a JS string literal via JSON — a JSON string is
    /// always a valid JS string literal — so field HTML containing quotes,
    /// backticks, or newlines can be safely spliced into `evaluateJavaScript`.
    static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string), let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private static let shellHTML = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    :root { color-scheme: light dark; }
    body {
        font: -apple-system-body;
        font-size: 17px;
        margin: 0;
        padding: 6px 2px;
        color: #000000;
        -webkit-text-size-adjust: 100%;
    }
    @media (prefers-color-scheme: dark) { body { color: #f2f2f7; } }
    #editor { outline: none; min-height: 1.4em; line-height: 1.4; }
    img { max-width: 100%; height: auto; }
    </style>
    </head>
    <body>
    <div id="editor" contenteditable="true" autocapitalize="sentences" autocorrect="on"></div>
    <script>
    const editor = document.getElementById('editor');
    function rc_setContent(html) { editor.innerHTML = html; }
    function rc_notifyChange() { window.webkit.messageHandlers.fieldChanged.postMessage(editor.innerHTML); }
    editor.addEventListener('input', rc_notifyChange);
    editor.addEventListener('focus', () => window.webkit.messageHandlers.fieldFocused.postMessage(true));

    // Toolbar buttons live outside this WKWebView, in native SwiftUI. Tapping
    // one resigns the editor's first responder (the enclosing Form dismisses
    // the keyboard on outside taps), which collapses the DOM selection before
    // the command runs. Track the last selection continuously and restore it
    // on the way back in, so "select text, tap Bold" actually applies to the
    // selected text instead of a collapsed cursor.
    let savedRange = null;
    document.addEventListener('selectionchange', () => {
        const selection = window.getSelection();
        if (selection.rangeCount > 0 && editor.contains(selection.anchorNode)) {
            savedRange = selection.getRangeAt(0).cloneRange();
        }
    });
    function rc_restoreSelection() {
        if (!savedRange) { return; }
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(savedRange);
    }

    // Reclaiming first responder via `editor.focus()` after a native button
    // stole it doesn't take effect synchronously within the same JS turn in
    // WKWebView — running execCommand immediately after is a silent no-op.
    // Deferring one tick lets the responder change land first.
    function rc_afterFocus(fn) {
        editor.focus();
        setTimeout(() => {
            rc_restoreSelection();
            fn();
            rc_notifyChange();
        }, 0);
    }
    function rc_exec(command) {
        rc_afterFocus(() => document.execCommand(command, false, null));
    }
    function rc_insertHTML(html) {
        rc_afterFocus(() => document.execCommand('insertHTML', false, html));
    }
    function rc_wrapSelection(prefix, suffix) {
        rc_afterFocus(() => {
            const selection = window.getSelection();
            if (!selection.rangeCount || selection.isCollapsed) { return; }
            document.execCommand('insertText', false, prefix + selection.toString() + suffix);
        });
    }
    </script>
    </body>
    </html>
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let onChange: @MainActor (String) -> Void
        private let onFocus: @MainActor () -> Void
        weak var webView: WKWebView?
        var pendingInitialHTML = ""

        init(onChange: @escaping @MainActor (String) -> Void, onFocus: @escaping @MainActor () -> Void) {
            self.onChange = onChange
            self.onFocus = onFocus
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("rc_setContent(\(FieldEditorWebView.jsStringLiteral(pendingInitialHTML)))")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated {
                switch message.name {
                case "fieldChanged":
                    if let html = message.body as? String { onChange(html) }
                case "fieldFocused":
                    onFocus()
                default:
                    break
                }
            }
        }
    }
}
