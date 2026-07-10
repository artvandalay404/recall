import GRDB
import Foundation

/// Computes per-deck due/new counts and builds the ordered queue of cards to
/// study for a session (PRD §7.1, §7.4), aggregating a deck with all of its
/// subdecks and respecting each deck's daily new/review limits.
///
/// Subdeck limits simplification: v1 applies the *root* deck's own
/// `newCardsPerDay` / `reviewsPerDay` to the whole aggregated subtree, rather
/// than reconciling each subdeck's individual limits against its parent's —
/// the PRD doesn't specify subdeck limit interaction, and this keeps the v1
/// behavior predictable (one number, set on the deck you tap to study).
public enum StudyQueueService {
    public static func deckStats(deckID: String, now: Date = Date(), in db: Database) throws -> DeckStats {
        guard let rootDeck = try Deck.fetchOne(db, key: deckID) else {
            return DeckStats(dueCount: 0, newCount: 0)
        }
        let deckIDs = try descendantDeckIDs(of: deckID, in: db)
        let allowance = try remainingAllowance(for: rootDeck, deckIDs: deckIDs, now: now, in: db)

        let dueCount = try Card
            .filter(deckIDs.contains(Card.Columns.deckID))
            .filter(Card.Columns.state != CardState.new)
            .filter(Card.Columns.due <= now)
            .fetchCount(db)

        let newCount = try Card
            .filter(deckIDs.contains(Card.Columns.deckID))
            .filter(Card.Columns.state == CardState.new)
            .fetchCount(db)

        return DeckStats(
            dueCount: min(dueCount, allowance.remainingReviews),
            newCount: min(newCount, allowance.remainingNew)
        )
    }

    /// The ordered queue of cards to study this session: due reviews
    /// (soonest-due first), then new cards (introduction order), each capped
    /// by what's left of today's allowance.
    public static func buildQueue(deckID: String, now: Date = Date(), in db: Database) throws -> [Card] {
        guard let rootDeck = try Deck.fetchOne(db, key: deckID) else { return [] }
        let deckIDs = try descendantDeckIDs(of: deckID, in: db)
        let allowance = try remainingAllowance(for: rootDeck, deckIDs: deckIDs, now: now, in: db)

        let dueCards = try Card
            .filter(deckIDs.contains(Card.Columns.deckID))
            .filter(Card.Columns.state != CardState.new)
            .filter(Card.Columns.due <= now)
            .order(Card.Columns.due)
            .limit(allowance.remainingReviews)
            .fetchAll(db)

        let newCards = try Card
            .filter(deckIDs.contains(Card.Columns.deckID))
            .filter(Card.Columns.state == CardState.new)
            .order(Card.Columns.due)
            .limit(allowance.remainingNew)
            .fetchAll(db)

        return dueCards + newCards
    }

    // MARK: - Subdeck resolution

    static func descendantDeckIDs(of deckID: String, in db: Database) throws -> [String] {
        var result = [deckID]
        var frontier = [deckID]
        while !frontier.isEmpty {
            let children = try Deck.filter(frontier.contains(Deck.Columns.parentID)).fetchAll(db)
            frontier = children.map(\.id)
            result.append(contentsOf: frontier)
        }
        return result
    }

    // MARK: - Daily allowance

    private struct Allowance {
        var remainingNew: Int
        var remainingReviews: Int
    }

    private static func remainingAllowance(for rootDeck: Deck, deckIDs: [String], now: Date, in db: Database) throws -> Allowance {
        let counts = try countsToday(deckIDs: deckIDs, now: now, in: db)
        return Allowance(
            remainingNew: max(0, rootDeck.newCardsPerDay - counts.newIntroducedToday),
            remainingReviews: max(0, rootDeck.reviewsPerDay - (counts.totalReviewsToday - counts.newIntroducedToday))
        )
    }

    private struct TodayCounts {
        var totalReviewsToday: Int
        var newIntroducedToday: Int
    }

    /// - `totalReviewsToday`: every review log entry today for cards in scope.
    /// - `newIntroducedToday`: of those, the ones that were a card's *first*
    ///   ever review — i.e. the card graduated out of `.new` today. A card can
    ///   only be new once, so its first review log row is exactly the moment
    ///   it was introduced.
    private static func countsToday(deckIDs: [String], now: Date, in db: Database) throws -> TodayCounts {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return TodayCounts(totalReviewsToday: 0, newIntroducedToday: 0)
        }

        let placeholders = databasePlaceholders(count: deckIDs.count)

        let totalReviewsToday = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM reviewLog
            JOIN card ON card.id = reviewLog.cardID
            WHERE card.deckID IN (\(placeholders)) AND reviewLog.reviewedAt >= ? AND reviewLog.reviewedAt < ?
            """, arguments: StatementArguments(deckIDs) + StatementArguments([startOfDay, endOfDay])) ?? 0

        let newIntroducedToday = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM (
                SELECT reviewLog.cardID AS cardID, MIN(reviewLog.reviewedAt) AS firstReview
                FROM reviewLog
                JOIN card ON card.id = reviewLog.cardID
                WHERE card.deckID IN (\(placeholders))
                GROUP BY reviewLog.cardID
            ) WHERE firstReview >= ? AND firstReview < ?
            """, arguments: StatementArguments(deckIDs) + StatementArguments([startOfDay, endOfDay])) ?? 0

        return TodayCounts(totalReviewsToday: totalReviewsToday, newIntroducedToday: newIntroducedToday)
    }

    private static func databasePlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}
