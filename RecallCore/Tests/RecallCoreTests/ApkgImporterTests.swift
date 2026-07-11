import Testing
import Foundation
import GRDB
import ZIPFoundation
@testable import RecallCore

struct ApkgImporterTests {
    @Test func importsDecksNotesCardsMediaAndReplaysReviewHistory() throws {
        let database = try AppDatabase.inMemory()
        let mediaStore = try MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let firstReview = Date(timeIntervalSince1970: 1_700_000_000)
        let secondReview = firstReview.addingTimeInterval(3600)

        let collectionData = try ApkgFixtureBuilder.sqliteFile { db in
            try db.execute(sql: "CREATE TABLE col (id INTEGER PRIMARY KEY, decks TEXT)")
            // Anki always materializes ancestor decks as their own rows, so
            // "Imported" (id 1) exists alongside its child "Imported::Spanish" (id 2).
            try db.execute(sql: "INSERT INTO col (id, decks) VALUES (1, ?)", arguments: [
                #"{"1": {"id": 1, "name": "Imported"}, "2": {"id": 2, "name": "Imported::Spanish"}}"#,
            ])
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "INSERT INTO notes (id, flds, tags) VALUES (1000, ?, 'greeting')", arguments: [
                "hola<img src=\"photo.jpg\">\u{1F}hello [sound:audio.mp3]",
            ])
            try db.execute(sql: "INSERT INTO notes (id, flds, tags) VALUES (2000, ?, '')", arguments: [
                "The capital of Spain is {{c1::Madrid}} and of France is {{c2::Paris}}.\u{1F}Europe facts",
            ])
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: """
                INSERT INTO cards (id, nid, did, odid, ord) VALUES
                (1, 1000, 2, 0, 0),
                (2, 2000, 2, 0, 0),
                (3, 2000, 2, 0, 1)
                """)
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
            try db.execute(sql: "INSERT INTO revlog (id, cid, ease, type) VALUES (?, 1, 3, 0)", arguments: [
                Int64(firstReview.timeIntervalSince1970 * 1000),
            ])
            try db.execute(sql: "INSERT INTO revlog (id, cid, ease, type) VALUES (?, 1, 3, 1)", arguments: [
                Int64(secondReview.timeIntervalSince1970 * 1000),
            ])
            try db.execute(sql: "INSERT INTO revlog (id, cid, ease, type) VALUES (?, 2, 4, 0)", arguments: [
                Int64(firstReview.timeIntervalSince1970 * 1000) + 1,
            ])
        }

        let apkgURL = try ApkgFixtureBuilder.makeArchive(entries: [
            "collection.anki2": collectionData,
            "media": Data(#"{"0": "audio.mp3", "1": "photo.jpg"}"#.utf8),
            "0": Data("FAKE_AUDIO".utf8),
            "1": Data("FAKE_IMAGE".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: apkgURL) }

        let summary = try ApkgImporter.importDeck(from: apkgURL, into: database, mediaStore: mediaStore)

        #expect(summary.deckCount == 2)
        #expect(summary.noteCount == 2)
        #expect(summary.cardCount == 3)
        #expect(summary.mediaFileCount == 2)
        #expect(summary.reviewLogCount == 3)

        try database.dbWriter.read { db in
            // Deck hierarchy: "Imported" parent created above the leaf "Spanish".
            let parent = try Deck.filter(Deck.Columns.name == "Imported").fetchOne(db)
            #expect(parent != nil)
            #expect(parent?.parentID == nil)
            let child = try Deck.filter(Deck.Columns.name == "Spanish").fetchOne(db)
            #expect(child?.parentID == parent?.id)

            // Basic note: media references rewritten to MediaStore filenames.
            let notes = try Note.fetchAll(db)
            let basicNote = try #require(notes.first { $0.noteTypeID == BuiltInNoteTypes.basicNoteTypeID })
            #expect(basicNote.tags == ["greeting"])
            #expect(!basicNote.fieldValues[0].contains("photo.jpg"))
            #expect(basicNote.fieldValues[0].contains("<img src=\""))
            #expect(basicNote.fieldValues[1].contains("<audio controls src=\""))
            #expect(!basicNote.fieldValues[1].contains("[sound:"))

            // Cloze note: both cloze siblings imported, matching Anki's own ord convention.
            let clozeNote = try #require(notes.first { $0.noteTypeID == BuiltInNoteTypes.clozeNoteTypeID })
            let clozeCards = try Card.filter(Card.Columns.noteID == clozeNote.id).order(Card.Columns.due).fetchAll(db)
            #expect(clozeCards.count == 2)

            // Studied card (source card id 1) replayed its two-review history through FSRS.
            let studiedCardRow = try Card.filter(Card.Columns.noteID == basicNote.id).fetchOne(db)
            let studiedCard = try #require(studiedCardRow)
            #expect(studiedCard.state != .new)
            #expect(studiedCard.lastReview != nil)

            var expected = Card(noteID: "x", deckID: "y", templateOrdinal: 0)
            let scheduler = FSRSScheduler()
            (expected, _) = scheduler.review(card: expected, rating: .good, reviewDate: firstReview)
            (expected, _) = scheduler.review(card: expected, rating: .good, reviewDate: secondReview)
            #expect(studiedCard.state == expected.state)
            #expect(abs(studiedCard.stability! - expected.stability!) < 1e-9)
            #expect(abs(studiedCard.difficulty! - expected.difficulty!) < 1e-9)
            #expect(studiedCard.due == expected.due)

            // Never-studied cloze sibling (source card id 3) stays new.
            let unstudiedCard = try #require(clozeCards.first { $0.id != studiedCard.id && $0.templateOrdinal == 1 })
            #expect(unstudiedCard.state == .new)
            #expect(unstudiedCard.lastReview == nil)

            let reviewLogCount = try ReviewLog.fetchCount(db)
            #expect(reviewLogCount == 3)
        }

        // Media bytes actually landed in the MediaStore under their new names.
        let importedBasicNote = try database.dbWriter.read { db in
            try Note.fetchAll(db).first { $0.noteTypeID == BuiltInNoteTypes.basicNoteTypeID }
        }
        let audioFilenameMatch = importedBasicNote?.fieldValues[1].firstMatch(of: /src="([^"]+)"/)
        let audioFilename = try #require(audioFilenameMatch?.1)
        let audioData = try Data(contentsOf: mediaStore.url(for: String(audioFilename)))
        #expect(audioData == Data("FAKE_AUDIO".utf8))
    }

    @Test func throwsOnAFileThatIsNotAZipArchive() throws {
        let database = try AppDatabase.inMemory()
        let mediaStore = try MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let notAZip = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("apkg")
        try Data("not a zip".utf8).write(to: notAZip)
        defer { try? FileManager.default.removeItem(at: notAZip) }

        #expect(throws: ApkgImportError.notAZipArchive) {
            try ApkgImporter.importDeck(from: notAZip, into: database, mediaStore: mediaStore)
        }
    }

    /// Exercises the "Latest" package layout (PRD §7.7): whole-file
    /// zstd-compressed `collection.anki21b`, a zstd-compressed protobuf media
    /// manifest, and individually zstd-compressed media entries. `CZstd` only
    /// vendors zstd's *decoder*, so this test shells out to the system `zstd`
    /// CLI to produce compressed fixtures — skipped when that binary isn't
    /// available rather than failing the suite.
    @Test(.enabled(if: SystemZstd.isAvailable))
    func importsTheNewerZstdProtobufPackageLayout() throws {
        let database = try AppDatabase.inMemory()
        let mediaStore = try MediaStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let collectionData = try ApkgFixtureBuilder.sqliteFile { db in
            // Schema V15+ shape: a normalized `decks` table, not col.decks JSON.
            try db.execute(sql: "CREATE TABLE decks (id INTEGER PRIMARY KEY, name TEXT, common BLOB, kind BLOB)")
            try db.execute(sql: "INSERT INTO decks (id, name) VALUES (1, 'Imported')")
            try db.execute(sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)")
            try db.execute(sql: "INSERT INTO notes (id, flds, tags) VALUES (1000, ?, '')", arguments: [
                "bonjour\u{1F}hello",
            ])
            try db.execute(sql: "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, odid INTEGER, ord INTEGER)")
            try db.execute(sql: "INSERT INTO cards (id, nid, did, odid, ord) VALUES (1, 1000, 1, 0, 0)")
            try db.execute(sql: "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER, ease INTEGER, type INTEGER)")
            try db.execute(sql: "INSERT INTO revlog (id, cid, ease, type) VALUES (1700000000000, 1, 3, 0)")
        }

        let mediaManifest = ProtobufFixtureEncoder.mediaEntries([
            ProtobufFixtureEncoder.mediaEntry(name: "clip.mp3", legacyZipFilename: 0),
        ])
        let meta = Data([0x08, 0x03]) // PackageMetadata{ version = 3 (Latest) }

        let apkgURL = try ApkgFixtureBuilder.makeArchive(entries: [
            "meta": meta,
            "collection.anki21b": try SystemZstd.compress(collectionData),
            "media": try SystemZstd.compress(mediaManifest),
            "0": try SystemZstd.compress(Data("FAKE_AUDIO".utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: apkgURL) }

        let summary = try ApkgImporter.importDeck(from: apkgURL, into: database, mediaStore: mediaStore)

        #expect(summary.deckCount == 1)
        #expect(summary.noteCount == 1)
        #expect(summary.cardCount == 1)
        #expect(summary.mediaFileCount == 1)
        #expect(summary.reviewLogCount == 1)

        let card = try database.dbWriter.read { db in try Card.fetchOne(db) }
        #expect(card?.state != .new)
    }
}

enum ApkgFixtureBuilder {
    static func sqliteFile(_ setup: (Database) throws -> Void) throws -> Data {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let dbQueue = try DatabaseQueue(path: path)
        try dbQueue.write(setup)
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    static func makeArchive(entries: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("apkg")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return data.subdata(in: start..<end)
            }
        }
        return url
    }
}

/// Shells out to a system `zstd` binary to compress test fixtures — this
/// project only vendors zstd's decoder (`CZstd`), so producing compressed
/// bytes for tests needs an external encoder.
enum SystemZstd {
    static let binaryPath: String? = {
        let candidates = ["/opt/homebrew/bin/zstd", "/opt/local/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var isAvailable: Bool { binaryPath != nil }

    static func compress(_ data: Data) throws -> Data {
        guard let binaryPath else { throw CocoaError(.fileNoSuchFile) }

        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: inputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-q", "-f", inputURL.path, "-o", outputURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }

        return try Data(contentsOf: outputURL)
    }
}
