import Testing
import Foundation
import GRDB
@testable import RecallCore

struct AnkiCollectionReaderTests {
    private func makeSQLiteFile(_ setup: (Database) throws -> Void) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite").path
        let dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write(setup)
        return path
    }

    @Test func readsDecksFromLegacyJSONColumnWhenNoDecksTableExists() throws {
        let path = try makeSQLiteFile { db in
            try db.execute(sql: "CREATE TABLE col (id INTEGER PRIMARY KEY, decks TEXT)")
            try db.execute(sql: "INSERT INTO col (id, decks) VALUES (1, ?)", arguments: [
                #"{"1": {"id": 1, "name": "Default"}, "2": {"id": 2, "name": "Spanish::Verbs"}}"#,
            ])
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
        }

        let reader = try AnkiCollectionReader(path: path)
        let decks = try reader.fetchDecks()

        #expect(Set(decks.map(\.name)) == Set(["Default", "Spanish::Verbs"]))
        #expect(decks.first(where: { $0.name == "Spanish::Verbs" })?.id == 2)
    }

    @Test func readsDecksFromNormalizedTableWhenPresent() throws {
        let path = try makeSQLiteFile { db in
            try db.execute(sql: "CREATE TABLE decks (id INTEGER PRIMARY KEY, name TEXT, common BLOB, kind BLOB)")
            try db.execute(sql: "INSERT INTO decks (id, name) VALUES (1, 'Default'), (2, 'French')")
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
        }

        let decks = try AnkiCollectionReader(path: path).fetchDecks()

        #expect(Set(decks) == Set([AnkiDeck(id: 1, name: "Default"), AnkiDeck(id: 2, name: "French")]))
    }

    @Test func splitsNoteFieldsOnUnitSeparatorAndTagsOnWhitespace() throws {
        let path = try makeSQLiteFile { db in
            try db.execute(sql: "CREATE TABLE col (id INTEGER PRIMARY KEY, decks TEXT)")
            try db.execute(sql: "INSERT INTO col (id, decks) VALUES (1, '{}')")
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "INSERT INTO notes (id, flds, tags) VALUES (100, ?, ' spanish::verbs  irregular ')", arguments: [
                "hola\u{1F}hello",
            ])
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
        }

        let notes = try AnkiCollectionReader(path: path).fetchNotes()

        #expect(notes == [AnkiNote(id: 100, fieldValues: ["hola", "hello"], tags: ["spanish::verbs", "irregular"])])
    }

    @Test func resolvesCardHomeDeckToOriginalDeckWhenInAFilteredDeck() throws {
        let path = try makeSQLiteFile { db in
            try db.execute(sql: "CREATE TABLE col (id INTEGER PRIMARY KEY, decks TEXT)")
            try db.execute(sql: "INSERT INTO col (id, decks) VALUES (1, '{}')")
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            // Card 1: parked in filtered deck 999, home deck 2. Card 2: normal, lives directly in deck 3.
            try db.execute(sql: "INSERT INTO cards (id, nid, did, odid, ord) VALUES (1, 100, 999, 2, 0), (2, 100, 3, 0, 1)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
        }

        let cards = try AnkiCollectionReader(path: path).fetchCards()

        #expect(cards.first(where: { $0.id == 1 })?.homeDeckID == 2)
        #expect(cards.first(where: { $0.id == 2 })?.homeDeckID == 3)
    }

    @Test func fetchesRevlogGroupedByCardExcludingManualAndFilteredEntries() throws {
        let path = try makeSQLiteFile { db in
            try db.execute(sql: "CREATE TABLE col (id INTEGER PRIMARY KEY, decks TEXT)")
            try db.execute(sql: "INSERT INTO col (id, decks) VALUES (1, '{}')")
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
            try db.execute(sql: """
                INSERT INTO revlog (id, cid, ease, type) VALUES
                (1000, 1, 3, 0),
                (2000, 1, 4, 1),
                (3000, 1, 0, 4),
                (4000, 1, 2, 3),
                (5000, 2, 1, 2)
                """)
        }

        let revlog = try AnkiCollectionReader(path: path).fetchRevlogByCardID()

        #expect(revlog[1]?.map(\.rating) == [.good, .easy])
        #expect(revlog[2]?.map(\.rating) == [.again])
    }
}
