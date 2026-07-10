import GRDB
import Foundation

/// The two fixed note types v1 ships (PRD §6, §7.2): Basic and Cloze. Every
/// library needs these to exist before any note can be created, so they're
/// seeded with stable, well-known IDs (rather than random UUIDs) making the
/// seed idempotent and safe to run on every `AppDatabase` launch.
public enum BuiltInNoteTypes {
    public static let basicNoteTypeID = "builtin.noteType.basic"
    public static let basicFrontFieldID = "builtin.field.basic.front"
    public static let basicBackFieldID = "builtin.field.basic.back"
    public static let basicTemplateID = "builtin.template.basic.card1"

    public static let clozeNoteTypeID = "builtin.noteType.cloze"
    public static let clozeTextFieldID = "builtin.field.cloze.text"
    public static let clozeExtraFieldID = "builtin.field.cloze.extra"
    public static let clozeTemplateID = "builtin.template.cloze.card1"

    /// Inserts the Basic and Cloze note types (with their fields and card
    /// templates) if they aren't already present. Safe to call repeatedly.
    public static func seedIfNeeded(in db: Database) throws {
        if try NoteType.fetchOne(db, key: basicNoteTypeID) == nil {
            try NoteType(id: basicNoteTypeID, name: "Basic", kind: .basic).insert(db)
            try Field(id: basicFrontFieldID, noteTypeID: basicNoteTypeID, name: "Front", ordinal: 0).insert(db)
            try Field(id: basicBackFieldID, noteTypeID: basicNoteTypeID, name: "Back", ordinal: 1).insert(db)
            try CardTemplate(
                id: basicTemplateID,
                noteTypeID: basicNoteTypeID,
                name: "Card 1",
                ordinal: 0,
                questionTemplate: "{{Front}}",
                answerTemplate: "{{FrontSide}}<hr id=\"answer\">{{Back}}"
            ).insert(db)
        }

        if try NoteType.fetchOne(db, key: clozeNoteTypeID) == nil {
            try NoteType(id: clozeNoteTypeID, name: "Cloze", kind: .cloze).insert(db)
            try Field(id: clozeTextFieldID, noteTypeID: clozeNoteTypeID, name: "Text", ordinal: 0).insert(db)
            try Field(id: clozeExtraFieldID, noteTypeID: clozeNoteTypeID, name: "Extra", ordinal: 1).insert(db)
            try CardTemplate(
                id: clozeTemplateID,
                noteTypeID: clozeNoteTypeID,
                name: "Cloze",
                ordinal: 0,
                questionTemplate: "{{cloze:Text}}",
                answerTemplate: "{{cloze:Text}}<br>{{Extra}}"
            ).insert(db)
        }
    }
}
