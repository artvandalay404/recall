import Foundation

/// Copies user-picked images/audio into an app-managed media directory so
/// card fields can reference them by filename (e.g. `<img src="…">`,
/// `<audio controls src="…">`), rendered by pointing a WKWebView's `baseURL`
/// at `directory` (PRD §7.5, §7.9). One flat directory, matching the
/// established SRS media-folder convention this app's future importer
/// (phase 4) will also need to read from.
public struct MediaStore: Sendable {
    public enum MediaStoreError: Error, Equatable {
        case unreadableSource
    }

    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Copies the file at `sourceURL` into the media directory under a fresh
    /// unique filename, preserving its extension. Returns the filename to
    /// reference from field HTML — not the full path, since app-container
    /// paths can change between installs/devices while the filename stays valid.
    @discardableResult
    public func importFile(from sourceURL: URL) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw MediaStoreError.unreadableSource
        }
        return try importData(data, extension: sourceURL.pathExtension)
    }

    @discardableResult
    public func importData(_ data: Data, extension ext: String) throws -> String {
        let filename = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        try data.write(to: directory.appendingPathComponent(filename))
        return filename
    }

    public func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Copies `sourceURL` into the media directory under an exact, caller-
    /// chosen `filename` — unlike `importFile`/`importData`, which mint a
    /// fresh unique name. Used when receiving a synced media file (PRD §7.8)
    /// that must land under the same filename local note field HTML already
    /// references.
    public func store(_ sourceURL: URL, as filename: String) throws {
        let destination = url(for: filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}
