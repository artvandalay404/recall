import GRDB
import Foundation

/// One row in the local sync outbox: a synced record that's changed locally
/// and hasn't been confirmed sent to CloudKit yet. `SyncEngine` drains this
/// table into `CKSyncEngine`'s own pending-change tracking (PRD §7.8).
struct PendingSyncChange: Codable, Equatable, Sendable {
    var recordType: SyncRecordType
    var recordID: String
    var isDeletion: Bool
}

extension PendingSyncChange: FetchableRecord, PersistableRecord {
    static let databaseTableName = "pendingSyncChange"
}

extension Database {
    /// Enqueues (or replaces) a pending sync change for `recordID`, in the
    /// same transaction as the row's own insert/update/delete. Repeated edits
    /// before a sync collapse into the latest `isDeletion` value.
    func enqueueSyncChange(_ recordType: SyncRecordType, recordID: String, isDeletion: Bool = false) throws {
        try execute(
            sql: """
                INSERT INTO pendingSyncChange (recordType, recordID, isDeletion) VALUES (?, ?, ?)
                ON CONFLICT(recordType, recordID) DO UPDATE SET isDeletion = excluded.isDeletion
                """,
            arguments: [recordType.rawValue, recordID, isDeletion]
        )
    }
}
