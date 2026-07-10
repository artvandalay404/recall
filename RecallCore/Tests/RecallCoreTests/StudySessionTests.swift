import Testing
import Foundation
import GRDB
@testable import RecallCore

struct StudySessionTests {
    private func makeBasicNoteAndCard(_ db: Database, deckID: String, due: Date) throws -> Card {
        let note = Note(noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"])
        try note.insert(db)
        let card = Card(noteID: note.id, deckID: deckID, templateOrdinal: 0, due: due)
        try card.insert(db)
        return card
    }

    @Test func gradingPersistsCardAndReviewLog() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return deck.id
        }

        let session = try StudySession(database: db, deckID: deckID, now: { now })
        #expect(session.queue.count == 1)

        try session.grade(.good)
        #expect(session.reviewedCount == 1)
        #expect(session.newIntroducedCount == 1)

        let logCount = try db.dbWriter.read { db in try ReviewLog.fetchCount(db) }
        #expect(logCount == 1)
    }

    @Test func renderCurrentProducesQuestionAndAnswer() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return deck.id
        }

        let session = try StudySession(database: db, deckID: deckID, now: { now })
        let rendered = try session.renderCurrent()
        #expect(rendered?.question.contains("front") == true)
        #expect(rendered?.answer.contains("back") == true)
    }

    @Test func rendersEveryCardGeneratedByAMultiClozeNote() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            return deck.id
        }
        // Two distinct cloze deletions generate two cards sharing the Cloze
        // note type's single CardTemplate row (ordinal 0), with
        // templateOrdinal 0 and 1 respectively addressing cloze numbers 1 and 2.
        try db.addClozeNote(deckID: deckID, text: "{{c1::Madrid}} and {{c2::Paris}}", due: now.addingTimeInterval(-10))

        let session = try StudySession(database: db, deckID: deckID, now: { now })
        #expect(session.queue.count == 2)

        let first = try session.renderCurrent()
        #expect(first?.question.contains("Paris") == true)
        #expect(first?.question.contains("Madrid") == false)

        try session.grade(.easy)
        let second = try session.renderCurrent()
        #expect(second?.question.contains("Madrid") == true)
        #expect(second?.question.contains("Paris") == false)
    }

    @Test func undoRestoresCardAndRemovesReviewLog() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let (deckID, originalCard) = try db.dbWriter.write { db -> (String, Card) in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            let card = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return (deck.id, card)
        }

        let session = try StudySession(database: db, deckID: deckID, now: { now })
        try session.grade(.good)
        #expect(try db.dbWriter.read { db in try ReviewLog.fetchCount(db) } == 1)
        #expect(session.canUndo)

        let undone = try session.undoLast()
        #expect(undone)
        #expect(session.reviewedCount == 0)
        #expect(session.newIntroducedCount == 0)
        #expect(!session.canUndo)

        let logCount = try db.dbWriter.read { db in try ReviewLog.fetchCount(db) }
        #expect(logCount == 0)

        let restored = try db.dbWriter.read { db in try Card.fetchOne(db, key: originalCard.id) }
        #expect(restored?.state == .new)
        #expect(abs(restored!.due.timeIntervalSince(originalCard.due)) < 0.01)

        #expect(session.currentCard?.id == originalCard.id)
    }

    @Test func undoWithNothingToUndoReturnsFalse() throws {
        let db = try AppDatabase.inMemory()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            return deck.id
        }

        let session = try StudySession(database: db, deckID: deckID)
        #expect(try session.undoLast() == false)
    }

    @Test func learningStepCardIsRequeuedWithinSession() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return deck.id
        }

        // Default learning steps are [60s, 600s]; grading "Good" on a new card
        // lands it in the first learning step (due ~60s later), well within
        // the default requeue window, so it should reappear this session.
        let session = try StudySession(database: db, deckID: deckID, now: { now })
        try session.grade(.good)

        #expect(session.isComplete == false)
        #expect(session.currentCard?.state == .learning)
    }

    @Test func graduatedReviewCardIsNotRequeuedWithinSession() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return deck.id
        }

        // "Easy" graduates a new card straight to `.review` with a multi-day
        // interval, which is well outside the requeue window.
        let session = try StudySession(database: db, deckID: deckID, now: { now })
        try session.grade(.easy)

        #expect(session.isComplete)
    }

    @Test func intervalPreviewsCoverAllFourRatings() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()
        let deckID = try db.dbWriter.write { db -> String in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try makeBasicNoteAndCard(db, deckID: deck.id, due: now.addingTimeInterval(-10))
            return deck.id
        }

        let session = try StudySession(database: db, deckID: deckID, now: { now })
        let previews = session.intervalPreviews()
        #expect(Set(previews.keys) == Set(Rating.allCases))
    }
}
