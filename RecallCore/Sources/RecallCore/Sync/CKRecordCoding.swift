import CloudKit
import Foundation

/// Encodes/decodes a CKRecord's *system* fields only (record ID, change tag —
/// never the app's own field values) to/from `Data`, so `syncRecordCache` can
/// persist "the exact CKRecord CloudKit last saw" across launches without
/// keeping full record graphs around. This is Apple's documented
/// `encodeSystemFields(with:)` pattern for exactly this purpose.
enum CKRecordCoding {
    static func encodeSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}
