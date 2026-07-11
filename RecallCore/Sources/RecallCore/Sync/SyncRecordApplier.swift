import CloudKit
import GRDB
import Foundation

/// Applies fetched CKRecord modifications/deletions (PRD §7.8, the "fetch"
/// side of sync) into the local database in one write transaction: in
/// dependency order (Deck, Note, Card, ReviewLog, MediaAsset) with
/// foreign-key checks deferred to commit, so a Card that arrives before its
/// parent Note in the same fetched batch — CKSyncEngine doesn't guarantee
/// per-type ordering — still lands correctly.
enum SyncRecordApplier {
    struct Deletion {
        let recordType: String
        let recordID: String
    }

    static func apply(
        modifications: [CKRecord],
        deletions: [Deletion],
        database: AppDatabase,
        mediaStore: MediaStore
    ) throws {
        try database.dbWriter.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")

            for record in modifications where record.recordType == SyncRecordType.deck.rawValue {
                guard let deck = Deck(record: record) else { continue }
                try deck.save(db)
            }
            for record in modifications where record.recordType == SyncRecordType.note.rawValue {
                guard let note = Note(record: record) else { continue }
                try note.save(db)
            }
            for record in modifications where record.recordType == SyncRecordType.card.rawValue {
                guard let card = Card(record: record) else { continue }
                try card.save(db)
            }
            for record in modifications where record.recordType == SyncRecordType.reviewLog.rawValue {
                guard let log = ReviewLog(record: record) else { continue }
                try log.save(db)
            }
            for record in modifications where record.recordType == SyncRecordType.mediaAsset.rawValue {
                guard let asset = try MediaAssetSync.apply(record, mediaStore: mediaStore) else { continue }
                try asset.save(db)
            }

            for deletion in deletions {
                try Self.applyDeletion(deletion, in: db)
            }

            for record in modifications {
                guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
                try SyncRecordCache.setSystemFields(
                    CKRecordCoding.encodeSystemFields(of: record),
                    for: type,
                    recordID: record.recordID.recordName,
                    in: db
                )
            }
        }
    }

    private static func applyDeletion(_ deletion: Deletion, in db: Database) throws {
        switch deletion.recordType {
        case SyncRecordType.deck.rawValue:
            try db.execute(sql: "DELETE FROM deck WHERE id = ?", arguments: [deletion.recordID])
        case SyncRecordType.note.rawValue:
            try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [deletion.recordID])
        case SyncRecordType.card.rawValue:
            try db.execute(sql: "DELETE FROM card WHERE id = ?", arguments: [deletion.recordID])
        case SyncRecordType.reviewLog.rawValue:
            try db.execute(sql: "DELETE FROM reviewLog WHERE id = ?", arguments: [deletion.recordID])
        case SyncRecordType.mediaAsset.rawValue:
            try db.execute(sql: "DELETE FROM mediaAsset WHERE filename = ?", arguments: [deletion.recordID])
        default:
            break
        }
        try db.execute(
            sql: "DELETE FROM syncRecordCache WHERE recordType = ? AND recordID = ?",
            arguments: [deletion.recordType, deletion.recordID]
        )
    }
}
