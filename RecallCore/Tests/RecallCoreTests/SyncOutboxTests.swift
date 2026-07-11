import Testing
import Foundation
import GRDB
@testable import RecallCore

/// Every mutation to a synced table (PRD §7.8) should enqueue a matching
/// `pendingSyncChange` row in the same transaction, so `SyncEngine` can drain
/// it into CloudKit later. These exercise that bookkeeping directly against
/// the outbox table, independent of any live CKSyncEngine/CloudKit account.
struct SyncOutboxTests {
    private func pendingChanges(in db: AppDatabase) throws -> [PendingSyncChange] {
        try db.dbWriter.read { db in try PendingSyncChange.fetchAll(db) }
    }

    @Test func creatingADeckEnqueuesASyncChange() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")

        let changes = try pendingChanges(in: db)
        #expect(changes == [PendingSyncChange(recordType: .deck, recordID: deck.id, isDeletion: false)])
    }

    @Test func renamingADeckReplacesThePendingChangeRatherThanDuplicatingIt() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")
        try db.renameDeck(deck, to: "Español")

        let changes = try pendingChanges(in: db)
        #expect(changes.count == 1)
        #expect(changes.first?.isDeletion == false)
    }

    @Test func deletingAnEmptyDeckEnqueuesADeletion() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")
        try db.deleteDeck(deck)

        let changes = try pendingChanges(in: db)
        #expect(changes == [PendingSyncChange(recordType: .deck, recordID: deck.id, isDeletion: true)])
    }

    @Test func creatingANoteEnqueuesTheNoteAndItsCard() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")
        let note = try db.addBasicNote(deckID: deck.id, front: "hola", back: "hello")
        let card = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchOne(db) }

        let changes = try pendingChanges(in: db)
        #expect(Set(changes.map(\.recordType)) == [.deck, .note, .card])
        #expect(changes.contains(PendingSyncChange(recordType: .note, recordID: note.id, isDeletion: false)))
        #expect(changes.contains(PendingSyncChange(recordType: .card, recordID: card!.id, isDeletion: false)))
    }

    @Test func removingAClozeDeletionOnUpdateEnqueuesTheDroppedCardsDeletion() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.addClozeNote(deckID: deck.id, text: "{{c1::one}} {{c2::two}}")
        let cardsBefore = try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchAll(db) }
        let droppedCard = try #require(cardsBefore.first(where: { $0.templateOrdinal == 1 }))

        _ = try db.updateNote(note, fieldValues: ["{{c1::one}} two"], tags: [])

        let changes = try pendingChanges(in: db)
        #expect(changes.contains(PendingSyncChange(recordType: .card, recordID: droppedCard.id, isDeletion: true)))
    }

    @Test func deletingANoteEnqueuesTheNoteAndItsCascadedCardsAsDeletions() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.addBasicNote(deckID: deck.id, front: "front", back: "back")
        let card = try #require(try db.dbWriter.read { db in try Card.filter(Card.Columns.noteID == note.id).fetchOne(db) })

        try db.deleteNote(note)

        let changes = try pendingChanges(in: db)
        #expect(changes.contains(PendingSyncChange(recordType: .note, recordID: note.id, isDeletion: true)))
        #expect(changes.contains(PendingSyncChange(recordType: .card, recordID: card.id, isDeletion: true)))
    }

    @Test func gradingACardEnqueuesTheCardAndItsReviewLog() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        _ = try db.addBasicNote(deckID: deck.id, front: "front", back: "back")
        let session = try StudySession(database: db, deckID: deck.id)

        try session.grade(.good)

        let changes = try pendingChanges(in: db)
        #expect(changes.contains { $0.recordType == .card && !$0.isDeletion })
        #expect(changes.contains { $0.recordType == .reviewLog && !$0.isDeletion })
    }

    @Test func undoingAGradeEnqueuesTheRevertedCardAndAReviewLogDeletion() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        _ = try db.addBasicNote(deckID: deck.id, front: "front", back: "back")
        let session = try StudySession(database: db, deckID: deck.id)
        try session.grade(.good)

        try session.undoLast()

        let changes = try pendingChanges(in: db)
        #expect(changes.contains { $0.recordType == .card && !$0.isDeletion })
        #expect(changes.contains { $0.recordType == .reviewLog && $0.isDeletion })
    }

    @Test func savingANoteWithMediaRegistersAndEnqueuesAMediaAsset() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.createNote(
            deckID: deck.id,
            noteTypeID: BuiltInNoteTypes.basicNoteTypeID,
            fieldValues: ["<img src=\"pic.jpg\">", "back"]
        )

        let assets = try db.dbWriter.read { db in try MediaAsset.fetchAll(db) }
        #expect(assets == [MediaAsset(filename: "pic.jpg", noteID: note.id, createdAt: assets[0].createdAt)])

        let changes = try pendingChanges(in: db)
        #expect(changes.contains(PendingSyncChange(recordType: .mediaAsset, recordID: "pic.jpg", isDeletion: false)))
    }

    @Test func editingANoteDoesNotReRegisterAnAlreadyKnownMediaFilename() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.createNote(
            deckID: deck.id,
            noteTypeID: BuiltInNoteTypes.basicNoteTypeID,
            fieldValues: ["<img src=\"pic.jpg\">", "back"]
        )

        _ = try db.updateNote(note, fieldValues: ["<img src=\"pic.jpg\"> updated", "back"], tags: [])

        let assets = try db.dbWriter.read { db in try MediaAsset.fetchAll(db) }
        #expect(assets.count == 1)
    }
}
