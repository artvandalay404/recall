import Testing
import Foundation
import CloudKit
@testable import RecallCore

/// These exercise the CKRecord <-> model mapping entirely offline: CKRecord
/// itself can be constructed and read locally with no CloudKit container or
/// network access, so this is a pure round-trip check of `CKRecordConvertible`.
struct CKRecordConvertibleTests {
    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    private func freshRecord<T: CKRecordConvertible>(for id: String, as type: T.Type) -> CKRecord {
        CKRecord(recordType: T.syncRecordType.rawValue, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
    }

    @Test func deckRoundTripsThroughACKRecord() throws {
        let deck = Deck(parentID: "parent-1", name: "Spanish", desiredRetention: 0.85, newCardsPerDay: 15, reviewsPerDay: 150)
        let record = freshRecord(for: deck.id, as: Deck.self)
        deck.populate(record)

        let decoded = try #require(Deck(record: record))
        #expect(decoded == deck)
    }

    @Test func deckWithNoParentRoundTrips() throws {
        let deck = Deck(name: "Root deck")
        let record = freshRecord(for: deck.id, as: Deck.self)
        deck.populate(record)

        let decoded = try #require(Deck(record: record))
        #expect(decoded.parentID == nil)
        #expect(decoded == deck)
    }

    @Test func noteRoundTripsThroughACKRecord() throws {
        let note = Note(noteTypeID: BuiltInNoteTypes.basicNoteTypeID, fieldValues: ["hola", "hello"], tags: ["language::spanish"])
        let record = freshRecord(for: note.id, as: Note.self)
        note.populate(record)

        let decoded = try #require(Note(record: record))
        #expect(decoded == note)
    }

    @Test func cardRoundTripsIncludingOptionalSchedulingFields() throws {
        let card = Card(
            noteID: "note-1", deckID: "deck-1", templateOrdinal: 0,
            state: .review, step: nil, stability: 4.2, difficulty: 3.1,
            due: Date(timeIntervalSince1970: 1_700_000_000), lastReview: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let record = freshRecord(for: card.id, as: Card.self)
        card.populate(record)

        let decoded = try #require(Card(record: record))
        #expect(decoded == card)
    }

    @Test func newCardWithNilSchedulingFieldsRoundTrips() throws {
        let card = Card(noteID: "note-1", deckID: "deck-1", templateOrdinal: 0)
        let record = freshRecord(for: card.id, as: Card.self)
        card.populate(record)

        let decoded = try #require(Card(record: record))
        #expect(decoded.step == nil)
        #expect(decoded.stability == nil)
        #expect(decoded.difficulty == nil)
        #expect(decoded.lastReview == nil)
        #expect(decoded == card)
    }

    @Test func reviewLogRoundTripsThroughACKRecord() throws {
        let log = ReviewLog(cardID: "card-1", rating: .good, reviewedAt: Date(timeIntervalSince1970: 1_700_000_000), reviewDurationMS: 4200)
        let record = freshRecord(for: log.id, as: ReviewLog.self)
        log.populate(record)

        let decoded = try #require(ReviewLog(record: record))
        #expect(decoded == log)
    }

    @Test func decodingARecordMissingRequiredFieldsFails() {
        let record = CKRecord(recordType: SyncRecordType.deck.rawValue, recordID: CKRecord.ID(recordName: "deck-1", zoneID: zoneID))
        record["name"] = "Incomplete"
        // desiredRetention/newCardsPerDay/etc. deliberately left unset.
        #expect(Deck(record: record) == nil)
    }
}
