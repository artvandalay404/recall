import SwiftUI
import RecallCore

@main
struct RecallApp: App {
    private let database: AppDatabase
    private let mediaStore: MediaStore

    init() {
        do {
            let directory = try Self.applicationSupportDirectory()
            database = try AppDatabase.onDisk(at: directory.appendingPathComponent("Recall.sqlite").path)
            mediaStore = try MediaStore(directory: directory.appendingPathComponent("Media", isDirectory: true))
        } catch {
            fatalError("Failed to open Recall's database: \(error)")
        }

        #if DEBUG
        DemoSeeder.seedIfNeeded(in: database)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, database)
                .environment(\.mediaStore, mediaStore)
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
