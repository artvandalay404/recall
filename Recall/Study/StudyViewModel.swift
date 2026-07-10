import Foundation
import Observation
import RecallCore

@MainActor
@Observable
final class StudyViewModel {
    enum Phase {
        case question
        case answer
    }

    private let session: StudySession

    var phase: Phase = .question
    var questionHTML = ""
    var answerHTML = ""
    var intervalPreviews: [Rating: String] = [:]
    var errorMessage: String?

    var isComplete: Bool { session.isComplete }
    var remainingCount: Int { session.queue.count }
    var canUndo: Bool { session.canUndo }

    init(database: AppDatabase, deckID: String) throws {
        session = try StudySession(database: database, deckID: deckID)
        loadCurrent()
    }

    func reveal() {
        phase = .answer
    }

    func grade(_ rating: Rating) {
        do {
            try session.grade(rating)
            phase = .question
            loadCurrent()
        } catch {
            errorMessage = "Couldn't save that review: \(error.localizedDescription)"
        }
    }

    func undo() {
        do {
            _ = try session.undoLast()
            phase = .question
            loadCurrent()
        } catch {
            errorMessage = "Couldn't undo: \(error.localizedDescription)"
        }
    }

    private func loadCurrent() {
        do {
            if let rendered = try session.renderCurrent() {
                questionHTML = rendered.question
                answerHTML = rendered.answer
            } else {
                questionHTML = ""
                answerHTML = ""
            }
            intervalPreviews = session.intervalPreviews()
        } catch {
            errorMessage = "Couldn't render this card: \(error.localizedDescription)"
        }
    }
}
