import Testing
import Foundation
@testable import RecallCore

struct AnkiMediaManifestTests {
    @Test func parsesLegacyJSONManifest() throws {
        let json = Data(#"{"0": "photo.jpg", "1": "clip.mp3"}"#.utf8)

        let entries = try AnkiMediaManifest.parseLegacyJSON(json)

        #expect(Set(entries) == Set([
            AnkiMediaEntry(originalName: "photo.jpg", zipEntryName: "0"),
            AnkiMediaEntry(originalName: "clip.mp3", zipEntryName: "1"),
        ]))
    }

    @Test func parsesProtobufManifestUsingLegacyZipFilename() throws {
        let message = ProtobufFixtureEncoder.mediaEntries([
            ProtobufFixtureEncoder.mediaEntry(name: "photo.jpg", legacyZipFilename: 5),
            ProtobufFixtureEncoder.mediaEntry(name: "clip.mp3", legacyZipFilename: 6),
        ])

        let entries = try AnkiMediaManifest.parseProtobuf(message, entryExists: { _ in false })

        #expect(entries == [
            AnkiMediaEntry(originalName: "photo.jpg", zipEntryName: "5"),
            AnkiMediaEntry(originalName: "clip.mp3", zipEntryName: "6"),
        ])
    }

    @Test func parsesProtobufManifestFallingBackToIndexWhenLegacyZipFilenameIsAbsent() throws {
        let message = ProtobufFixtureEncoder.mediaEntries([
            ProtobufFixtureEncoder.mediaEntry(name: "photo.jpg", legacyZipFilename: nil),
        ])

        let entriesWhenZeroIndexedFileExists = try AnkiMediaManifest.parseProtobuf(message, entryExists: { $0 == "0" })
        #expect(entriesWhenZeroIndexedFileExists == [AnkiMediaEntry(originalName: "photo.jpg", zipEntryName: "0")])

        let entriesWhenOneIndexedFileExists = try AnkiMediaManifest.parseProtobuf(message, entryExists: { $0 == "1" })
        #expect(entriesWhenOneIndexedFileExists == [AnkiMediaEntry(originalName: "photo.jpg", zipEntryName: "1")])
    }

    @Test func parsesEmptyManifest() throws {
        let entries = try AnkiMediaManifest.parseProtobuf(Data(), entryExists: { _ in false })
        #expect(entries.isEmpty)
    }
}

/// A tiny protobuf *encoder*, test-only: builds byte fixtures for
/// `AnkiMediaManifest`'s decoder without needing a real `.apkg` file or a
/// full protobuf library.
enum ProtobufFixtureEncoder {
    static func mediaEntries(_ entries: [Data]) -> Data {
        var result = Data()
        for entry in entries {
            result.append(tag(field: 1, wireType: 2))
            result.append(varint(UInt64(entry.count)))
            result.append(entry)
        }
        return result
    }

    static func mediaEntry(name: String, legacyZipFilename: Int?) -> Data {
        var result = Data()
        let nameBytes = Data(name.utf8)
        result.append(tag(field: 1, wireType: 2))
        result.append(varint(UInt64(nameBytes.count)))
        result.append(nameBytes)

        if let legacyZipFilename {
            result.append(tag(field: 255, wireType: 0))
            result.append(varint(UInt64(legacyZipFilename)))
        }
        return result
    }

    private static func tag(field: Int, wireType: Int) -> Data {
        varint(UInt64((field << 3) | wireType))
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }
}
