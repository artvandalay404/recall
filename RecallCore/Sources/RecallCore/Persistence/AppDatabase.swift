import GRDB
import Foundation

/// Owns the app's GRDB connection and schema migrations.
///
/// Data model: `Library -> Deck (+subdecks) -> Note (via NoteType) -> Card -> ReviewLog`,
/// per the PRD's section 8 architecture table.
public struct AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
        try dbWriter.write { db in
            try BuiltInNoteTypes.seedIfNeeded(in: db)
        }
    }

    /// An in-memory database, useful for previews and tests.
    public static func inMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbQueue)
    }

    /// An on-disk database at the given path, creating parent directories as needed.
    public static func onDisk(at path: String) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let dbPool = try DatabasePool(path: path, configuration: configuration)
        return try AppDatabase(dbPool)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1CreateSchema") { db in
            try db.create(table: "library") { t in
                t.column("id", .integer).primaryKey()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "deck") { t in
                t.column("id", .text).primaryKey()
                t.column("parentID", .text).references("deck", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("desiredRetention", .double).notNull()
                t.column("newCardsPerDay", .integer).notNull()
                t.column("reviewsPerDay", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "deck_on_parentID", on: "deck", columns: ["parentID"])

            try db.create(table: "noteType") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "field") { t in
                t.column("id", .text).primaryKey()
                t.column("noteTypeID", .text).notNull().references("noteType", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("ordinal", .integer).notNull()
            }
            try db.create(index: "field_on_noteTypeID", on: "field", columns: ["noteTypeID"])

            try db.create(table: "cardTemplate") { t in
                t.column("id", .text).primaryKey()
                t.column("noteTypeID", .text).notNull().references("noteType", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("ordinal", .integer).notNull()
                t.column("questionTemplate", .text).notNull()
                t.column("answerTemplate", .text).notNull()
                t.column("css", .text).notNull()
            }
            try db.create(index: "cardTemplate_on_noteTypeID", on: "cardTemplate", columns: ["noteTypeID"])

            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("noteTypeID", .text).notNull().references("noteType", onDelete: .restrict)
                t.column("fieldValues", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "note_on_noteTypeID", on: "note", columns: ["noteTypeID"])

            try db.create(table: "card") { t in
                t.column("id", .text).primaryKey()
                t.column("noteID", .text).notNull().references("note", onDelete: .cascade)
                t.column("deckID", .text).notNull().references("deck", onDelete: .restrict)
                t.column("templateOrdinal", .integer).notNull()
                t.column("state", .integer).notNull()
                t.column("step", .integer)
                t.column("stability", .double)
                t.column("difficulty", .double)
                t.column("due", .datetime).notNull()
                t.column("lastReview", .datetime)
            }
            try db.create(index: "card_on_noteID", on: "card", columns: ["noteID"])
            try db.create(index: "card_on_deckID_state_due", on: "card", columns: ["deckID", "state", "due"])

            try db.create(table: "reviewLog") { t in
                t.column("id", .text).primaryKey()
                t.column("cardID", .text).notNull().references("card", onDelete: .cascade)
                t.column("rating", .integer).notNull()
                t.column("reviewedAt", .datetime).notNull()
                t.column("reviewDurationMS", .integer)
            }
            try db.create(index: "reviewLog_on_cardID", on: "reviewLog", columns: ["cardID"])
        }

        migrator.registerMigration("v2Sync") { db in
            // A per-card version so CloudKit sync (PRD §7.8) can resolve a
            // conflicting save with "last-writer-wins per card" by comparing
            // timestamps, mirroring `deck.updatedAt` / `note.updatedAt`.
            try db.alter(table: "card") { t in
                t.add(column: "updatedAt", .datetime).notNull().defaults(to: Date())
            }

            // The local outbox of not-yet-synced changes: every mutation to a
            // synced table enqueues (or replaces) a row here in the same
            // transaction, and SyncEngine drains it into CKSyncEngine's own
            // pending-change tracking. Keyed by the record's own type + id so
            // repeated edits before a sync collapse into one pending change.
            try db.create(table: "pendingSyncChange") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                t.column("isDeletion", .boolean).notNull()
                t.primaryKey(["recordType", "recordID"])
            }

            // Caches each synced row's last-known CKRecord system fields
            // (id, change tag, etc. — never the app's own field values) via
            // `CKRecord.encodeSystemFields`, so a resend after a fetch/save
            // can mutate the exact record CloudKit last saw instead of
            // colliding with a stale change tag.
            try db.create(table: "syncRecordCache") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                t.column("systemFields", .blob).notNull()
                t.primaryKey(["recordType", "recordID"])
            }

            // Tracks which media filenames (referenced by a note's field HTML,
            // PRD §7.9) a note owns, so sync can upload/download each one as
            // its own "MediaAsset" CKRecord (PRD §7.8's "media via CKAsset").
            try db.create(table: "mediaAsset") { t in
                t.column("filename", .text).primaryKey()
                t.column("noteID", .text).notNull().references("note", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "mediaAsset_on_noteID", on: "mediaAsset", columns: ["noteID"])
        }

        return migrator
    }
}
