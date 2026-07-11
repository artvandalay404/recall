import Testing
import Foundation
import CloudKit
import GRDB
@testable import RecallCore

struct SyncRecordBuilderTests {
    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    private func mediaStore() throws -> MediaStore {
        try MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    @Test func buildsARecordForAnExistingDeck() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")

        let record = try SyncRecordBuilder.record(
            for: .deck, recordID: deck.id, zoneID: zoneID, database: db, mediaStore: try mediaStore()
        )

        #expect(record?.recordID.recordName == deck.id)
        #expect(record?["name"] as String? == "Spanish")
    }

    @Test func returnsNilWhenTheLocalRowNoLongerExists() throws {
        let db = try AppDatabase.inMemory()

        let record = try SyncRecordBuilder.record(
            for: .deck, recordID: "missing-deck", zoneID: zoneID, database: db, mediaStore: try mediaStore()
        )

        #expect(record == nil)
    }

    @Test func reusesCachedSystemFieldsInsteadOfMintingAFreshRecordIdentity() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Spanish")

        let cachedRecord = CKRecord(recordType: SyncRecordType.deck.rawValue, recordID: CKRecord.ID(recordName: deck.id, zoneID: zoneID))
        let cachedData = CKRecordCoding.encodeSystemFields(of: cachedRecord)
        try db.dbWriter.write { db in try SyncRecordCache.setSystemFields(cachedData, for: .deck, recordID: deck.id, in: db) }

        let built = try SyncRecordBuilder.record(
            for: .deck, recordID: deck.id, zoneID: zoneID, database: db, mediaStore: try mediaStore()
        )

        #expect(built?.recordID == cachedRecord.recordID)
        #expect(built?["name"] as String? == "Spanish")
    }

    @Test func buildsAMediaAssetRecordWithAnAssetPointingAtTheStoredFile() throws {
        let db = try AppDatabase.inMemory()
        let store = try mediaStore()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.addBasicNote(deckID: deck.id, front: "front", back: "back")

        try db.dbWriter.write { db in
            try MediaAsset(filename: "manual.jpg", noteID: note.id).insert(db)
        }
        try Data("bytes".utf8).write(to: store.url(for: "manual.jpg"))

        let record = try SyncRecordBuilder.record(
            for: .mediaAsset, recordID: "manual.jpg", zoneID: zoneID, database: db, mediaStore: store
        )

        let asset: CKAsset? = record?["asset"]
        #expect(asset?.fileURL == store.url(for: "manual.jpg"))
    }
}
