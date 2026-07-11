import CloudKit
import GRDB
import Foundation

/// Mirrors the local database to the user's CloudKit private database via
/// `CKSyncEngine` (PRD §7.8). Offline-first: local writes always land in
/// GRDB immediately (see `AppDatabase`'s write methods) regardless of
/// network/account state; this engine only drains the local outbox
/// (`pendingSyncChange`) into CloudKit in the background and applies
/// what CloudKit reports back. Conflicts resolve last-writer-wins per row,
/// comparing each row's own `updatedAt`; review logs never update in place
/// (they merge by append), and media syncs as CKAsset-bearing "MediaAsset"
/// records (PRD §7.9).
public actor SyncEngine {
    private let database: AppDatabase
    private let mediaStore: MediaStore
    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private let stateFileURL: URL
    private var outboxTask: Task<Void, Never>?

    public init(
        database: AppDatabase,
        mediaStore: MediaStore,
        containerIdentifier: String,
        stateDirectory: URL
    ) throws {
        self.database = database
        self.mediaStore = mediaStore
        self.container = CKContainer(identifier: containerIdentifier)
        self.zoneID = CKRecordZone.ID(zoneName: SyncSchema.zoneName, ownerName: CKCurrentUserDefaultName)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        self.stateFileURL = stateDirectory.appendingPathComponent("SyncEngineState.data")
    }

    /// Deferred until first access (via `start()`) so `self` is fully
    /// initialized before it's handed to `CKSyncEngine` as its delegate.
    private lazy var engine: CKSyncEngine = {
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: Self.loadStateSerialization(from: stateFileURL),
            delegate: self
        )
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }()

    /// Ensures the custom zone exists, starts draining the local outbox, and
    /// lets `CKSyncEngine` take over automatic scheduling from here. Safe to
    /// call once, at app launch; harmless (just idempotent) if called again.
    public func start() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        guard outboxTask == nil else { return }
        outboxTask = Task { [weak self] in
            await self?.observeOutbox()
        }
    }

    /// Forces an immediate two-way sync. `CKSyncEngine` already syncs
    /// automatically in the background (PRD §7.8's "sync is invisible"), so
    /// this exists only for an explicit manual trigger.
    public func syncNow() async {
        try? await engine.sendChanges()
        try? await engine.fetchChanges()
    }

    /// Watches the local outbox and forwards every pending change to
    /// `CKSyncEngine`'s own tracking, which persists and (de)schedules
    /// sending on its own. Re-adding an already-pending change is harmless,
    /// so this simply mirrors the outbox's current contents on every change
    /// rather than diffing — simpler, and self-healing across a crash
    /// between a local write and this observation firing.
    private func observeOutbox() async {
        let observation = ValueObservation.tracking { db in try PendingSyncChange.fetchAll(db) }
        do {
            for try await changes in observation.values(in: database.dbWriter) {
                guard !changes.isEmpty else { continue }
                let pending: [CKSyncEngine.PendingRecordZoneChange] = changes.map { change in
                    let recordID = CKRecord.ID(recordName: change.recordID, zoneID: zoneID)
                    return change.isDeletion ? .deleteRecord(recordID) : .saveRecord(recordID)
                }
                engine.state.add(pendingRecordZoneChanges: pending)
            }
        } catch {
            // Observation only fails if the database itself becomes unusable;
            // there's nothing sync-specific to recover from here.
        }
    }

    private static func loadStateSerialization(from url: URL) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistStateSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    // MARK: - Outbox bookkeeping

    private func clearPendingChange(recordType: SyncRecordType, recordID: String) {
        try? database.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM pendingSyncChange WHERE recordType = ? AND recordID = ?",
                arguments: [recordType.rawValue, recordID]
            )
        }
    }

    private func cacheSystemFields(of record: CKRecord, recordType: SyncRecordType) {
        try? database.dbWriter.write { db in
            try SyncRecordCache.setSystemFields(
                CKRecordCoding.encodeSystemFields(of: record),
                for: recordType,
                recordID: record.recordID.recordName,
                in: db
            )
        }
    }

    // MARK: - Building/looking up records (actor-isolated `async` so the
    // record-provider closure below — which CKSyncEngine may invoke off this
    // actor's executor — can safely `await` back into isolation).

    private func pendingChange(forRecordName recordName: String) async -> PendingSyncChange? {
        try? await database.dbWriter.read { db in
            try PendingSyncChange.filter(Column("recordID") == recordName).fetchOne(db)
        }
    }

    private func buildRecord(for pending: PendingSyncChange) async -> CKRecord? {
        try? SyncRecordBuilder.record(
            for: pending.recordType,
            recordID: pending.recordID,
            zoneID: zoneID,
            database: database,
            mediaStore: mediaStore
        )
    }
}

// MARK: - CKSyncEngineDelegate

extension SyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistStateSerialization(update.stateSerialization)

        case .fetchedRecordZoneChanges(let update):
            let modifications = update.modifications.map(\.record)
            let deletions = update.deletions.map {
                SyncRecordApplier.Deletion(recordType: $0.recordType, recordID: $0.recordID.recordName)
            }
            try? SyncRecordApplier.apply(modifications: modifications, deletions: deletions, database: database, mediaStore: mediaStore)

        case .sentRecordZoneChanges(let update):
            await handleSentRecordZoneChanges(update, syncEngine: syncEngine)

        case .accountChange, .fetchedDatabaseChanges, .sentDatabaseChanges,
             .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let pending = await self.pendingChange(forRecordName: recordID.recordName) else { return nil }
            return await self.buildRecord(for: pending)
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        for record in event.savedRecords {
            guard let recordType = SyncRecordType(rawValue: record.recordType) else { continue }
            cacheSystemFields(of: record, recordType: recordType)
            clearPendingChange(recordType: recordType, recordID: record.recordID.recordName)
        }

        for recordID in event.deletedRecordIDs {
            for recordType in SyncRecordType.allCases {
                clearPendingChange(recordType: recordType, recordID: recordID.recordName)
            }
        }

        for failure in event.failedRecordSaves {
            guard failure.error.code == .serverRecordChanged, let serverRecord = failure.error.serverRecord else { continue }
            await resolveConflict(clientRecord: failure.record, serverRecord: serverRecord, syncEngine: syncEngine)
        }
    }

    /// Last-writer-wins per PRD §7.8: compares each side's own `updatedAt`
    /// field. If the local edit is newer, it's merged onto the server's
    /// record (whose change tag CloudKit will actually accept) and requeued;
    /// otherwise the server's version is adopted locally right away and the
    /// pending local change is dropped.
    private func resolveConflict(clientRecord: CKRecord, serverRecord: CKRecord, syncEngine: CKSyncEngine) async {
        guard let recordType = SyncRecordType(rawValue: clientRecord.recordType) else { return }
        let recordID = clientRecord.recordID

        let mergedForResend: CKRecord? = try? await database.dbWriter.read { db in
            guard Self.localIsNewer(recordType: recordType, recordID: recordID.recordName, than: serverRecord, in: db) else {
                return nil
            }
            switch recordType {
            case .deck:
                guard let deck = try Deck.fetchOne(db, key: recordID.recordName) else { return nil }
                deck.populate(serverRecord)
            case .note:
                guard let note = try Note.fetchOne(db, key: recordID.recordName) else { return nil }
                note.populate(serverRecord)
            case .card:
                guard let card = try Card.fetchOne(db, key: recordID.recordName) else { return nil }
                card.populate(serverRecord)
            case .reviewLog, .mediaAsset:
                return nil
            }
            return serverRecord
        }

        if let mergedForResend {
            cacheSystemFields(of: mergedForResend, recordType: recordType)
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        } else {
            try? SyncRecordApplier.apply(modifications: [serverRecord], deletions: [], database: database, mediaStore: mediaStore)
            clearPendingChange(recordType: recordType, recordID: recordID.recordName)
        }
    }

    private static func localIsNewer(recordType: SyncRecordType, recordID: String, than serverRecord: CKRecord, in db: Database) -> Bool {
        guard let serverUpdatedAt: Date = serverRecord["updatedAt"] else { return true }
        switch recordType {
        case .deck:
            guard let local = try? Deck.fetchOne(db, key: recordID) else { return false }
            return local.updatedAt > serverUpdatedAt
        case .note:
            guard let local = try? Note.fetchOne(db, key: recordID) else { return false }
            return local.updatedAt > serverUpdatedAt
        case .card:
            guard let local = try? Card.fetchOne(db, key: recordID) else { return false }
            return local.updatedAt > serverUpdatedAt
        case .reviewLog, .mediaAsset:
            // Both are create-once and effectively immutable, so a genuine
            // conflict here shouldn't happen; server wins as the safe default.
            return false
        }
    }
}
