import SwiftUI
import RecallCore

@main
struct RecallApp: App {
    /// Matches the `com.apple.developer.icloud-container-identifiers`
    /// entitlement (Apple's default `iCloud.<bundle-id>` convention).
    private static let cloudKitContainerIdentifier = "iCloud.com.recall.ios"

    private let database: AppDatabase
    private let mediaStore: MediaStore
    private let syncEngine: SyncEngine

    init() {
        do {
            let directory = try Self.applicationSupportDirectory()
            database = try AppDatabase.onDisk(at: directory.appendingPathComponent("Recall.sqlite").path)
            mediaStore = try MediaStore(directory: directory.appendingPathComponent("Media", isDirectory: true))
            syncEngine = try SyncEngine(
                database: database,
                mediaStore: mediaStore,
                containerIdentifier: Self.cloudKitContainerIdentifier,
                stateDirectory: directory.appendingPathComponent("Sync", isDirectory: true)
            )
        } catch {
            fatalError("Failed to open Recall's database: \(error)")
        }

        #if DEBUG
        DemoSeeder.seedIfNeeded(in: database)
        #endif

        let syncEngine = self.syncEngine
        Task { await syncEngine.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, database)
                .environment(\.mediaStore, mediaStore)
                .environment(\.syncEngine, syncEngine)
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
