import Foundation
import RecallCore

#if DEBUG
/// Seeds one sample deck with real Basic + Cloze content on first launch, so
/// the study loop (deck list → session → grading) is exercisable in the
/// simulator before the phase-3 field editor and phase-4 importer exist.
/// Only runs when the library has no decks at all — never touches a library
/// the user has already put content into.
enum DemoSeeder {
    static func seedIfNeeded(in database: AppDatabase) {
        do {
            guard try database.rootDeckRows().isEmpty else { return }

            let deck = try database.createDeck(name: "Sample: Spanish Basics")

            let basics: [(front: String, back: String)] = [
                ("hola", "hello"),
                ("gracias", "thank you"),
                ("por favor", "please"),
                ("buenos días", "good morning"),
                ("¿Cómo estás?", "How are you?"),
                ("adiós", "goodbye"),
            ]
            for pair in basics {
                try database.addBasicNote(deckID: deck.id, front: pair.front, back: pair.back)
            }

            try database.addClozeNote(
                deckID: deck.id,
                text: "The capital of Spain is {{c1::Madrid}}, and the capital of France is {{c2::Paris}}.",
                extra: "Both are in Western Europe."
            )
            try database.addClozeNote(
                deckID: deck.id,
                text: "\"Buenos días\" means {{c1::good morning}} in Spanish.",
                extra: ""
            )
        } catch {
            assertionFailure("Demo seeding failed: \(error)")
        }
    }
}
#endif
