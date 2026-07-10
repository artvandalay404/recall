import GRDB
import Foundation

/// A deck of cards. Decks nest via `parentID` to form subdecks.
public struct Deck: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var parentID: String?
    public var name: String
    public var desiredRetention: Double
    public var newCardsPerDay: Int
    public var reviewsPerDay: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        parentID: String? = nil,
        name: String,
        desiredRetention: Double = 0.9,
        newCardsPerDay: Int = 20,
        reviewsPerDay: Int = 200,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.desiredRetention = desiredRetention
        self.newCardsPerDay = newCardsPerDay
        self.reviewsPerDay = reviewsPerDay
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Deck: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "deck"

    public enum Columns {
        static let id = Column(CodingKeys.id)
        static let parentID = Column(CodingKeys.parentID)
        static let name = Column(CodingKeys.name)
    }
}
