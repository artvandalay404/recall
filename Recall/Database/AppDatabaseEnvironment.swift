import SwiftUI
import RecallCore

private struct AppDatabaseKey: EnvironmentKey {
    static let defaultValue: AppDatabase = try! AppDatabase.inMemory()
}

extension EnvironmentValues {
    var appDatabase: AppDatabase {
        get { self[AppDatabaseKey.self] }
        set { self[AppDatabaseKey.self] = newValue }
    }
}
