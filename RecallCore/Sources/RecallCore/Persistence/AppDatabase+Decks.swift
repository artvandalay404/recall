import GRDB
import Foundation

/// Deck listing/CRUD convenience wrapping `dbWriter` directly, so callers
/// outside RecallCore (the app's view models) never need to import GRDB.
public extension AppDatabase {
    struct DeckRow: Identifiable, Equatable, Sendable {
        public let deck: Deck
        public let stats: DeckStats
        public var id: String { deck.id }
    }

    /// Top-level decks (no parent) with their due/new counts, name-sorted.
    func rootDeckRows(now: Date = Date()) throws -> [DeckRow] {
        try dbWriter.read { db in
            let decks = try Deck
                .filter(Deck.Columns.parentID == nil)
                .order(Deck.Columns.name)
                .fetchAll(db)
            return try decks.map { deck in
                DeckRow(deck: deck, stats: try StudyQueueService.deckStats(deckID: deck.id, now: now, in: db))
            }
        }
    }

    @discardableResult
    func createDeck(name: String, parentID: String? = nil) throws -> Deck {
        try dbWriter.write { db in
            let deck = Deck(parentID: parentID, name: name)
            try deck.insert(db)
            try db.enqueueSyncChange(.deck, recordID: deck.id)
            return deck
        }
    }

    @discardableResult
    func renameDeck(_ deck: Deck, to name: String) throws -> Deck {
        try dbWriter.write { db in
            var updated = deck
            updated.name = name
            updated.updatedAt = Date()
            try updated.update(db)
            try db.enqueueSyncChange(.deck, recordID: updated.id)
            return updated
        }
    }

    func deleteDeck(_ deck: Deck) throws {
        _ = try dbWriter.write { db in
            try deck.delete(db)
            try db.enqueueSyncChange(.deck, recordID: deck.id, isDeletion: true)
        }
    }
}
