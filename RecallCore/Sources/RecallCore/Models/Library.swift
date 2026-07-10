import GRDB
import Foundation

/// The single top-level container for everything in a user's local database —
/// the domain equivalent of the PRD's "Collection" (renamed to avoid colliding
/// with Swift's `Collection` protocol).
///
/// There is exactly one row of this table per on-device database.
public struct Library: Codable, Equatable, Sendable {
    public static let singletonID = 1

    public var id: Int
    public var createdAt: Date

    public init(id: Int = Library.singletonID, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}

extension Library: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "library"
}
