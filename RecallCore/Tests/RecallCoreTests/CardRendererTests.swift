import Testing
import Foundation
@testable import RecallCore

struct CardRendererTests {
    private func basicFields() -> [Field] {
        [
            Field(noteTypeID: "nt", name: "Front", ordinal: 0),
            Field(noteTypeID: "nt", name: "Back", ordinal: 1),
        ]
    }

    private func basicTemplate() -> CardTemplate {
        CardTemplate(
            noteTypeID: "nt",
            name: "Card 1",
            ordinal: 0,
            questionTemplate: "{{Front}}",
            answerTemplate: "{{FrontSide}}<hr id=\"answer\">{{Back}}"
        )
    }

    @Test func basicTemplateSubstitutesFrontAndBack() throws {
        let note = Note(noteTypeID: "nt", fieldValues: ["¿Qué hora es?", "What time is it?"])
        let (question, answer) = try CardRenderer.render(note: note, fields: basicFields(), template: basicTemplate(), clozeOrdinal: 0)

        #expect(question.contains("¿Qué hora es?"))
        #expect(!question.contains("What time is it?"))
        #expect(answer.contains("¿Qué hora es?"))
        #expect(answer.contains("What time is it?"))
    }

    @Test func missingFieldSubstitutesEmptyString() throws {
        let template = CardTemplate(noteTypeID: "nt", name: "Card 1", ordinal: 0, questionTemplate: "{{Front}} {{Nonexistent}}", answerTemplate: "{{Back}}")
        let note = Note(noteTypeID: "nt", fieldValues: ["hola", "hello"])
        let (question, _) = try CardRenderer.render(note: note, fields: basicFields(), template: template, clozeOrdinal: 0)

        #expect(question.contains("hola"))
        #expect(!question.contains("Nonexistent"))
    }

    @Test func fieldCountMismatchThrows() {
        let note = Note(noteTypeID: "nt", fieldValues: ["only one"])
        #expect(throws: CardRenderer.RenderError.fieldCountMismatch(expected: 2, actual: 1)) {
            _ = try CardRenderer.render(note: note, fields: basicFields(), template: basicTemplate(), clozeOrdinal: 0)
        }
    }

    // MARK: - Cloze

    private func clozeFields() -> [Field] {
        [
            Field(noteTypeID: "nt-cloze", name: "Text", ordinal: 0),
            Field(noteTypeID: "nt-cloze", name: "Extra", ordinal: 1),
        ]
    }

    private func clozeTemplate() -> CardTemplate {
        CardTemplate(
            noteTypeID: "nt-cloze",
            name: "Cloze",
            ordinal: 0,
            questionTemplate: "{{cloze:Text}}",
            answerTemplate: "{{cloze:Text}}<br>{{Extra}}"
        )
    }

    @Test func clozeNumbersFindsDistinctOrdinals() {
        #expect(CardRenderer.clozeNumbers(in: "The {{c1::capital}} of France is {{c2::Paris}}.") == [1, 2])
        #expect(CardRenderer.clozeNumbers(in: "No clozes here") == [])
        #expect(CardRenderer.clozeNumbers(in: "{{c1::a}} and {{c1::b}} share ordinal 1") == [1])
    }

    @Test func clozeQuestionMasksActiveDeletionAndRevealsOthers() throws {
        let note = Note(noteTypeID: "nt-cloze", fieldValues: ["The {{c1::capital}} of France is {{c2::Paris}}.", ""])
        let (question, _) = try CardRenderer.render(note: note, fields: clozeFields(), template: clozeTemplate(), clozeOrdinal: 0)

        #expect(question.contains("[...]"))
        #expect(!question.contains("capital"))
        #expect(question.contains("Paris"))
    }

    @Test func clozeAnswerRevealsActiveDeletionHighlighted() throws {
        let note = Note(noteTypeID: "nt-cloze", fieldValues: ["The {{c1::capital}} of France is {{c2::Paris}}.", "Extra note"])
        let (_, answer) = try CardRenderer.render(note: note, fields: clozeFields(), template: clozeTemplate(), clozeOrdinal: 0)

        #expect(answer.contains("<span class=\"cloze\">capital</span>"))
        #expect(answer.contains("Paris"))
        #expect(answer.contains("Extra note"))
    }

    @Test func clozeHintIsShownInMaskWhenPresent() throws {
        let note = Note(noteTypeID: "nt-cloze", fieldValues: ["{{c1::Paris::city}} is the capital.", ""])
        let (question, _) = try CardRenderer.render(note: note, fields: clozeFields(), template: clozeTemplate(), clozeOrdinal: 0)

        #expect(question.contains("[city]"))
        #expect(!question.contains("Paris"))
    }

    @Test func secondClozeOrdinalMasksSecondDeletion() throws {
        let note = Note(noteTypeID: "nt-cloze", fieldValues: ["The {{c1::capital}} of France is {{c2::Paris}}.", ""])
        let (question, _) = try CardRenderer.render(note: note, fields: clozeFields(), template: clozeTemplate(), clozeOrdinal: 1)

        #expect(question.contains("capital"))
        #expect(question.contains("[...]"))
        #expect(!question.contains("Paris"))
    }
}
