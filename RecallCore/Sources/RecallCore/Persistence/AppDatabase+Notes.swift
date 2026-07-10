import GRDB
import Foundation

/// Errors surfaced by note creation/editing that a note-editor UI should
/// present to the user, rather than a raw database failure.
public enum NoteEditingError: Error, Equatable {
    /// The note's fields, as currently filled in, don't generate any cards —
    /// e.g. a Cloze note with no `{{cN::...}}` deletion in its Text field.
    case noCardsGenerated
    case unknownNoteType(String)
}

extension NoteEditingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noCardsGenerated:
            return "This note doesn't produce any cards yet. For Cloze notes, select some text and tap the cloze button."
        case .unknownNoteType(let id):
            return "Unknown note type (\(id))."
        }
    }
}

/// Note creation, editing, deletion, and light browse/search (PRD §7.2, §7.5,
/// §7.6). Card generation is driven by the note type's kind: Basic-style note
/// types generate one card per `CardTemplate` row; Cloze note types generate
/// one card per distinct `{{cN::...}}` deletion found in the note's first
/// field (its "Text" field, by the built-in Cloze note type's convention).
public extension AppDatabase {
    struct NoteSummary: Identifiable, Equatable, Sendable {
        public let note: Note
        public let noteTypeName: String
        public let deckName: String
        public let cardCount: Int
        public var id: String { note.id }
    }

    // MARK: - Note types & fields

    func allNoteTypes() throws -> [NoteType] {
        try dbWriter.read { db in try NoteType.order(Column("name")).fetchAll(db) }
    }

    func noteType(id: String) throws -> NoteType? {
        try dbWriter.read { db in try NoteType.fetchOne(db, key: id) }
    }

    func fields(forNoteType noteTypeID: String) throws -> [Field] {
        try dbWriter.read { db in
            try Field.filter(Field.Columns.noteTypeID == noteTypeID).order(Field.Columns.ordinal).fetchAll(db)
        }
    }

    // MARK: - Create / update / delete

    @discardableResult
    func createNote(deckID: String, noteTypeID: String, fieldValues: [String], tags: [String] = [], due: Date = Date()) throws -> Note {
        try dbWriter.write { db in
            guard let noteType = try NoteType.fetchOne(db, key: noteTypeID) else {
                throw NoteEditingError.unknownNoteType(noteTypeID)
            }
            let ordinals = try Self.cardOrdinals(for: noteType, fieldValues: fieldValues, in: db)
            guard !ordinals.isEmpty else { throw NoteEditingError.noCardsGenerated }

            let note = Note(noteTypeID: noteTypeID, fieldValues: fieldValues, tags: tags)
            try note.insert(db)
            for ordinal in ordinals {
                try Card(noteID: note.id, deckID: deckID, templateOrdinal: ordinal, due: due).insert(db)
            }
            return note
        }
    }

    /// Updates a note's fields/tags in place, then reconciles its generated
    /// cards against the new field values: a Cloze note gains a fresh card
    /// for any newly-added `{{cN::...}}` deletion, and loses the card (and
    /// its review history) for any deletion removed from the text.
    @discardableResult
    func updateNote(_ note: Note, fieldValues: [String], tags: [String]) throws -> Note {
        try dbWriter.write { db in
            guard let noteType = try NoteType.fetchOne(db, key: note.noteTypeID) else {
                throw NoteEditingError.unknownNoteType(note.noteTypeID)
            }
            let desiredOrdinals = Set(try Self.cardOrdinals(for: noteType, fieldValues: fieldValues, in: db))
            guard !desiredOrdinals.isEmpty else { throw NoteEditingError.noCardsGenerated }

            var updated = note
            updated.fieldValues = fieldValues
            updated.tags = tags
            updated.updatedAt = Date()
            try updated.update(db)

            let existingCards = try Card.filter(Card.Columns.noteID == note.id).fetchAll(db)
            let existingOrdinals = Set(existingCards.map(\.templateOrdinal))

            if let deckID = existingCards.first?.deckID {
                for ordinal in desiredOrdinals.subtracting(existingOrdinals) {
                    try Card(noteID: note.id, deckID: deckID, templateOrdinal: ordinal).insert(db)
                }
            }
            for card in existingCards where !desiredOrdinals.contains(card.templateOrdinal) {
                try card.delete(db)
            }

            return updated
        }
    }

    func deleteNote(_ note: Note) throws {
        _ = try dbWriter.write { db in try note.delete(db) }
    }

    // MARK: - Browse / search

    /// A "light" (PRD §7.6) in-memory filtered scan across all notes — v1
    /// scope is a searchable list, not a full advanced query browser, so this
    /// favors simplicity over indexing.
    func searchNotes(query: String = "", deckID: String? = nil) throws -> [NoteSummary] {
        try dbWriter.read { db in
            let noteTypesByID = Dictionary(uniqueKeysWithValues: try NoteType.fetchAll(db).map { ($0.id, $0) })
            let decksByID = Dictionary(uniqueKeysWithValues: try Deck.fetchAll(db).map { ($0.id, $0) })
            let cardsByNoteID = Dictionary(grouping: try Card.fetchAll(db), by: \.noteID)

            var noteIDsInDeck: Set<String>?
            if let deckID {
                let deckIDs = Set(try StudyQueueService.descendantDeckIDs(of: deckID, in: db))
                noteIDsInDeck = Set(
                    cardsByNoteID.values.flatMap { $0 }
                        .filter { deckIDs.contains($0.deckID) }
                        .map(\.noteID)
                )
            }

            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            return try Note.order(Column("updatedAt").desc).fetchAll(db).compactMap { note -> NoteSummary? in
                if let noteIDsInDeck, !noteIDsInDeck.contains(note.id) { return nil }
                if !trimmedQuery.isEmpty {
                    let haystack = (note.fieldValues.joined(separator: " ") + " " + note.tags.joined(separator: " ")).lowercased()
                    guard haystack.contains(trimmedQuery) else { return nil }
                }
                let cards = cardsByNoteID[note.id] ?? []
                return NoteSummary(
                    note: note,
                    noteTypeName: noteTypesByID[note.noteTypeID]?.name ?? "Unknown",
                    deckName: cards.first.flatMap { decksByID[$0.deckID]?.name } ?? "—",
                    cardCount: cards.count
                )
            }
        }
    }

    // MARK: - Card generation

    /// Which `Card.templateOrdinal` values a note with these field values
    /// should have, given its note type. Basic-style note types (fixed
    /// `CardTemplate` set) always generate one card per template; Cloze note
    /// types generate one card per distinct `{{cN::...}}` deletion in the
    /// first field.
    private static func cardOrdinals(for noteType: NoteType, fieldValues: [String], in db: Database) throws -> [Int] {
        switch noteType.kind {
        case .cloze:
            return CardRenderer.clozeNumbers(in: fieldValues.first ?? "").map { $0 - 1 }
        case .basic:
            return try CardTemplate.filter(Column("noteTypeID") == noteType.id).fetchAll(db).map(\.ordinal)
        }
    }

    // MARK: - Legacy narrow helpers (demo seeding, tests)

    @discardableResult
    func addBasicNote(deckID: String, front: String, back: String, due: Date = Date()) throws -> Note {
        try createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: [front, back], due: due)
    }

    /// Inserts a Cloze note and one card per distinct `{{cN::...}}` deletion found in `text`.
    @discardableResult
    func addClozeNote(deckID: String, text: String, extra: String = "", due: Date = Date()) throws -> Note {
        try createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.clozeNoteTypeID, fieldValues: [text, extra], due: due)
    }
}
