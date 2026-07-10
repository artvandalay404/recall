import Foundation

/// Minimal note/card creation against the built-in Basic and Cloze note
/// types. This is intentionally narrow — a full field-based editor with rich
/// text, cloze helper UI, and media insertion is phase 3 (PRD §7.5); this
/// exists so decks can hold real content before that editor lands.
public extension AppDatabase {
    @discardableResult
    func addBasicNote(deckID: String, front: String, back: String, due: Date = Date()) throws -> Note {
        try dbWriter.write { db in
            let note = Note(noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: [front, back])
            try note.insert(db)
            let card = Card(noteID: note.id, deckID: deckID, templateOrdinal: 0, due: due)
            try card.insert(db)
            return note
        }
    }

    /// Inserts a Cloze note and one card per distinct `{{cN::...}}` deletion found in `text`.
    @discardableResult
    func addClozeNote(deckID: String, text: String, extra: String = "", due: Date = Date()) throws -> Note {
        try dbWriter.write { db in
            let note = Note(noteTypeID: BuiltInNoteTypes.clozeNoteTypeID, fieldValues: [text, extra])
            try note.insert(db)
            for number in CardRenderer.clozeNumbers(in: text) {
                let card = Card(noteID: note.id, deckID: deckID, templateOrdinal: number - 1, due: due)
                try card.insert(db)
            }
            return note
        }
    }
}
