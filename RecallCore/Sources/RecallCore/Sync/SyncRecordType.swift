import GRDB

/// The synced tables (PRD §7.8), doubling as each row's CloudKit `recordType`
/// string — one custom zone (`SyncSchema.zoneName`) in the private database
/// holds all of them. `NoteType`/`Field`/`CardTemplate` are deliberately not
/// synced: v1 ships only the fixed Basic/Cloze note types (PRD §3 non-goals),
/// seeded with the same well-known IDs and content on every device by
/// `BuiltInNoteTypes.seedIfNeeded`, so they're already identical everywhere
/// without needing to move any bytes.
enum SyncRecordType: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case deck = "Deck"
    case note = "Note"
    case card = "Card"
    case reviewLog = "ReviewLog"
    case mediaAsset = "MediaAsset"
}

enum SyncSchema {
    static let zoneName = "RecallZone"
}
