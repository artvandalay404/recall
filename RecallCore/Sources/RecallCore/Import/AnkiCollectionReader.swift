import GRDB
import Foundation

/// A deck in the source collection, keyed by Anki's own integer deck id.
/// Hierarchy is encoded purely through `::`-separated `name` segments (both
/// the legacy JSON and the newer `decks` table agree on this), not a
/// parent-id column.
struct AnkiDeck: Equatable, Hashable {
    let id: Int64
    let name: String
}

struct AnkiNote: Equatable {
    let id: Int64
    let fieldValues: [String]
    let tags: [String]
}

struct AnkiCard: Equatable {
    let id: Int64
    let noteID: Int64
    let ord: Int
    /// A card's *home* deck: its original deck (`odid`) if it's currently
    /// sitting in a filtered/cram deck, else its own deck (`did`). Stable
    /// across every schema version this importer supports, so this avoids
    /// needing to decode `decks.kind` just to recognize filtered decks.
    let homeDeckID: Int64
}

struct AnkiRevlogEntry: Equatable {
    let id: Int64
    let cardID: Int64
    let rating: Rating
}

/// Reads the stable, schema-version-independent parts of an Anki collection
/// database (PRD §7.7): decks, notes, cards, and review history. Deliberately
/// does not read note types/templates — this importer classifies every note
/// as Basic- or Cloze-shaped from its own field content (mirroring
/// `AppDatabase.cardOrdinals`), so it never needs the source collection's
/// per-notetype template/config data (which, in the newer schema, is
/// protobuf-encoded and not needed here regardless).
struct AnkiCollectionReader {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        do {
            dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        } catch {
            throw ApkgImportError.unreadableCollection(error.localizedDescription)
        }
    }

    /// Prefers the normalized `decks` table (schema V15+, plain `id`/`name`
    /// columns); falls back to the legacy `col.decks` JSON blob, which is the
    /// source of truth on schema V11 and is left stale (not kept in sync) on
    /// later schema versions once a `decks` table exists.
    func fetchDecks() throws -> [AnkiDeck] {
        try dbQueue.read { db in
            if try db.tableExists("decks") {
                let rows = try Row.fetchAll(db, sql: "SELECT id, name FROM decks")
                if !rows.isEmpty {
                    return rows.map { AnkiDeck(id: $0["id"], name: $0["name"]) }
                }
            }
            guard let json = try String.fetchOne(db, sql: "SELECT decks FROM col LIMIT 1") else { return [] }
            return Self.parseLegacyDecksJSON(json)
        }
    }

    /// `flds` is a `\u{1F}`-joined (ASCII unit separator) list of field
    /// values; `tags` is a whitespace-separated string.
    func fetchNotes() throws -> [AnkiNote] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, flds, tags FROM notes")
            return rows.map { row in
                let flds: String = row["flds"]
                let tagsField: String = row["tags"]
                return AnkiNote(
                    id: row["id"],
                    fieldValues: flds.components(separatedBy: "\u{1F}"),
                    tags: tagsField.split(whereSeparator: \.isWhitespace).map(String.init)
                )
            }
        }
    }

    func fetchCards() throws -> [AnkiCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, nid, did, odid, ord FROM cards")
            return rows.map { row in
                let did: Int64 = row["did"]
                let odid: Int64 = row["odid"]
                return AnkiCard(id: row["id"], noteID: row["nid"], ord: row["ord"], homeDeckID: odid != 0 ? odid : did)
            }
        }
    }

    /// Genuine grading events only, oldest first, grouped by card — manual
    /// reschedules (`ease` 0) and non-grading review kinds (filtered/cram,
    /// manual, rescheduled) are excluded since they don't represent a real
    /// FSRS-replayable review (PRD §7.7's SM-2 → FSRS seeding).
    func fetchRevlogByCardID() throws -> [Int64: [AnkiRevlogEntry]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, cid, ease FROM revlog
                WHERE ease BETWEEN 1 AND 4 AND type IN (0, 1, 2)
                ORDER BY id ASC
                """)
            var result: [Int64: [AnkiRevlogEntry]] = [:]
            for row in rows {
                let cardID: Int64 = row["cid"]
                guard let rating = Rating(rawValue: row["ease"]) else { continue }
                result[cardID, default: []].append(AnkiRevlogEntry(id: row["id"], cardID: cardID, rating: rating))
            }
            return result
        }
    }

    private static func parseLegacyDecksJSON(_ json: String) -> [AnkiDeck] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [] }

        return dict.values.compactMap { value in
            guard let name = value["name"] as? String, let idNumber = value["id"] as? NSNumber else { return nil }
            return AnkiDeck(id: idNumber.int64Value, name: name)
        }
    }
}
