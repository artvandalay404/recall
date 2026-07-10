import Foundation
import Observation
import RecallCore

@MainActor
@Observable
final class NoteEditorViewModel {
    private let database: AppDatabase
    /// Only used by the create-mode path; edit mode derives the deck from
    /// the note's existing cards instead (a note's target deck can't change
    /// from the editor, only from moving individual cards, which isn't v1 scope).
    private let deckID: String?
    private var existingNote: Note?

    var availableNoteTypes: [NoteType] = []
    var selectedNoteType: NoteType
    var fields: [Field] = []
    var fieldValues: [String] = []
    var tagsText = ""
    var errorMessage: String?

    var isEditing: Bool { existingNote != nil }

    /// Where a note's cloze deletions live, by the built-in Cloze note
    /// type's field-ordering convention (Text is always field 0). `nil` for
    /// non-cloze note types.
    var clozeFieldIndex: Int? {
        selectedNoteType.kind == .cloze ? 0 : nil
    }

    /// Create mode: starts on Basic, lets the caller switch note type before saving.
    init(database: AppDatabase, deckID: String) {
        self.database = database
        self.deckID = deckID
        let basic = try? database.noteType(id: BuiltInNoteTypes.basicNoteTypeID)
        self.selectedNoteType = basic ?? NoteType(id: BuiltInNoteTypes.basicNoteTypeID, name: "Basic", kind: .basic)
        loadAvailableNoteTypes()
        loadFields(for: selectedNoteType, resettingValues: true)
    }

    /// Edit mode: fixed to the note's existing type.
    init(database: AppDatabase, note: Note, noteType: NoteType) {
        self.database = database
        self.deckID = nil
        self.existingNote = note
        self.selectedNoteType = noteType
        self.tagsText = note.tags.joined(separator: " ")
        loadFields(for: noteType, resettingValues: false)
        self.fieldValues = note.fieldValues
    }

    func selectNoteType(_ noteType: NoteType) {
        guard !isEditing, noteType.id != selectedNoteType.id else { return }
        selectedNoteType = noteType
        loadFields(for: noteType, resettingValues: true)
    }

    func nextClozeNumber() -> Int {
        let text = fieldValues.first ?? ""
        return (CardRenderer.clozeNumbers(in: text).max() ?? 0) + 1
    }

    @discardableResult
    func save() -> Bool {
        let tags = tagsText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        do {
            if let existing = existingNote {
                existingNote = try database.updateNote(existing, fieldValues: fieldValues, tags: tags)
            } else if let deckID {
                existingNote = try database.createNote(
                    deckID: deckID,
                    noteTypeID: selectedNoteType.id,
                    fieldValues: fieldValues,
                    tags: tags
                )
            }
            return true
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    @discardableResult
    func delete() -> Bool {
        guard let existing = existingNote else { return true }
        do {
            try database.deleteNote(existing)
            return true
        } catch {
            errorMessage = "Couldn't delete this note: \(error.localizedDescription)"
            return false
        }
    }

    private func loadAvailableNoteTypes() {
        do {
            availableNoteTypes = try database.allNoteTypes()
        } catch {
            errorMessage = "Couldn't load note types: \(error.localizedDescription)"
        }
    }

    private func loadFields(for noteType: NoteType, resettingValues: Bool) {
        do {
            fields = try database.fields(forNoteType: noteType.id)
            if resettingValues {
                fieldValues = Array(repeating: "", count: fields.count)
            }
        } catch {
            errorMessage = "Couldn't load fields: \(error.localizedDescription)"
        }
    }

    private static func describe(_ error: Error) -> String {
        if let noteEditingError = error as? NoteEditingError, let description = noteEditingError.errorDescription {
            return description
        }
        return "Couldn't save this note: \(error.localizedDescription)"
    }
}
