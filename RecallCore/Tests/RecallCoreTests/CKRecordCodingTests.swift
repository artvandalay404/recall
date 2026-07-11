import Testing
import CloudKit
@testable import RecallCore

struct CKRecordCodingTests {
    @Test func systemFieldsRoundTripPreservesRecordIdentity() throws {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "deck-1", zoneID: zoneID)
        let record = CKRecord(recordType: SyncRecordType.deck.rawValue, recordID: recordID)
        record["name"] = "Spanish"

        let data = CKRecordCoding.encodeSystemFields(of: record)
        let decoded = try #require(CKRecordCoding.decodeSystemFields(data))

        #expect(decoded.recordID == recordID)
        #expect(decoded.recordType == SyncRecordType.deck.rawValue)
        // System-fields encoding deliberately drops field values (PRD §7.8's
        // cache stores only what's needed to reuse the record's identity).
        #expect(decoded["name"] as String? == nil)
    }

    @Test func decodingGarbageDataReturnsNil() {
        #expect(CKRecordCoding.decodeSystemFields(Data([0x01, 0x02, 0x03])) == nil)
    }
}
