import Testing
@testable import RecallCore

struct HTMLPlainTextTests {
    @Test func stripsTagsAndCollapsesWhitespace() {
        let result = HTMLPlainText.preview(of: "<b>hola</b>   <i>mundo</i>")
        #expect(result == "hola mundo")
    }

    @Test func rendersClozeSpansAsTheirAnswerText() {
        let result = HTMLPlainText.preview(of: "The {{c1::capital}} of France is {{c2::Paris::city}}.")
        #expect(result == "The capital of France is Paris.")
    }

    @Test func truncatesLongTextWithEllipsis() {
        let long = String(repeating: "a", count: 100)
        let result = HTMLPlainText.preview(of: long, maxLength: 10)
        #expect(result == String(repeating: "a", count: 10) + "…")
    }

    @Test func shortTextIsReturnedUnchanged() {
        let result = HTMLPlainText.preview(of: "hola", maxLength: 80)
        #expect(result == "hola")
    }
}
