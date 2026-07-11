import SwiftUI
import RecallCore

private struct SyncEngineKey: EnvironmentKey {
    static let defaultValue: SyncEngine? = nil
}

extension EnvironmentValues {
    /// `nil` in previews/tests, where there's no CloudKit container to sync
    /// against; `RecallApp` injects the real instance at launch.
    var syncEngine: SyncEngine? {
        get { self[SyncEngineKey.self] }
        set { self[SyncEngineKey.self] = newValue }
    }
}
