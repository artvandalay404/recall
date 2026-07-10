import Foundation

/// Turns a `Note`'s field values and a `CardTemplate`'s HTML into the
/// question/answer HTML pair rendered client-side in a WKWebView (PRD §7.4).
///
/// Supports the two fixed note-type kinds v1 ships: plain `{{Field}}` /
/// `{{FrontSide}}` substitution for Basic-style templates, and
/// `{{cloze:Field}}` masking/reveal for Cloze templates.
public enum CardRenderer {
    public enum RenderError: Error, Equatable {
        case fieldCountMismatch(expected: Int, actual: Int)
    }

    /// - Parameter clozeOrdinal: the card's `templateOrdinal`, which for Cloze
    ///   note types is the zero-based cloze number this card reveals
    ///   (`{{c1::...}}` ↔ ordinal 0).
    public static func render(
        note: Note,
        fields: [Field],
        template: CardTemplate,
        clozeOrdinal: Int
    ) throws -> (question: String, answer: String) {
        guard note.fieldValues.count == fields.count else {
            throw RenderError.fieldCountMismatch(expected: fields.count, actual: note.fieldValues.count)
        }

        var values: [String: String] = [:]
        for field in fields {
            values[field.name] = note.fieldValues[field.ordinal]
        }

        let isCloze = template.questionTemplate.contains("{{cloze:") || template.answerTemplate.contains("{{cloze:")

        let questionBody: String
        let answerBody: String
        if isCloze {
            questionBody = substituteCloze(template.questionTemplate, values: values, activeNumber: clozeOrdinal + 1, revealActiveCloze: false)
            answerBody = substituteCloze(template.answerTemplate, values: values, activeNumber: clozeOrdinal + 1, revealActiveCloze: true)
        } else {
            questionBody = substituteFields(template.questionTemplate, values: values)
            answerBody = substituteFields(template.answerTemplate, values: values, frontSide: questionBody)
        }

        return (wrap(questionBody, css: template.css), wrap(answerBody, css: template.css))
    }

    /// The distinct 1-based cloze numbers referenced in `text` (e.g.
    /// `{{c1::x}} {{c2::y}}` → `[1, 2]`), used to determine how many cards a
    /// Cloze note generates.
    public static func clozeNumbers(in text: String) -> [Int] {
        var numbers = Set<Int>()
        for match in clozeSpanRegex.matches(in: text, range: fullRange(of: text)) {
            if let numberString = substring(text, match, group: 1), let number = Int(numberString) {
                numbers.insert(number)
            }
        }
        return numbers.sorted()
    }

    // MARK: - Regexes

    /// `{{FieldName}}` or `{{FrontSide}}` — a plain token substitution.
    private static let fieldTokenRegex = try! NSRegularExpression(pattern: "\\{\\{([^{}:]+)\\}\\}")
    /// `{{cloze:FieldName}}` — marks where a cloze field's masked/revealed text goes.
    private static let clozeFieldTokenRegex = try! NSRegularExpression(pattern: "\\{\\{cloze:([^{}]+)\\}\\}")
    /// `{{cN::answer}}` or `{{cN::answer::hint}}` inside a cloze field's raw value.
    private static let clozeSpanRegex = try! NSRegularExpression(
        pattern: "\\{\\{c(\\d+)::(.*?)(?:::(.*?))?\\}\\}",
        options: [.dotMatchesLineSeparators]
    )

    // MARK: - Plain field substitution

    private static func substituteFields(_ template: String, values: [String: String], frontSide: String? = nil) -> String {
        var result = ""
        var lastEnd = template.startIndex

        for match in fieldTokenRegex.matches(in: template, range: fullRange(of: template)) {
            guard let matchRange = Range(match.range, in: template), let name = substring(template, match, group: 1) else { continue }
            result += template[lastEnd..<matchRange.lowerBound]
            result += name == "FrontSide" ? (frontSide ?? "") : (values[name] ?? "")
            lastEnd = matchRange.upperBound
        }
        result += template[lastEnd...]
        return result
    }

    // MARK: - Cloze substitution

    private static func substituteCloze(_ template: String, values: [String: String], activeNumber: Int, revealActiveCloze: Bool) -> String {
        var result = ""
        var lastEnd = template.startIndex

        for match in clozeFieldTokenRegex.matches(in: template, range: fullRange(of: template)) {
            guard let matchRange = Range(match.range, in: template), let fieldName = substring(template, match, group: 1) else { continue }
            result += template[lastEnd..<matchRange.lowerBound]
            let raw = values[fieldName] ?? ""
            result += renderClozeSpans(raw, activeNumber: activeNumber, revealActive: revealActiveCloze)
            lastEnd = matchRange.upperBound
        }
        result += template[lastEnd...]

        // Any remaining plain fields (e.g. Cloze's "Extra" field) in the same template.
        return substituteFields(result, values: values)
    }

    private static func renderClozeSpans(_ text: String, activeNumber: Int, revealActive: Bool) -> String {
        var result = ""
        var lastEnd = text.startIndex

        for match in clozeSpanRegex.matches(in: text, range: fullRange(of: text)) {
            guard let matchRange = Range(match.range, in: text),
                  let numberString = substring(text, match, group: 1),
                  let number = Int(numberString),
                  let answer = substring(text, match, group: 2) else { continue }
            let hint = substring(text, match, group: 3)

            result += text[lastEnd..<matchRange.lowerBound]
            if number != activeNumber {
                result += answer
            } else if revealActive {
                result += "<span class=\"cloze\">\(answer)</span>"
            } else {
                result += "<span class=\"cloze\">[\(hint ?? "...")]</span>"
            }
            lastEnd = matchRange.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    // MARK: - NSRegularExpression helpers

    private static func fullRange(of text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }

    private static func substring(_ text: String, _ match: NSTextCheckingResult, group: Int) -> String? {
        guard group < match.numberOfRanges, match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - HTML document wrapping

    private static let baseCSS = """
    :root { color-scheme: light dark; }
    body {
        font: -apple-system-body;
        font-size: 22px;
        line-height: 1.4;
        margin: 0;
        padding: 24px;
        text-align: center;
        color: #000000;
        background: #ffffff;
    }
    @media (prefers-color-scheme: dark) {
        body { color: #f2f2f7; background: #1c1c1e; }
    }
    .cloze { font-weight: 600; color: #4f8cff; }
    img { max-width: 100%; height: auto; }
    """

    private static func wrap(_ body: String, css: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(baseCSS)
        \(css)</style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
