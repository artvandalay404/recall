import GRDB
import Foundation

/// A single reviewable card generated from a `Note` via one of its note type's
/// card templates. Carries the FSRS scheduling state directly, matching the
/// upstream FSRS reference scheduler's `Card` shape (state/step/stability/
/// difficulty/due/lastReview) plus the linkage fields needed by the app.
public struct Card: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var noteID: String
    public var deckID: String

    /// Which of the note type's card templates generated this card.
    public var templateOrdinal: Int

    public var state: CardState
    public var step: Int?
    public var stability: Double?
    public var difficulty: Double?

    /// For `.new` cards, the FIFO introduction order; otherwise the date the
    /// card is next due for review.
    public var due: Date
    public var lastReview: Date?

    public init(
        id: String = UUID().uuidString,
        noteID: String,
        deckID: String,
        templateOrdinal: Int,
        state: CardState = .new,
        step: Int? = nil,
        stability: Double? = nil,
        difficulty: Double? = nil,
        due: Date = Date(),
        lastReview: Date? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.deckID = deckID
        self.templateOrdinal = templateOrdinal
        self.state = state
        self.step = step
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lastReview = lastReview
    }
}

extension Card: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "card"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let deckID = Column(CodingKeys.deckID)
        static let noteID = Column(CodingKeys.noteID)
        static let state = Column(CodingKeys.state)
        static let due = Column(CodingKeys.due)
    }
}
