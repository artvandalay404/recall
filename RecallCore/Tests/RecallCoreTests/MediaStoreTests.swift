import Testing
import Foundation
@testable import RecallCore

struct MediaStoreTests {
    private func makeStore() throws -> MediaStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try MediaStore(directory: directory)
    }

    @Test func importDataWritesAFileWithTheGivenExtension() throws {
        let store = try makeStore()
        let filename = try store.importData(Data("hello".utf8), extension: "txt")

        #expect(filename.hasSuffix(".txt"))
        let contents = try String(contentsOf: store.url(for: filename), encoding: .utf8)
        #expect(contents == "hello")
    }

    @Test func importDataWithNoExtensionOmitsTheDot() throws {
        let store = try makeStore()
        let filename = try store.importData(Data("hello".utf8), extension: "")

        #expect(!filename.contains("."))
    }

    @Test func importFileCopiesFromASourceURL() throws {
        let store = try makeStore()
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try Data("fake image bytes".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let filename = try store.importFile(from: sourceURL)

        #expect(filename.hasSuffix(".jpg"))
        let contents = try Data(contentsOf: store.url(for: filename))
        #expect(contents == Data("fake image bytes".utf8))
    }

    @Test func distinctImportsGetDistinctFilenames() throws {
        let store = try makeStore()
        let first = try store.importData(Data("a".utf8), extension: "png")
        let second = try store.importData(Data("b".utf8), extension: "png")

        #expect(first != second)
    }
}
