import Testing
import Foundation
import GRDB
@testable import RecallCore

struct StudyQueueServiceTests {
    private func insertCard(_ db: Database, deckID: String, state: CardState, due: Date, noteID: String = UUID().uuidString) throws -> Card {
        let note = Note(id: noteID, noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"])
        try note.insert(db)
        let card = Card(noteID: note.id, deckID: deckID, templateOrdinal: 0, state: state, due: due)
        try card.insert(db)
        return card
    }

    @Test func newAndDueCardsAreBothIncludedInTheQueue() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try insertCard(db, deckID: deck.id, state: .new, due: now.addingTimeInterval(-10))
            _ = try insertCard(db, deckID: deck.id, state: .review, due: now.addingTimeInterval(-3600))

            let queue = try StudyQueueService.buildQueue(deckID: deck.id, now: now, in: db)
            #expect(queue.count == 2)
        }
    }

    @Test func futureDueCardsAreExcluded() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            _ = try insertCard(db, deckID: deck.id, state: .review, due: now.addingTimeInterval(3600))

            let queue = try StudyQueueService.buildQueue(deckID: deck.id, now: now, in: db)
            #expect(queue.isEmpty)

            let stats = try StudyQueueService.deckStats(deckID: deck.id, now: now, in: db)
            #expect(stats.dueCount == 0)
        }
    }

    @Test func dueCardsComeBeforeNewCardsInQueueOrder() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck")
            try deck.insert(db)
            let newCard = try insertCard(db, deckID: deck.id, state: .new, due: now.addingTimeInterval(-100))
            let dueCard = try insertCard(db, deckID: deck.id, state: .review, due: now.addingTimeInterval(-100))

            let queue = try StudyQueueService.buildQueue(deckID: deck.id, now: now, in: db)
            #expect(queue.map(\.id) == [dueCard.id, newCard.id])
        }
    }

    @Test func newCardsPerDayLimitCapsTheQueue() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck", newCardsPerDay: 2)
            try deck.insert(db)
            for _ in 0..<5 {
                _ = try insertCard(db, deckID: deck.id, state: .new, due: now)
            }

            let queue = try StudyQueueService.buildQueue(deckID: deck.id, now: now, in: db)
            #expect(queue.count == 2)

            let stats = try StudyQueueService.deckStats(deckID: deck.id, now: now, in: db)
            #expect(stats.newCount == 2)
        }
    }

    @Test func reviewingACardTodayReducesRemainingAllowance() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let deck = Deck(name: "Deck", newCardsPerDay: 10, reviewsPerDay: 10)
            try deck.insert(db)

            let card = try insertCard(db, deckID: deck.id, state: .new, due: now.addingTimeInterval(-10))
            let (updated, log) = FSRSScheduler().review(card: card, rating: .good, reviewDate: now.addingTimeInterval(-5))
            try log.insert(db)
            try updated.update(db)

            _ = try insertCard(db, deckID: deck.id, state: .new, due: now.addingTimeInterval(-10))

            let stats = try StudyQueueService.deckStats(deckID: deck.id, now: now, in: db)
            #expect(stats.newCount == 1)
        }
    }

    @Test func subdeckCardsAreAggregatedIntoParentQueue() throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try db.dbWriter.write { db in
            let parent = Deck(name: "Parent")
            try parent.insert(db)
            let child = Deck(parentID: parent.id, name: "Child")
            try child.insert(db)

            _ = try insertCard(db, deckID: parent.id, state: .new, due: now)
            _ = try insertCard(db, deckID: child.id, state: .new, due: now)

            let queue = try StudyQueueService.buildQueue(deckID: parent.id, now: now, in: db)
            #expect(queue.count == 2)

            let childQueue = try StudyQueueService.buildQueue(deckID: child.id, now: now, in: db)
            #expect(childQueue.count == 1)
        }
    }
}
