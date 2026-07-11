import GRDB
import Foundation

/// Drives one study session for a deck (PRD §7.4): holds the ordered queue of
/// cards built by `StudyQueueService`, renders the current card, persists
/// grades through `FSRSScheduler`, and supports undoing the last grade.
///
/// Not `Sendable` — intended to be owned by a single `@MainActor` view model.
public final class StudySession {
    public enum StudySessionError: Error, Equatable {
        case missingNote(String)
        case missingNoteType(String)
        case missingTemplate(noteTypeID: String, ordinal: Int)
    }

    private struct UndoEntry {
        let previousCard: Card
        let insertedReviewLogID: String
    }

    private let database: AppDatabase
    private let scheduler: FSRSScheduler
    private let now: () -> Date
    /// How far into the future a just-graded learning/relearning card's next
    /// due date can be and still reappear later in *this* session, rather
    /// than waiting for a future session. Mirrors the fact that FSRS learning
    /// steps are typically minutes, not days.
    private let requeueWindow: TimeInterval
    private var undoStack: [UndoEntry] = []

    public private(set) var queue: [Card]
    public private(set) var reviewedCount = 0
    public private(set) var newIntroducedCount = 0

    public init(
        database: AppDatabase,
        deckID: String,
        scheduler: FSRSScheduler = FSRSScheduler(),
        now: @escaping () -> Date = Date.init,
        requeueWindow: TimeInterval = 20 * 60
    ) throws {
        self.database = database
        self.scheduler = scheduler
        self.now = now
        self.requeueWindow = requeueWindow
        self.queue = try database.dbWriter.read { db in
            try StudyQueueService.buildQueue(deckID: deckID, now: now(), in: db)
        }
    }

    public var currentCard: Card? { queue.first }
    public var isComplete: Bool { queue.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }

    /// Renders the current card's question/answer HTML, or `nil` if the
    /// session is complete.
    public func renderCurrent() throws -> (question: String, answer: String)? {
        guard let card = queue.first else { return nil }
        return try database.dbWriter.read { db in
            let (note, fields, template) = try Self.loadRenderInputs(card: card, in: db)
            return try CardRenderer.render(note: note, fields: fields, template: template, clozeOrdinal: card.templateOrdinal)
        }
    }

    /// A short interval label per rating (e.g. `"10m"`, `"3d"`) previewing
    /// what each grade button would do to the current card, without applying it.
    public func intervalPreviews(referenceNow: Date? = nil) -> [Rating: String] {
        guard let card = queue.first else { return [:] }
        let reviewDate = referenceNow ?? now()
        var result: [Rating: String] = [:]
        for rating in Rating.allCases {
            let (updated, _) = scheduler.review(card: card, rating: rating, reviewDate: reviewDate)
            result[rating] = IntervalFormatting.short(from: reviewDate, to: updated.due)
        }
        return result
    }

    /// Grades the current card, persists the updated card + review log, and
    /// advances the queue. Returns the new current card, if any remain.
    @discardableResult
    public func grade(_ rating: Rating) throws -> Card? {
        guard let card = queue.first else { return nil }
        let reviewDate = now()
        let (updatedCard, log) = scheduler.review(card: card, rating: rating, reviewDate: reviewDate)

        try database.dbWriter.write { db in
            try updatedCard.update(db)
            try log.insert(db)
            try db.enqueueSyncChange(.card, recordID: updatedCard.id)
            try db.enqueueSyncChange(.reviewLog, recordID: log.id)
        }

        undoStack.append(UndoEntry(previousCard: card, insertedReviewLogID: log.id))
        queue.removeFirst()
        reviewedCount += 1
        if card.state == .new { newIntroducedCount += 1 }

        if updatedCard.state != .review, updatedCard.due <= reviewDate.addingTimeInterval(requeueWindow) {
            let insertIndex = queue.firstIndex(where: { $0.due > updatedCard.due }) ?? queue.count
            queue.insert(updatedCard, at: insertIndex)
        }

        return queue.first
    }

    /// Reverts the last grade: restores the card's prior scheduling state in
    /// the database, deletes the review log it produced, and puts the card
    /// back at the front of the queue. Returns `false` if there was nothing to undo.
    @discardableResult
    public func undoLast() throws -> Bool {
        guard let entry = undoStack.popLast() else { return false }

        try database.dbWriter.write { db in
            try entry.previousCard.update(db)
            try db.execute(sql: "DELETE FROM reviewLog WHERE id = ?", arguments: [entry.insertedReviewLogID])
            try db.enqueueSyncChange(.card, recordID: entry.previousCard.id)
            try db.enqueueSyncChange(.reviewLog, recordID: entry.insertedReviewLogID, isDeletion: true)
        }

        queue.removeAll { $0.id == entry.previousCard.id }
        queue.insert(entry.previousCard, at: 0)
        reviewedCount -= 1
        if entry.previousCard.state == .new { newIntroducedCount -= 1 }
        return true
    }

    // MARK: - Rendering lookups

    private static func loadRenderInputs(card: Card, in db: Database) throws -> (Note, [Field], CardTemplate) {
        guard let note = try Note.fetchOne(db, key: card.noteID) else {
            throw StudySessionError.missingNote(card.noteID)
        }
        guard let noteType = try NoteType.fetchOne(db, key: note.noteTypeID) else {
            throw StudySessionError.missingNoteType(note.noteTypeID)
        }
        let fields = try Field.filter(Column("noteTypeID") == noteType.id).fetchAll(db)

        // Cloze note types have exactly one CardTemplate row (ordinal 0);
        // `card.templateOrdinal` there is the cloze number - 1, passed through
        // to `CardRenderer` as `clozeOrdinal`, not a distinct template to look
        // up. Basic-style note types have one CardTemplate row per generated
        // card, so `card.templateOrdinal` addresses it directly.
        let templateOrdinal = noteType.kind == .cloze ? 0 : card.templateOrdinal
        guard let template = try CardTemplate
            .filter(Column("noteTypeID") == noteType.id)
            .filter(Column("ordinal") == templateOrdinal)
            .fetchOne(db)
        else {
            throw StudySessionError.missingTemplate(noteTypeID: noteType.id, ordinal: templateOrdinal)
        }
        return (note, fields, template)
    }
}
