import Foundation

/// A minimal protobuf wire-format reader — just enough to pull specific
/// fields out of the small, fixed set of messages Anki embeds in `.apkg` /
/// `.colpkg` packages (PRD §7.7). Not a general protobuf library: no schema
/// validation, no support for generating messages, just sequential
/// tag/value scanning with unknown fields skipped.
///
/// Wire format reference: https://protobuf.dev/programming-guides/encoding/
struct ProtobufWireReader {
    enum WireError: Error, Equatable {
        case truncated
        case malformedVarint
        case unsupportedWireType(Int)
    }

    private let bytes: [UInt8]
    private var offset: Int = 0

    init(_ data: Data) {
        self.bytes = Array(data)
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < bytes.count else { throw WireError.truncated }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift < 64 else { throw WireError.malformedVarint }
        }
        return result
    }

    /// Returns `nil` once every byte has been consumed.
    mutating func readTag() throws -> (fieldNumber: Int, wireType: Int)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = try Int(readVarint())
        guard length >= 0, offset + length <= bytes.count else { throw WireError.truncated }
        let slice = bytes[offset..<offset + length]
        offset += length
        return Data(slice)
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0: _ = try readVarint()
        case 1: guard offset + 8 <= bytes.count else { throw WireError.truncated }; offset += 8
        case 2: _ = try readLengthDelimited()
        case 5: guard offset + 4 <= bytes.count else { throw WireError.truncated }; offset += 4
        default: throw WireError.unsupportedWireType(wireType)
        }
    }
}
