import SwiftUI
import WebKit

/// Renders a card's question/answer HTML (PRD §7.4). Reused across cards in a
/// session — `updateUIView` just reloads the HTML string rather than
/// recreating the `WKWebView`, since spinning up a fresh web view per card
/// would reintroduce the flip-latency the PRD calls out as a risk.
struct CardWebView: UIViewRepresentable {
    let html: String
    var baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}
