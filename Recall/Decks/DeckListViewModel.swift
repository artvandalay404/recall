import Foundation
import Observation
import RecallCore

@MainActor
@Observable
final class DeckListViewModel {
    private let database: AppDatabase

    var rows: [AppDatabase.DeckRow] = []
    var errorMessage: String?

    init(database: AppDatabase) {
        self.database = database
    }

    func refresh() {
        do {
            rows = try database.rootDeckRows()
        } catch {
            errorMessage = "Couldn't load decks: \(error.localizedDescription)"
        }
    }

    func createDeck(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try database.createDeck(name: trimmed)
            refresh()
        } catch {
            errorMessage = "Couldn't create deck: \(error.localizedDescription)"
        }
    }

    func rename(_ deck: Deck, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try database.renameDeck(deck, to: trimmed)
            refresh()
        } catch {
            errorMessage = "Couldn't rename deck: \(error.localizedDescription)"
        }
    }

    func delete(_ deck: Deck) {
        do {
            try database.deleteDeck(deck)
            refresh()
        } catch {
            errorMessage = "\"\(deck.name)\" still has cards — delete or move them first."
        }
    }
}
