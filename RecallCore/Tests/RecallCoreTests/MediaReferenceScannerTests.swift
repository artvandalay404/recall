import Testing
@testable import RecallCore

struct MediaReferenceScannerTests {
    @Test func findsAnImageReference() {
        let filenames = MediaReferenceScanner.filenames(in: ["<img src=\"abc123.jpg\">"])
        #expect(filenames == ["abc123.jpg"])
    }

    @Test func findsAnAudioReference() {
        let filenames = MediaReferenceScanner.filenames(in: ["<audio controls src=\"def456.mp3\"></audio>"])
        #expect(filenames == ["def456.mp3"])
    }

    @Test func findsMultipleReferencesAcrossFieldsWithoutDuplicates() {
        let filenames = MediaReferenceScanner.filenames(in: [
            "front <img src=\"a.jpg\">",
            "back <audio controls src=\"b.mp3\"></audio><img src=\"a.jpg\">",
        ])
        #expect(filenames == ["a.jpg", "b.mp3"])
    }

    @Test func plainTextWithNoMediaReturnsEmpty() {
        #expect(MediaReferenceScanner.filenames(in: ["just text", ""]).isEmpty)
    }
}
