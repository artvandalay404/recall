import Testing
import Foundation
import GRDB
@testable import RecallCore

struct SchemaTests {
    @Test func migratorCreatesExpectedTables() throws {
        let db = try AppDatabase.inMemory()
        let tables = try db.dbWriter.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")
        }
        #expect(tables == [
            "library", "deck", "noteType", "field", "cardTemplate", "note", "card", "reviewLog",
            "pendingSyncChange", "syncRecordCache", "mediaAsset",
        ])
    }

    @Test func fullHierarchyRoundTripsThroughTheDatabase() throws {
        let db = try AppDatabase.inMemory()
        let noteType = NoteType(name: "Basic", kind: .basic)

        try db.dbWriter.write { db in
            let deck = Deck(name: "Spanish")
            try deck.insert(db)

            try noteType.insert(db)

            let front = Field(noteTypeID: noteType.id, name: "Front", ordinal: 0)
            try front.insert(db)
            let back = Field(noteTypeID: noteType.id, name: "Back", ordinal: 1)
            try back.insert(db)

            let template = CardTemplate(
                noteTypeID: noteType.id,
                name: "Card 1",
                ordinal: 0,
                questionTemplate: "{{Front}}",
                answerTemplate: "{{FrontSide}}<hr>{{Back}}"
            )
            try template.insert(db)

            let note = Note(noteTypeID: noteType.id, fieldValues: ["hola", "hello"], tags: ["language::spanish"])
            try note.insert(db)

            var card = Card(noteID: note.id, deckID: deck.id, templateOrdinal: 0)
            try card.insert(db)

            let (reviewedCard, log) = FSRSScheduler().review(card: card, rating: .good, reviewDate: Date())
            try log.insert(db)
            card = reviewedCard
            try card.update(db)
        }

        try db.dbWriter.read { db in
            let fetchedCard = try Card.fetchOne(db)
            #expect(fetchedCard?.state == .learning)

            let logCount = try ReviewLog.fetchCount(db)
            #expect(logCount == 1)

            let noteCount = try Note.fetchCount(db)
            #expect(noteCount == 1)

            let fieldCount = try Field.filter(Column("noteTypeID") == noteType.id).fetchCount(db)
            #expect(fieldCount == 2)
        }
    }

    @Test func deletingNoteCascadesToItsCards() throws {
        let db = try AppDatabase.inMemory()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck")
            try deck.insert(db)

            let noteType = NoteType(name: "Basic", kind: .basic)
            try noteType.insert(db)

            let note = Note(noteTypeID: noteType.id, fieldValues: ["a", "b"])
            try note.insert(db)

            let card = Card(noteID: note.id, deckID: deck.id, templateOrdinal: 0)
            try card.insert(db)

            try note.delete(db)
        }

        let remainingCards = try db.dbWriter.read { db in try Card.fetchCount(db) }
        #expect(remainingCards == 0)
    }

    @Test func deckSubdeckCascadesOnParentDeletion() throws {
        let db = try AppDatabase.inMemory()

        try db.dbWriter.write { db in
            let parent = Deck(name: "Parent")
            try parent.insert(db)

            let child = Deck(parentID: parent.id, name: "Child")
            try child.insert(db)

            try parent.delete(db)
        }

        let remainingDecks = try db.dbWriter.read { db in try Deck.fetchCount(db) }
        #expect(remainingDecks == 0)
    }
}
