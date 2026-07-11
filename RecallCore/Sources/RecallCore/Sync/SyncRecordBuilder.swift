import CloudKit
import GRDB
import Foundation

/// Builds the CKRecord to save for one pending sync change (the "send" side
/// of PRD §7.8), reusing the cached CKRecord CloudKit last saw for that row
/// when one exists — so its system fields/change tag survive a resend —
/// and falling back to a fresh record for a row never synced before.
/// Returns `nil` when the local row no longer exists (e.g. it was deleted
/// after being enqueued as a save), telling the caller to skip it.
enum SyncRecordBuilder {
    static func record(
        for recordType: SyncRecordType,
        recordID: String,
        zoneID: CKRecordZone.ID,
        database: AppDatabase,
        mediaStore: MediaStore
    ) throws -> CKRecord? {
        try database.dbWriter.read { db in
            switch recordType {
            case .deck:
                guard let deck = try Deck.fetchOne(db, key: recordID) else { return nil }
                let record = try Self.reusableRecord(recordType: recordType, recordID: recordID, zoneID: zoneID, in: db)
                deck.populate(record)
                return record
            case .note:
                guard let note = try Note.fetchOne(db, key: recordID) else { return nil }
                let record = try Self.reusableRecord(recordType: recordType, recordID: recordID, zoneID: zoneID, in: db)
                note.populate(record)
                return record
            case .card:
                guard let card = try Card.fetchOne(db, key: recordID) else { return nil }
                let record = try Self.reusableRecord(recordType: recordType, recordID: recordID, zoneID: zoneID, in: db)
                card.populate(record)
                return record
            case .reviewLog:
                guard let log = try ReviewLog.fetchOne(db, key: recordID) else { return nil }
                let record = try Self.reusableRecord(recordType: recordType, recordID: recordID, zoneID: zoneID, in: db)
                log.populate(record)
                return record
            case .mediaAsset:
                guard let asset = try MediaAsset.fetchOne(db, key: recordID) else { return nil }
                let record = try Self.reusableRecord(recordType: recordType, recordID: recordID, zoneID: zoneID, in: db)
                MediaAssetSync.populate(record, asset: asset, mediaStore: mediaStore)
                return record
            }
        }
    }

    private static func reusableRecord(
        recordType: SyncRecordType,
        recordID: String,
        zoneID: CKRecordZone.ID,
        in db: Database
    ) throws -> CKRecord {
        if let cached = try SyncRecordCache.systemFields(for: recordType, recordID: recordID, in: db),
           let record = CKRecordCoding.decodeSystemFields(cached) {
            return record
        }
        return CKRecord(recordType: recordType.rawValue, recordID: CKRecord.ID(recordName: recordID, zoneID: zoneID))
    }
}
