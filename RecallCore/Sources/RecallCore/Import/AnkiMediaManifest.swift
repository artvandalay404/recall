import Foundation

/// One entry in a package's media manifest: the media file's original
/// filename (what field HTML references, e.g. `photo.jpg`) and the name it's
/// stored under inside the zip (a plain incrementing number, e.g. `"0"`).
struct AnkiMediaEntry: Equatable, Hashable {
    let originalName: String
    let zipEntryName: String
}

/// Parses a package's `media` entry (PRD §7.7) in either format Anki has
/// shipped: the legacy flat JSON map, or the newer zstd-compressed protobuf
/// `MediaEntries` message (`proto/anki/import_export.proto`):
/// ```
/// message MediaEntries {
///     message MediaEntry {
///         string name = 1;
///         uint32 size = 2;
///         bytes sha1 = 3;
///         optional uint32 legacy_zip_filename = 255;
///     }
///     repeated MediaEntry entries = 1;
/// }
/// ```
/// `size`/`sha1` aren't needed here (this importer trusts the archive's
/// bytes as-is) and are skipped.
enum AnkiMediaManifest {
    /// `{"0": "photo.jpg", "1": "clip.mp3", ...}`.
    static func parseLegacyJSON(_ data: Data) throws -> [AnkiMediaEntry] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw ApkgImportError.unrecognizedMediaManifest
        }
        return dict.map { AnkiMediaEntry(originalName: $0.value, zipEntryName: $0.key) }
    }

    /// `entryExists` resolves an entry's storage filename when the protobuf
    /// didn't set `legacy_zip_filename` — this importer has observed that
    /// field always being present in practice, but falls back to probing the
    /// archive for `"<index>"` / `"<index+1>"` rather than assuming either
    /// numbering convention.
    static func parseProtobuf(_ data: Data, entryExists: (String) -> Bool) throws -> [AnkiMediaEntry] {
        var reader = ProtobufWireReader(data)
        var result: [AnkiMediaEntry] = []
        var index = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            guard fieldNumber == 1, wireType == 2 else {
                try reader.skip(wireType: wireType)
                continue
            }
            let raw = try parseEntry(reader.readLengthDelimited())
            let zipEntryName = raw.legacyZipFilename.map(String.init)
                ?? (entryExists(String(index)) ? String(index) : String(index + 1))
            result.append(AnkiMediaEntry(originalName: raw.name, zipEntryName: zipEntryName))
            index += 1
        }
        return result
    }

    private struct RawEntry {
        var name = ""
        var legacyZipFilename: Int?
    }

    private static func parseEntry(_ data: Data) throws -> RawEntry {
        var reader = ProtobufWireReader(data)
        var entry = RawEntry()
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch (fieldNumber, wireType) {
            case (1, 2):
                entry.name = String(decoding: try reader.readLengthDelimited(), as: UTF8.self)
            case (255, 0):
                entry.legacyZipFilename = Int(try reader.readVarint())
            default:
                try reader.skip(wireType: wireType)
            }
        }
        return entry
    }
}
