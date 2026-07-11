import GRDB
import Foundation

/// Reads/writes each synced row's cached CKRecord system fields (recordID,
/// change tag — never the app's own field values), keyed by `(recordType,
/// recordID)`. `SyncEngine` uses this so a resend after a fetch or a save
/// reuses the exact CKRecord CloudKit last saw, rather than building a fresh
/// one that collides with a stale change tag.
enum SyncRecordCache {
    static func systemFields(for recordType: SyncRecordType, recordID: String, in db: Database) throws -> Data? {
        try Data.fetchOne(
            db,
            sql: "SELECT systemFields FROM syncRecordCache WHERE recordType = ? AND recordID = ?",
            arguments: [recordType.rawValue, recordID]
        )
    }

    static func setSystemFields(_ data: Data, for recordType: SyncRecordType, recordID: String, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO syncRecordCache (recordType, recordID, systemFields) VALUES (?, ?, ?)
                ON CONFLICT(recordType, recordID) DO UPDATE SET systemFields = excluded.systemFields
                """,
            arguments: [recordType.rawValue, recordID, data]
        )
    }

    static func removeSystemFields(for recordType: SyncRecordType, recordID: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM syncRecordCache WHERE recordType = ? AND recordID = ?",
            arguments: [recordType.rawValue, recordID]
        )
    }
}
