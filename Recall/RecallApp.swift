import SwiftUI
import RecallCore

@main
struct RecallApp: App {
    private let database: AppDatabase

    init() {
        do {
            let url = try Self.databaseURL()
            database = try AppDatabase.onDisk(at: url.path)
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
        }
    }

    private static func databaseURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("Recall.sqlite")
    }
}
