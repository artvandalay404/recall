import SwiftUI
import RecallCore

private struct MediaStoreKey: EnvironmentKey {
    static let defaultValue: MediaStore = try! MediaStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("RecallMediaPreview", isDirectory: true)
    )
}

extension EnvironmentValues {
    var mediaStore: MediaStore {
        get { self[MediaStoreKey.self] }
        set { self[MediaStoreKey.self] = newValue }
    }
}
