import CloudKit
import Foundation

/// A local row that mirrors 1:1 onto a CKRecord (PRD §7.8): `populate` writes
/// this value's fields onto an existing record (reused from
/// `syncRecordCache` when possible, so its system fields/change tag survive),
/// and `init?(record:)` decodes a fetched record back into a local value.
/// The record's own `recordID.recordName` is always the row's local `id`.
protocol CKRecordConvertible {
    static var syncRecordType: SyncRecordType { get }
    func populate(_ record: CKRecord)
    init?(record: CKRecord)
}

extension Deck: CKRecordConvertible {
    static var syncRecordType: SyncRecordType { .deck }

    func populate(_ record: CKRecord) {
        record["parentID"] = parentID
        record["name"] = name
        record["desiredRetention"] = desiredRetention
        record["newCardsPerDay"] = newCardsPerDay
        record["reviewsPerDay"] = reviewsPerDay
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
    }

    init?(record: CKRecord) {
        guard let name: String = record["name"],
              let desiredRetention: Double = record["desiredRetention"],
              let newCardsPerDay: Int = record["newCardsPerDay"],
              let reviewsPerDay: Int = record["reviewsPerDay"],
              let createdAt: Date = record["createdAt"],
              let updatedAt: Date = record["updatedAt"]
        else { return nil }
        let parentID: String? = record["parentID"]
        self.init(
            id: record.recordID.recordName,
            parentID: parentID,
            name: name,
            desiredRetention: desiredRetention,
            newCardsPerDay: newCardsPerDay,
            reviewsPerDay: reviewsPerDay,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Note: CKRecordConvertible {
    static var syncRecordType: SyncRecordType { .note }

    func populate(_ record: CKRecord) {
        record["noteTypeID"] = noteTypeID
        record["fieldValues"] = fieldValues
        record["tags"] = tags
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
    }

    init?(record: CKRecord) {
        guard let noteTypeID: String = record["noteTypeID"],
              let fieldValues: [String] = record["fieldValues"],
              let createdAt: Date = record["createdAt"],
              let updatedAt: Date = record["updatedAt"]
        else { return nil }
        let tags: [String] = record["tags"] ?? []
        self.init(
            id: record.recordID.recordName,
            noteTypeID: noteTypeID,
            fieldValues: fieldValues,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Card: CKRecordConvertible {
    static var syncRecordType: SyncRecordType { .card }

    func populate(_ record: CKRecord) {
        record["noteID"] = noteID
        record["deckID"] = deckID
        record["templateOrdinal"] = templateOrdinal
        record["state"] = state.rawValue
        record["step"] = step
        record["stability"] = stability
        record["difficulty"] = difficulty
        record["due"] = due
        record["lastReview"] = lastReview
        record["updatedAt"] = updatedAt
    }

    init?(record: CKRecord) {
        guard let noteID: String = record["noteID"],
              let deckID: String = record["deckID"],
              let templateOrdinal: Int = record["templateOrdinal"],
              let stateRaw: Int = record["state"],
              let state = CardState(rawValue: stateRaw),
              let due: Date = record["due"],
              let updatedAt: Date = record["updatedAt"]
        else { return nil }
        self.init(
            id: record.recordID.recordName,
            noteID: noteID,
            deckID: deckID,
            templateOrdinal: templateOrdinal,
            state: state,
            step: record["step"],
            stability: record["stability"],
            difficulty: record["difficulty"],
            due: due,
            lastReview: record["lastReview"],
            updatedAt: updatedAt
        )
    }
}

extension ReviewLog: CKRecordConvertible {
    static var syncRecordType: SyncRecordType { .reviewLog }

    func populate(_ record: CKRecord) {
        record["cardID"] = cardID
        record["rating"] = rating.rawValue
        record["reviewedAt"] = reviewedAt
        record["reviewDurationMS"] = reviewDurationMS
    }

    init?(record: CKRecord) {
        guard let cardID: String = record["cardID"],
              let ratingRaw: Int = record["rating"],
              let rating = Rating(rawValue: ratingRaw),
              let reviewedAt: Date = record["reviewedAt"]
        else { return nil }
        self.init(
            id: record.recordID.recordName,
            cardID: cardID,
            rating: rating,
            reviewedAt: reviewedAt,
            reviewDurationMS: record["reviewDurationMS"]
        )
    }
}
