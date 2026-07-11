import Foundation
import Observation
import RecallCore

/// Drives an `.apkg` / `.colpkg` import (PRD §7.7) from the deck list:
/// picking a file kicks off `ApkgImporter` on a background task (an import
/// can mean parsing thousands of cards' worth of SQLite + media + review
/// history, which would otherwise block the UI), then reports a summary or
/// error back on the main actor.
@MainActor
@Observable
final class ImportViewModel {
    private let database: AppDatabase
    private let mediaStore: MediaStore

    var isImporting = false
    var summary: ApkgImportSummary?
    var errorMessage: String?

    init(database: AppDatabase, mediaStore: MediaStore) {
        self.database = database
        self.mediaStore = mediaStore
    }

    func importDeck(from url: URL) {
        guard !isImporting else { return }
        isImporting = true
        summary = nil
        errorMessage = nil

        let database = self.database
        let mediaStore = self.mediaStore
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: Outcome
            do {
                outcome = .success(try ApkgImporter.importDeck(from: url, into: database, mediaStore: mediaStore))
            } catch {
                outcome = .failure(Self.describe(error))
            }
            await MainActor.run {
                guard let self else { return }
                self.isImporting = false
                switch outcome {
                case .success(let summary): self.summary = summary
                case .failure(let message): self.errorMessage = message
                }
            }
        }
    }

    private enum Outcome: Sendable {
        case success(ApkgImportSummary)
        case failure(String)
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if let importError = error as? ApkgImportError, let description = importError.errorDescription {
            return description
        }
        return "Couldn't import this deck: \(error.localizedDescription)"
    }
}
