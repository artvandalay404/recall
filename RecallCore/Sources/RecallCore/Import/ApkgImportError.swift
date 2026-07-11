import Foundation

/// Errors surfaced by `ApkgImporter` that an import UI should present to the
/// user, rather than a raw archive/database failure.
public enum ApkgImportError: Error, Equatable {
    /// The file isn't a zip archive, or ZIPFoundation couldn't open it.
    case notAZipArchive
    /// None of `collection.anki21b`, `collection.anki21`, `collection.anki2`
    /// were found in the archive.
    case missingCollection
    /// The collection database couldn't be read as SQLite once extracted
    /// (and, if applicable, zstd-decompressed).
    case unreadableCollection(String)
    /// The `media` manifest entry exists but is in neither the legacy JSON
    /// nor the newer zstd/protobuf format this importer understands.
    case unrecognizedMediaManifest
}

extension ApkgImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAZipArchive:
            return "This doesn't look like a valid deck file."
        case .missingCollection:
            return "This file doesn't contain a collection to import."
        case .unreadableCollection(let detail):
            return "Couldn't read the collection database (\(detail))."
        case .unrecognizedMediaManifest:
            return "Couldn't read this deck's media file."
        }
    }
}
