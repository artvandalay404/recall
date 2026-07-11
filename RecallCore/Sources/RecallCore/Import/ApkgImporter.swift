import ZIPFoundation
import GRDB
import Foundation

/// Imports an Anki `.apkg` / `.colpkg` file (PRD §7.7): unzips it, reads the
/// embedded collection database and media, maps its models into this app's
/// fixed Basic/Cloze note types, and seeds FSRS scheduling state by replaying
/// each card's real review history through `FSRSScheduler`.
///
/// Every imported note is classified Cloze vs. Basic from its own first
/// field's content (`CardRenderer.clozeNumbers`), the same rule
/// `AppDatabase.createNote` already uses for notes created in-app — this
/// importer never needs to read the source collection's note-type/template
/// definitions (protobuf-encoded in the newer schema) at all.
///
/// A source note type with more than one card template (e.g. Anki's "Basic
/// (and reversed card)") only contributes its `ord == 0` card: v1 has no
/// custom-template support (PRD §3 non-goals), so the reverse card and its
/// review history are intentionally dropped. Cloze notes are unaffected —
/// Anki's own `ord` for a cloze card already equals its cloze number minus
/// one, matching this app's convention exactly, so every cloze sibling and
/// its history imports faithfully.
public enum ApkgImporter {
    public static func importDeck(from fileURL: URL, into database: AppDatabase, mediaStore: MediaStore) throws -> ApkgImportSummary {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        let archive: Archive
        do {
            archive = try Archive(url: fileURL, accessMode: .read)
        } catch {
            throw ApkgImportError.notAZipArchive
        }

        let version = AnkiPackageVersion.detect(
            metaData: try? Self.extractData(archive: archive, entryName: "meta"),
            entryExists: { archive[$0] != nil }
        )
        guard let collectionEntry = archive[version.collectionEntryName] else {
            throw ApkgImportError.missingCollection
        }

        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var collectionData = Data()
        _ = try archive.extract(collectionEntry) { collectionData.append($0) }
        if !version.isLegacy {
            collectionData = try ZstdDecoder.decompress(collectionData)
        }
        let collectionPath = workDirectory.appendingPathComponent("collection.sqlite").path
        try collectionData.write(to: URL(fileURLWithPath: collectionPath))

        let reader = try AnkiCollectionReader(path: collectionPath)
        let ankiNotes = try reader.fetchNotes()
        let ankiCards = try reader.fetchCards()
        let revlogByCardID = try reader.fetchRevlogByCardID()

        let mediaFilenameMap = try Self.importMedia(archive: archive, version: version, mediaStore: mediaStore)
        let deckIDByAnkiID = try Self.importDecks(try reader.fetchDecks(), into: database)

        var summary = ApkgImportSummary(deckCount: deckIDByAnkiID.count, mediaFileCount: mediaFilenameMap.count)
        let cardsByNoteID = Dictionary(grouping: ankiCards, by: \.noteID)
        let scheduler = FSRSScheduler()

        for note in ankiNotes {
            guard let sourceCards = cardsByNoteID[note.id], !sourceCards.isEmpty else { continue }
            guard let deckID = deckIDByAnkiID[sourceCards[0].homeDeckID] else { continue }

            let firstField = note.fieldValues.first ?? ""
            let isCloze = !CardRenderer.clozeNumbers(in: firstField).isEmpty
            let mappedFieldValues = [
                firstField,
                note.fieldValues.dropFirst().joined(separator: "<br>"),
            ].map { Self.rewriteMediaReferences(in: $0, using: mediaFilenameMap) }

            guard let createdNote = try? database.createNote(
                deckID: deckID,
                noteTypeID: isCloze ? BuiltInNoteTypes.clozeNoteTypeID : BuiltInNoteTypes.basicNoteTypeID,
                fieldValues: mappedFieldValues,
                tags: note.tags,
                due: Date(millisecondsSince1970: note.id)
            ) else { continue }
            summary.noteCount += 1

            let createdCards = try database.dbWriter.read { db in
                try Card.filter(Card.Columns.noteID == createdNote.id).fetchAll(db)
            }
            summary.cardCount += createdCards.count

            for createdCard in createdCards {
                let sourceOrd = isCloze ? createdCard.templateOrdinal : 0
                guard let sourceCard = sourceCards.first(where: { $0.ord == sourceOrd }),
                      let revlog = revlogByCardID[sourceCard.id], !revlog.isEmpty
                else { continue }

                var card = createdCard
                var logs: [ReviewLog] = []
                for entry in revlog {
                    let (updated, log) = scheduler.review(card: card, rating: entry.rating, reviewDate: Date(millisecondsSince1970: entry.id))
                    card = updated
                    logs.append(log)
                }

                try database.dbWriter.write { db in
                    try card.update(db)
                    try db.enqueueSyncChange(.card, recordID: card.id)
                    for log in logs {
                        try log.insert(db)
                        try db.enqueueSyncChange(.reviewLog, recordID: log.id)
                    }
                }
                summary.reviewLogCount += logs.count
            }
        }

        return summary
    }

    // MARK: - Decks

    /// Anki decks carry no parent-id column — hierarchy lives entirely in
    /// `::`-separated deck names — so parents are created first (shallowest
    /// names first) and looked up by their exact name to link each child's
    /// `parentID`.
    private static func importDecks(_ ankiDecks: [AnkiDeck], into database: AppDatabase) throws -> [Int64: String] {
        let ankiIDByName = Dictionary(uniqueKeysWithValues: ankiDecks.map { ($0.name, $0.id) })
        let orderedByDepth = ankiDecks.sorted {
            $0.name.components(separatedBy: "::").count < $1.name.components(separatedBy: "::").count
        }

        var recallIDByAnkiID: [Int64: String] = [:]
        for deck in orderedByDepth {
            let components = deck.name.components(separatedBy: "::")
            let parentRecallID = components.count > 1
                ? ankiIDByName[components.dropLast().joined(separator: "::")].flatMap { recallIDByAnkiID[$0] }
                : nil
            let created = try database.createDeck(name: components.last ?? deck.name, parentID: parentRecallID)
            recallIDByAnkiID[deck.id] = created.id
        }
        return recallIDByAnkiID
    }

    // MARK: - Media

    /// Maps each media file's *original* filename (what field HTML
    /// references) to the filename `MediaStore` assigned it on import.
    private static func importMedia(archive: Archive, version: AnkiPackageVersion, mediaStore: MediaStore) throws -> [String: String] {
        guard let manifestEntry = archive["media"] else { return [:] }
        let manifestData = try Self.extractData(archive: archive, entry: manifestEntry)

        let entries: [AnkiMediaEntry]
        if version.isLegacy {
            entries = try AnkiMediaManifest.parseLegacyJSON(manifestData)
        } else {
            entries = try AnkiMediaManifest.parseProtobuf(try ZstdDecoder.decompress(manifestData)) { archive[$0] != nil }
        }

        var map: [String: String] = [:]
        for entry in entries {
            guard let zipEntry = archive[entry.zipEntryName] else { continue }
            var data = try Self.extractData(archive: archive, entry: zipEntry)
            if !version.isLegacy {
                data = try ZstdDecoder.decompress(data)
            }
            let filename = try mediaStore.importData(data, extension: (entry.originalName as NSString).pathExtension)
            map[entry.originalName] = filename
        }
        return map
    }

    private static func extractData(archive: Archive, entryName: String) throws -> Data {
        guard let entry = archive[entryName] else { throw ApkgImportError.missingCollection }
        return try extractData(archive: archive, entry: entry)
    }

    private static func extractData(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    // MARK: - Field HTML rewriting

    /// Rewrites Anki's `[sound:name]` bracket syntax into this app's literal
    /// `<audio>` tag convention (PRD §7.9, matching `NoteEditorView`'s own
    /// audio-insertion HTML) and repoints `<img src="name">` at the filename
    /// `MediaStore` assigned the file on import.
    private static func rewriteMediaReferences(in html: String, using map: [String: String]) -> String {
        var result = Self.replacing(pattern: "\\[sound:([^\\]]+)\\]", in: html) { originalName in
            map[originalName].map { "<audio controls src=\"\($0)\"></audio>" }
        }
        result = Self.replacing(pattern: "(<img\\s+[^>]*?src=\")([^\"]+)(\"[^>]*>)", in: result, groupToReplace: 2) { originalName in
            map[originalName]
        }
        return result
    }

    /// Replaces every match of `pattern`'s capture group 1 (or `groupToReplace`)
    /// with `transform`'s result, leaving the match untouched when `transform`
    /// returns `nil` (e.g. a referenced media file this importer couldn't find).
    private static func replacing(pattern: String, in text: String, groupToReplace: Int = 1, transform: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let fullRange = NSRange(text.startIndex..., in: text)

        var result = ""
        var lastEnd = text.startIndex
        for match in regex.matches(in: text, range: fullRange) {
            guard let matchRange = Range(match.range, in: text),
                  let capturedRange = Range(match.range(at: groupToReplace), in: text)
            else { continue }

            let captured = String(text[capturedRange])
            guard let replacement = transform(captured) else { continue }

            result += text[lastEnd..<matchRange.lowerBound]
            if groupToReplace == 1 {
                result += replacement
            } else {
                result += text[matchRange.lowerBound..<capturedRange.lowerBound]
                result += replacement
                result += text[capturedRange.upperBound..<matchRange.upperBound]
            }
            lastEnd = matchRange.upperBound
        }
        result += text[lastEnd...]
        return result
    }
}

private extension Date {
    init(millisecondsSince1970: Int64) {
        self.init(timeIntervalSince1970: Double(millisecondsSince1970) / 1000)
    }
}
