import CZstd
import Foundation

/// One-shot Zstandard decompression, backed by the vendored decoder-only
/// sources in the `CZstd` target (PRD §7.7 — newer `.apkg`/`.colpkg` exports
/// whole-file zstd-compress `collection.anki21b` and, individually,
/// each media entry).
///
/// Only decoding is vendored (no encoder) since importing is this app's only
/// use of zstd. Every frame this importer reads was produced by Anki's own
/// exporter, which always writes its pledged content size into the frame
/// header, so a single `ZSTD_decompress` call (no streaming) suffices.
public enum ZstdDecoder {
    public enum ZstdError: Error, Equatable {
        case unknownContentSize
        case decodeFailed(String)
    }

    public static func decompress(_ data: Data) throws -> Data {
        let contentSize = data.withUnsafeBytes { pointer in
            ZSTD_getFrameContentSize(pointer.baseAddress, data.count)
        }
        guard contentSize != ZSTD_CONTENTSIZE_ERROR, contentSize != ZSTD_CONTENTSIZE_UNKNOWN else {
            throw ZstdError.unknownContentSize
        }

        var output = Data(count: Int(contentSize))
        let writtenSize = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                ZSTD_decompress(destination.baseAddress, destination.count, source.baseAddress, data.count)
            }
        }
        guard ZSTD_isError(writtenSize) == 0 else {
            let message = String(cString: ZSTD_getErrorName(writtenSize))
            throw ZstdError.decodeFailed(message)
        }
        return output
    }
}
