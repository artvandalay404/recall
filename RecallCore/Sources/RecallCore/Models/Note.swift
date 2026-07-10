import GRDB
import Foundation

/// A note holds the field values a learner entered. One note generates one or
/// more `Card`s via its `NoteType`'s card templates. Editing a note updates
/// every card generated from it.
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var noteTypeID: String

    /// Field values, ordinal-aligned with the owning `NoteType`'s `Field` rows.
    /// Stored as JSON by GRDB's automatic Codable support.
    public var fieldValues: [String]

    /// Hierarchical tags (e.g. "language::spanish::verbs"), independent of deck.
    public var tags: [String]

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        noteTypeID: String,
        fieldValues: [String],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.noteTypeID = noteTypeID
        self.fieldValues = fieldValues
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Note: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "note"
}
