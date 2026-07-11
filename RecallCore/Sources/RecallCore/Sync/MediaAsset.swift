import GRDB
import Foundation

/// Tracks one media filename a `Note`'s field HTML references (an `<img>` or
/// `<audio>` `src`, PRD §7.9), so `SyncEngine` can mirror it to CloudKit as
/// its own "MediaAsset" CKRecord carrying a `CKAsset` (PRD §7.8). Registered
/// once, at note-save time, by scanning the note's final field values with
/// `MediaReferenceScanner` — never removed, even if a later edit drops the
/// reference, so a still-referenced-elsewhere or already-synced file is never
/// destroyed by an unrelated edit.
struct MediaAsset: Codable, Equatable, Sendable {
    var filename: String
    var noteID: String
    var createdAt: Date

    init(filename: String, noteID: String, createdAt: Date = Date()) {
        self.filename = filename
        self.noteID = noteID
        self.createdAt = createdAt
    }
}

extension MediaAsset: FetchableRecord, PersistableRecord {
    static let databaseTableName = "mediaAsset"
}
