import GRDB
import Foundation

/// A note type defines the fields a `Note` holds and the card templates
/// generated from it. v1 ships a fixed set: Basic and Cloze.
public struct NoteType: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable, DatabaseValueConvertible {
        case basic
        case cloze
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: Kind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }
}

extension NoteType: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "noteType"
}
