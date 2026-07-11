import Testing
import Foundation
import CloudKit
import GRDB
@testable import RecallCore

struct SyncRecordApplierTests {
    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    private func record<T: CKRecordConvertible>(for value: T, id: String) -> CKRecord {
        let record = CKRecord(recordType: T.syncRecordType.rawValue, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        value.populate(record)
        return record
    }

    private func mediaStore() throws -> MediaStore {
        try MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    @Test func applyingAFetchedDeckInsertsItLocally() throws {
        let db = try AppDatabase.inMemory()
        // A whole-second timestamp survives GRDB's `.datetime` storage
        // precision exactly, so the post-round-trip struct compares equal.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let deck = Deck(name: "Spanish", createdAt: fixedDate, updatedAt: fixedDate)

        try SyncRecordApplier.apply(
            modifications: [record(for: deck, id: deck.id)],
            deletions: [],
            database: db,
            mediaStore: try mediaStore()
        )

        let fetched = try db.dbWriter.read { db in try Deck.fetchOne(db, key: deck.id) }
        #expect(fetched == deck)
    }

    @Test func applyingOutOfOrderRecordsStillSatisfiesForeignKeys() throws {
        let db = try AppDatabase.inMemory()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let deck = Deck(name: "Deck", createdAt: fixedDate, updatedAt: fixedDate)
        let note = Note(noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["front", "back"], createdAt: fixedDate, updatedAt: fixedDate)
        let card = Card(noteID: note.id, deckID: deck.id, templateOrdinal: 0, due: fixedDate, updatedAt: fixedDate)

        // Card and Note listed before their parents — apply() must still
        // succeed by applying in dependency order within the transaction.
        try SyncRecordApplier.apply(
            modifications: [
                record(for: card, id: card.id),
                record(for: note, id: note.id),
                record(for: deck, id: deck.id),
            ],
            deletions: [],
            database: db,
            mediaStore: try mediaStore()
        )

        let fetchedCard = try db.dbWriter.read { db in try Card.fetchOne(db, key: card.id) }
        #expect(fetchedCard == card)
    }

    @Test func applyingADeletionRemovesTheLocalRow() throws {
        let db = try AppDatabase.inMemory()
        let deck = try db.createDeck(name: "Deck")

        try SyncRecordApplier.apply(
            modifications: [],
            deletions: [SyncRecordApplier.Deletion(recordType: SyncRecordType.deck.rawValue, recordID: deck.id)],
            database: db,
            mediaStore: try mediaStore()
        )

        let fetched = try db.dbWriter.read { db in try Deck.fetchOne(db, key: deck.id) }
        #expect(fetched == nil)
    }

    @Test func applyingAModificationCachesItsSystemFields() throws {
        let db = try AppDatabase.inMemory()
        let deck = Deck(name: "Spanish")

        try SyncRecordApplier.apply(
            modifications: [record(for: deck, id: deck.id)],
            deletions: [],
            database: db,
            mediaStore: try mediaStore()
        )

        let cached = try db.dbWriter.read { db in try SyncRecordCache.systemFields(for: .deck, recordID: deck.id, in: db) }
        #expect(cached != nil)
    }

    @Test func applyingAMediaAssetRecordCopiesTheAssetIntoTheMediaStore() throws {
        let db = try AppDatabase.inMemory()
        let store = try mediaStore()
        let deck = try db.createDeck(name: "Deck")
        let note = try db.addBasicNote(deckID: deck.id, front: "front", back: "back")
        let sourceFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try Data("fake image bytes".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: sourceFile) }

        let mediaRecord = CKRecord(recordType: SyncRecordType.mediaAsset.rawValue, recordID: CKRecord.ID(recordName: "pic.jpg", zoneID: zoneID))
        mediaRecord["noteID"] = note.id
        mediaRecord["createdAt"] = Date()
        mediaRecord["asset"] = CKAsset(fileURL: sourceFile)

        try SyncRecordApplier.apply(modifications: [mediaRecord], deletions: [], database: db, mediaStore: store)

        let contents = try Data(contentsOf: store.url(for: "pic.jpg"))
        #expect(contents == Data("fake image bytes".utf8))
        let assetRow = try db.dbWriter.read { db in try MediaAsset.fetchOne(db, key: "pic.jpg") }
        #expect(assetRow?.noteID == note.id)
    }
}
