import GRDB
import Foundation

/// One named field slot (e.g. "Front", "Back") belonging to a `NoteType`, in
/// display/storage order via `ordinal`.
public struct Field: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var noteTypeID: String
    public var name: String
    public var ordinal: Int

    public init(
        id: String = UUID().uuidString,
        noteTypeID: String,
        name: String,
        ordinal: Int
    ) {
        self.id = id
        self.noteTypeID = noteTypeID
        self.name = name
        self.ordinal = ordinal
    }
}

extension Field: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "field"
}
