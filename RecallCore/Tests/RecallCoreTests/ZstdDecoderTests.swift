import Testing
import Foundation
@testable import RecallCore

/// Fixture generated via the system `zstd` CLI (`zstd -19 plain.txt -o
/// plain.txt.zst`) — `CZstd` only vendors lib/common + lib/decompress (no
/// encoder), so the fixture is precomputed rather than round-tripped through
/// our own code.
struct ZstdDecoderTests {
    @Test func decompressesAPrecompressedFixture() throws {
        let compressedHex = "28b52ffd242c61010068656c6c6f20776f726c642c20746869732069732061207a73746420726f756e642074726970207465737421dec49eec"
        let compressed = Data(hex: compressedHex)

        let decompressed = try ZstdDecoder.decompress(compressed)

        #expect(String(decoding: decompressed, as: UTF8.self) == "hello world, this is a zstd round trip test!")
    }

    @Test func throwsOnGarbageInput() {
        #expect(throws: Error.self) {
            try ZstdDecoder.decompress(Data("not a zstd frame".utf8))
        }
    }
}

extension Data {
    init(hex: String) {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self = data
    }
}
