import GRDB
import Foundation

/// An append-only record of a single review event. Never mutated or deleted;
/// review logs merge by append across synced devices.
public struct ReviewLog: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var cardID: String
    public var rating: Rating
    public var reviewedAt: Date

    /// Wall-clock time the learner spent on this review, if measured.
    public var reviewDurationMS: Int?

    public init(
        id: String = UUID().uuidString,
        cardID: String,
        rating: Rating,
        reviewedAt: Date,
        reviewDurationMS: Int? = nil
    ) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.reviewDurationMS = reviewDurationMS
    }
}

extension ReviewLog: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "reviewLog"
}
