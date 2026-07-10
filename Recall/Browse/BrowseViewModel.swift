import Foundation
import Observation
import RecallCore

@MainActor
@Observable
final class BrowseViewModel {
    private let database: AppDatabase

    var searchText: String = "" {
        didSet { refresh() }
    }
    var summaries: [AppDatabase.NoteSummary] = []
    var errorMessage: String?

    init(database: AppDatabase) {
        self.database = database
        refresh()
    }

    func refresh() {
        do {
            summaries = try database.searchNotes(query: searchText)
        } catch {
            errorMessage = "Couldn't load notes: \(error.localizedDescription)"
        }
    }

    func delete(_ summary: AppDatabase.NoteSummary) {
        do {
            try database.deleteNote(summary.note)
            refresh()
        } catch {
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}
