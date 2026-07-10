import Foundation

/// Strips a field's HTML down to a short plain-text preview for browse-list
/// rows (PRD §7.6) — not a full HTML parser, just enough to hide markup noise
/// (`<b>`, `<img>`, cloze spans) from a one-line summary.
public enum HTMLPlainText {
    public static func preview(of html: String, maxLength: Int = 80) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "\\{\\{c\\d+::(.*?)(?:::.*?)?\\}\\}",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "…"
    }
}
