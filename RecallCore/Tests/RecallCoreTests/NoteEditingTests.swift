import Testing
import Foundation
import GRDB
@testable import RecallCore

struct NoteEditingTests {
    private func makeDeck(_ db: AppDatabase) throws -> String {
        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            return deck.id
        }
    }

    // MARK: - Create

    @Test func creatingABasicNoteGeneratesOneCard() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)

        let note = try db.createNote(
            deckID: deckID,
            noteTypeID: BuiltInNoteTypes.basicNoteTypeID,
            fieldValues: ["front", "back"]
        )

        let cards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        #expect(cards.count == 1)
        #expect(cards[0].templateOrdinal == 0)
        #expect(cards[0].deckID == deckID)
    }

    @Test func creatingAClozeNoteGeneratesOneCardPerDeletion() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)

        let note = try db.createNote(
            deckID: deckID,
            noteTypeID: BuiltInNoteTypes.clozeNoteTypeID,
            fieldValues: ["{{c1::Madrid}} and {{c2::Paris}}", ""]
        )

        let cards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        #expect(Set(cards.map(\.templateOrdinal)) == [0, 1])
    }

    @Test func creatingAClozeNoteWithNoDeletionsThrows() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)

        #expect(throws: NoteEditingError.noCardsGenerated) {
            _ = try db.createNote(
                deckID: deckID,
                noteTypeID: BuiltInNoteTypes.clozeNoteTypeID,
                fieldValues: ["no deletions here", ""]
            )
        }

        let noteCount = try db.dbWriter.read { db in try Note.fetchCount(db) }
        #expect(noteCount == 0)
    }

    @Test func creatingWithUnknownNoteTypeThrows() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)

        #expect(throws: NoteEditingError.unknownNoteType("nope")) {
            _ = try db.createNote(deckID: deckID, noteTypeID: "nope", fieldValues: ["a", "b"])
        }
    }

    // MARK: - Update

    @Test func updatingABasicNoteChangesFieldsWithoutTouchingCards() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"])

        let updated = try db.updateNote(note, fieldValues: ["new front", "new back"], tags: ["tag1"])

        #expect(updated.fieldValues == ["new front", "new back"])
        #expect(updated.tags == ["tag1"])
        let cards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        #expect(cards.count == 1)
    }

    @Test func addingAClozeDeletionOnUpdateAddsANewCard() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(
            deckID: deckID,
            noteTypeID: BuiltInNoteTypes.clozeNoteTypeID,
            fieldValues: ["{{c1::Madrid}}", ""]
        )

        _ = try db.updateNote(note, fieldValues: ["{{c1::Madrid}} and {{c2::Paris}}", ""], tags: [])

        let cards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        #expect(Set(cards.map(\.templateOrdinal)) == [0, 1])
        #expect(cards.allSatisfy { $0.deckID == deckID })
    }

    @Test func removingAClozeDeletionOnUpdateDeletesItsCardAndReviewLog() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(
            deckID: deckID,
            noteTypeID: BuiltInNoteTypes.clozeNoteTypeID,
            fieldValues: ["{{c1::Madrid}} and {{c2::Paris}}", ""]
        )
        let cardToRemove = try db.dbWriter.read { db in
            try Card.filter(Card.Columns.noteID == note.id).filter(Card.Columns.state == CardState.new).order(Column("templateOrdinal")).fetchAll(db)
        }.first { $0.templateOrdinal == 1 }!

        try db.dbWriter.write { db in
            let log = ReviewLog(cardID: cardToRemove.id, rating: .good, reviewedAt: Date())
            try log.insert(db)
        }

        _ = try db.updateNote(note, fieldValues: ["{{c1::Madrid}} and Paris", ""], tags: [])

        let remainingCards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        #expect(remainingCards.map(\.templateOrdinal) == [0])

        let remainingLogs = try db.dbWriter.read { db in try ReviewLog.filter(Column("cardID") == cardToRemove.id).fetchCount(db) }
        #expect(remainingLogs == 0)
    }

    @Test func updatingPreservesSchedulingStateOfCardsThatStillExist() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"])
        let originalCard = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchOne(db)! }

        try db.dbWriter.write { db in
            var card = originalCard
            card.state = .review
            card.stability = 5.0
            try card.update(db)
        }

        _ = try db.updateNote(note, fieldValues: ["edited front", "back"], tags: [])

        let cardAfter = try db.dbWriter.read { db in try Card.fetchOne(db, key: originalCard.id)! }
        #expect(cardAfter.state == .review)
        #expect(cardAfter.stability == 5.0)
    }

    @Test func updatingToRemoveAllDeletionsThrowsAndLeavesNoteUnchanged() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.clozeNoteTypeID, fieldValues: ["{{c1::Madrid}}", ""])

        #expect(throws: NoteEditingError.noCardsGenerated) {
            _ = try db.updateNote(note, fieldValues: ["no deletions", ""], tags: [])
        }

        let reloaded = try db.dbWriter.read { db in try Note.fetchOne(db, key: note.id)! }
        #expect(reloaded.fieldValues == ["{{c1::Madrid}}", ""])
        let cards = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchCount(db) }
        #expect(cards == 1)
    }

    // MARK: - Delete

    @Test func deletingANoteCascadesToItsCardsAndReviewLogs() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        let note = try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"])
        let card = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchOne(db)! }
        try db.dbWriter.write { db in try ReviewLog(cardID: card.id, rating: .good, reviewedAt: Date()).insert(db) }

        try db.deleteNote(note)

        #expect(try db.dbWriter.read { db in try Note.fetchCount(db) } == 0)
        #expect(try db.dbWriter.read { db in try Card.fetchCount(db) } == 0)
        #expect(try db.dbWriter.read { db in try ReviewLog.fetchCount(db) } == 0)
    }

    // MARK: - Search / browse

    @Test func searchNotesFiltersByFieldTextCaseInsensitively() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        try db.addBasicNote(deckID: deckID, front: "hola", back: "hello")
        try db.addBasicNote(deckID: deckID, front: "adiós", back: "goodbye")

        let results = try db.searchNotes(query: "HELLO")
        #expect(results.count == 1)
        #expect(results[0].note.fieldValues == ["hola", "hello"])
    }

    @Test func searchNotesFiltersByTag() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["a", "b"], tags: ["verbs"])
        try db.createNote(deckID: deckID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["c", "d"], tags: ["nouns"])

        let results = try db.searchNotes(query: "verbs")
        #expect(results.count == 1)
        #expect(results[0].note.tags == ["verbs"])
    }

    @Test func searchNotesScopesToADeckAndItsSubdecks() throws {
        let db = try AppDatabase.inMemory()
        let (parentID, childID, otherID) = try db.dbWriter.write { db -> (String, String, String) in
            let parent = Deck(name: "Parent")
            try parent.insert(db)
            let child = Deck(parentID: parent.id, name: "Child")
            try child.insert(db)
            let other = Deck(name: "Other")
            try other.insert(db)
            return (parent.id, child.id, other.id)
        }

        try db.addBasicNote(deckID: parentID, front: "in parent", back: "x")
        try db.addBasicNote(deckID: childID, front: "in child", back: "x")
        try db.addBasicNote(deckID: otherID, front: "in other", back: "x")

        let results = try db.searchNotes(deckID: parentID)
        #expect(results.count == 2)
        #expect(!results.contains { $0.note.fieldValues.first == "in other" })
    }

    @Test func searchNotesReportsNoteTypeDeckNameAndCardCount() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try makeDeck(db)
        try db.addClozeNote(deckID: deckID, text: "{{c1::Madrid}} and {{c2::Paris}}")

        let results = try db.searchNotes()
        #expect(results.count == 1)
        #expect(results[0].noteTypeName == "Cloze")
        #expect(results[0].deckName == "Deck")
        #expect(results[0].cardCount == 2)
    }
}
