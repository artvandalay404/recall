import Foundation

/// Which of the three `.apkg`/`.colpkg` package layouts Anki has shipped
/// (PRD §7.7). Detected from the zip's optional `meta` entry — a one-field
/// protobuf (`PackageMetadata{ version = 1 }`) — with a name-based fallback
/// for older exporters (e.g. AnkiDroid) that don't write one.
enum AnkiPackageVersion: Int {
    /// `collection.anki2`, plain SQLite, legacy JSON `media` manifest.
    case legacy1 = 1
    /// `collection.anki21`, plain SQLite, legacy JSON `media` manifest.
    case legacy2 = 2
    /// `collection.anki21b`, whole-file zstd-compressed SQLite; `media` is a
    /// zstd-compressed protobuf manifest, and each numbered media entry is
    /// itself individually zstd-compressed.
    case latest = 3

    var collectionEntryName: String {
        switch self {
        case .legacy1: return "collection.anki2"
        case .legacy2: return "collection.anki21"
        case .latest: return "collection.anki21b"
        }
    }

    var isLegacy: Bool { self != .latest }

    static func detect(metaData: Data?, entryExists: (String) -> Bool) -> AnkiPackageVersion {
        if let metaData, let parsed = try? parseMeta(metaData), let version = AnkiPackageVersion(rawValue: parsed) {
            return version
        }
        return entryExists(AnkiPackageVersion.legacy2.collectionEntryName) ? .legacy2 : .legacy1
    }

    /// `PackageMetadata{ version = 1 }` — a single varint field.
    private static func parseMeta(_ data: Data) throws -> Int {
        var reader = ProtobufWireReader(data)
        var version = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            if fieldNumber == 1, wireType == 0 {
                version = Int(try reader.readVarint())
            } else {
                try reader.skip(wireType: wireType)
            }
        }
        return version
    }
}
