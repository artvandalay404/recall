import Foundation

/// Finds media filenames referenced by a note's field HTML — the `src`
/// attribute of an `<img>` or `<audio>` tag, matching the two conventions
/// `NoteEditorView` and `ApkgImporter` both write (PRD §7.5, §7.7, §7.9).
/// Used at note-save time to register each filename for CloudKit sync
/// (PRD §7.8) via `MediaAsset`.
enum MediaReferenceScanner {
    private static let regex = try! NSRegularExpression(pattern: "src=\"([^\"]+)\"")

    static func filenames(in fieldValues: [String]) -> Set<String> {
        var result: Set<String> = []
        for value in fieldValues {
            let fullRange = NSRange(value.startIndex..., in: value)
            for match in regex.matches(in: value, range: fullRange) {
                guard let capturedRange = Range(match.range(at: 1), in: value) else { continue }
                result.insert(String(value[capturedRange]))
            }
        }
        return result
    }
}
