import Testing
import Foundation
@testable import RecallCore

/// Regression vectors ported from the FSRS reference implementation's own
/// test suite: https://github.com/open-spaced-repetition/py-fsrs
/// (`tests/test_basic.py`), run against `fsrs==...` DEFAULT_PARAMETERS.
///
/// `py-fsrs` starts a brand-new `Card` directly in its `Learning` state
/// (step 0, stability nil); this port instead starts new cards in the
/// distinct `.new` state (see `CardState`), so state assertions on a
/// never-reviewed card differ from the Python originals accordingly —
/// every numeric (interval/stability/difficulty) assertion is unchanged.
struct FSRSSchedulerTests {
    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 86400).rounded(.towardZero))
    }

    private func makeCard(due: Date = Date()) -> Card {
        Card(noteID: "note-1", deckID: "deck-1", templateOrdinal: 0, due: due)
    }

    @Test func reviewCardIntervalHistoryMatchesReferenceVector() {
        let scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard(due: utcDate(2022, 11, 29, 12, 30, 0))
        var reviewDate = card.due

        let ratings: [Rating] = [.good, .good, .good, .good, .good, .good, .again, .again, .good, .good, .good, .good, .good]
        var intervalHistory: [Int] = []

        for rating in ratings {
            let (updated, _) = scheduler.review(card: card, rating: rating, reviewDate: reviewDate)
            intervalHistory.append(daysBetween(updated.lastReview!, updated.due))
            reviewDate = updated.due
            card = updated
        }

        #expect(intervalHistory == [0, 2, 11, 46, 163, 498, 0, 0, 2, 4, 7, 12, 21])
    }

    @Test func repeatedEasyReviewsClampDifficultyToMinimum() {
        let scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard()
        let base = utcDate(2022, 11, 29, 12, 30, 0)

        for i in 0..<10 {
            let reviewDate = base.addingTimeInterval(Double(i) / 1_000_000)
            let (updated, _) = scheduler.review(card: card, rating: .easy, reviewDate: reviewDate)
            card = updated
        }

        #expect(abs(card.difficulty! - 1.0) < 1e-9)
    }

    @Test func memoStateMatchesReferenceVector() {
        let scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard()
        var reviewDate = utcDate(2022, 11, 29, 12, 30, 0)

        let ratings: [Rating] = [.again, .good, .good, .good, .good, .good]
        let elapsedDaysBeforeEachReview = [0, 0, 1, 3, 8, 21]

        for (rating, elapsedDays) in zip(ratings, elapsedDaysBeforeEachReview) {
            reviewDate = reviewDate.addingTimeInterval(Double(elapsedDays) * 86400)
            let (updated, _) = scheduler.review(card: card, rating: rating, reviewDate: reviewDate)
            card = updated
        }

        #expect(abs(card.stability! - 53.62691) < 1e-4)
        #expect(abs(card.difficulty! - 6.3574867) < 1e-4)
    }

    @Test func retrievabilityAndStateTransitions() {
        let scheduler = FSRSScheduler()
        var card = makeCard()

        #expect(card.state == .new)
        #expect(scheduler.retrievability(of: card) == 0)

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .learning)
        #expect((0...1).contains(scheduler.retrievability(of: card, at: card.due)))

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .review)
        #expect((0...1).contains(scheduler.retrievability(of: card, at: card.due)))

        (card, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(card.state == .relearning)
        #expect((0...1).contains(scheduler.retrievability(of: card, at: card.due)))
    }

    @Test func goodRatingAdvancesThroughLearningStepsThenGraduates() {
        let scheduler = FSRSScheduler()
        let createdAt = utcDate(2024, 1, 1, 9, 0, 0)
        var card = makeCard(due: createdAt)

        var (updated, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(updated.state == .learning)
        #expect(updated.step == 1)
        #expect(abs(updated.due.timeIntervalSince(createdAt) - 600) < 1)
        card = updated

        let dueAfterFirstReview = card.due
        (updated, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(updated.state == .review)
        #expect(updated.step == nil)
        #expect(updated.due.timeIntervalSince(dueAfterFirstReview) >= 86400)
    }

    @Test func againRatingStaysInLearningStepZero() {
        let scheduler = FSRSScheduler()
        let card = makeCard()

        let (updated, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(updated.state == .learning)
        #expect(updated.step == 0)
        #expect(abs(updated.due.timeIntervalSince(card.due) - 60) < 1)
    }

    @Test func hardRatingAveragesFirstTwoLearningSteps() {
        let scheduler = FSRSScheduler()
        let card = makeCard()

        let (updated, _) = scheduler.review(card: card, rating: .hard, reviewDate: card.due)
        #expect(updated.state == .learning)
        #expect(updated.step == 0)
        #expect(abs(updated.due.timeIntervalSince(card.due) - 330) < 1)
    }

    @Test func easyRatingGraduatesImmediatelyFromLearning() {
        let scheduler = FSRSScheduler()
        let card = makeCard()

        let (updated, _) = scheduler.review(card: card, rating: .easy, reviewDate: card.due)
        #expect(updated.state == .review)
        #expect(updated.step == nil)
        #expect(updated.due.timeIntervalSince(card.due) >= 86400)
    }

    @Test func reviewStateFallsBackToRelearningOnAgain() {
        let scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard()

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .review)
        #expect(card.step == nil)

        let prevDue = card.due
        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .review)
        #expect(card.due.timeIntervalSince(prevDue) >= 86400)

        let prevDue2 = card.due
        (card, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(card.state == .relearning)
        #expect(abs(card.due.timeIntervalSince(prevDue2) - 600) < 1)
    }

    @Test func relearningGraduatesBackToReviewOnGood() {
        let scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard()

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        (card, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(card.state == .relearning)
        #expect(card.step == 0)

        (card, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(card.state == .relearning)
        #expect(card.step == 0)

        let prevDue = card.due
        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .review)
        #expect(card.step == nil)
        #expect(card.due.timeIntervalSince(prevDue) >= 86400)
    }

    @Test func stabilityNeverDropsBelowMinimum() {
        let scheduler = FSRSScheduler()
        var card = makeCard()

        for _ in 0..<1000 {
            let reviewDate = card.due.addingTimeInterval(86400)
            let (updated, _) = scheduler.review(card: card, rating: .again, reviewDate: reviewDate)
            #expect(updated.stability! >= FSRSParameters.stabilityMin)
            card = updated
        }
    }

    @Test func respectsMaximumInterval() {
        let maxDays = 100
        let scheduler = FSRSScheduler(maximumIntervalDays: maxDays, enableFuzzing: false)
        var card = makeCard()

        for rating: Rating in [.easy, .good, .easy, .good] {
            let (updated, _) = scheduler.review(card: card, rating: rating, reviewDate: card.due)
            if updated.state == .review, let last = updated.lastReview {
                let days = updated.due.timeIntervalSince(last) / 86400
                #expect(days <= Double(maxDays) + 0.001)
            }
            card = updated
        }
    }

    @Test func noLearningStepsGraduatesImmediately() {
        let scheduler = FSRSScheduler(learningSteps: [], enableFuzzing: false)
        let card = makeCard()

        let (updated, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(updated.state == .review)
        #expect(updated.due.timeIntervalSince(updated.lastReview!) >= 86400)
    }

    @Test func noRelearningStepsStaysInReviewOnAgain() {
        let scheduler = FSRSScheduler(relearningSteps: [], enableFuzzing: false)
        var card = makeCard()

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .learning)

        (card, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
        #expect(card.state == .review)

        (card, _) = scheduler.review(card: card, rating: .again, reviewDate: card.due)
        #expect(card.state == .review)
    }

    @Test func fuzzingProducesVariationAcrossRepeatedReviews() {
        var scheduler = FSRSScheduler(enableFuzzing: false)
        var card = makeCard()

        for rating: Rating in [.good, .good, .good] {
            (card, _) = scheduler.review(card: card, rating: rating, reviewDate: card.due)
        }
        #expect(card.state == .review)

        scheduler.enableFuzzing = true
        var observedDays = Set<Int>()
        for _ in 0..<25 {
            let (updated, _) = scheduler.review(card: card, rating: .good, reviewDate: card.due)
            observedDays.insert(daysBetween(card.due, updated.due))
        }
        #expect(observedDays.count > 1)
    }

    @Test func parameterValidationRejectsWeightsOutOfBounds() {
        #expect(FSRSParameters.default.isValid)

        var tooHigh = FSRSParameters.defaultWeights
        tooHigh[6] = 100
        #expect(!FSRSParameters(weights: tooHigh).isValid)
    }
}
