import CloudKit
import Foundation

/// `MediaAsset` <-> CKRecord conversion (PRD §7.8's "media via CKAsset").
/// Handled separately from `CKRecordConvertible` because it needs `MediaStore`
/// to turn a filename into the actual file CloudKit uploads/downloads.
enum MediaAssetSync {
    static func populate(_ record: CKRecord, asset: MediaAsset, mediaStore: MediaStore) {
        record["noteID"] = asset.noteID
        record["createdAt"] = asset.createdAt
        record["asset"] = CKAsset(fileURL: mediaStore.url(for: asset.filename))
    }

    /// Decodes a fetched "MediaAsset" record, copying its downloaded asset
    /// file into `mediaStore` under the filename the record's own ID names —
    /// the same filename local note field HTML already references.
    static func apply(_ record: CKRecord, mediaStore: MediaStore) throws -> MediaAsset? {
        guard let noteID: String = record["noteID"],
              let createdAt: Date = record["createdAt"],
              let asset: CKAsset = record["asset"],
              let fileURL = asset.fileURL
        else { return nil }
        let filename = record.recordID.recordName
        try mediaStore.store(fileURL, as: filename)
        return MediaAsset(filename: filename, noteID: noteID, createdAt: createdAt)
    }
}
