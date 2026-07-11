import Foundation

/// The FSRS-6 spaced-repetition scheduler.
///
/// This is a faithful Swift port of the reference implementation at
/// https://github.com/open-spaced-repetition/py-fsrs (`fsrs/scheduler.py`),
/// adapted to an explicit `.new` card state (see `CardState`) so the app can
/// distinguish never-studied cards from cards mid learning-steps.
public struct FSRSScheduler: Sendable {
    public var parameters: FSRSParameters
    public var desiredRetention: Double
    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    public var maximumIntervalDays: Int
    public var enableFuzzing: Bool

    private let decay: Double
    private let factor: Double

    public init(
        parameters: FSRSParameters = .default,
        desiredRetention: Double = 0.9,
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        maximumIntervalDays: Int = 36_500,
        enableFuzzing: Bool = true
    ) {
        self.parameters = parameters
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumIntervalDays = maximumIntervalDays
        self.enableFuzzing = enableFuzzing

        self.decay = -parameters[20]
        self.factor = pow(0.9, 1 / self.decay) - 1
    }

    // MARK: - Retrievability

    /// The predicted probability `card` is correctly recalled at `date`.
    public func retrievability(of card: Card, at date: Date = Date()) -> Double {
        guard let lastReview = card.lastReview, let stability = card.stability else {
            return 0
        }
        let elapsedDays = max(0, Self.daysBetween(lastReview, date))
        return pow(1 + factor * Double(elapsedDays) / stability, decay)
    }

    // MARK: - Reviewing

    /// Applies `rating` to `card` as of `reviewDate`, returning the updated
    /// card and the review log entry to append.
    public func review(
        card: Card,
        rating: Rating,
        reviewDate: Date = Date(),
        randomSource: () -> Double = { Double.random(in: 0..<1) }
    ) -> (card: Card, reviewLog: ReviewLog) {
        var card = card
        let daysSinceLastReview = card.lastReview.map { Self.daysBetween($0, reviewDate) }

        var interval: TimeInterval

        switch card.state {
        case .new:
            card.stability = initialStability(rating: rating)
            card.difficulty = initialDifficulty(rating: rating, clamp: true)
            card.step = 0
            (card.state, card.step, interval) = stepOutcome(
                currentStep: 0, rating: rating, steps: learningSteps, graduatedState: .learning, stability: card.stability!
            )

        case .learning:
            let oldDifficulty = card.difficulty!
            card.stability = nextStability(
                oldStability: card.stability!, oldDifficulty: oldDifficulty, rating: rating,
                daysSinceLastReview: daysSinceLastReview, card: card, reviewDate: reviewDate
            )
            card.difficulty = nextDifficulty(difficulty: oldDifficulty, rating: rating)
            (card.state, card.step, interval) = stepOutcome(
                currentStep: card.step!, rating: rating, steps: learningSteps, graduatedState: .learning, stability: card.stability!
            )

        case .review:
            let oldDifficulty = card.difficulty!
            card.stability = nextStability(
                oldStability: card.stability!, oldDifficulty: oldDifficulty, rating: rating,
                daysSinceLastReview: daysSinceLastReview, card: card, reviewDate: reviewDate
            )
            card.difficulty = nextDifficulty(difficulty: oldDifficulty, rating: rating)

            switch rating {
            case .again where !relearningSteps.isEmpty:
                card.state = .relearning
                card.step = 0
                interval = relearningSteps[0]
            default:
                card.state = .review
                card.step = nil
                interval = Double(nextIntervalDays(stability: card.stability!)) * 86400
            }

        case .relearning:
            let oldDifficulty = card.difficulty!
            card.stability = nextStability(
                oldStability: card.stability!, oldDifficulty: oldDifficulty, rating: rating,
                daysSinceLastReview: daysSinceLastReview, card: card, reviewDate: reviewDate
            )
            card.difficulty = nextDifficulty(difficulty: oldDifficulty, rating: rating)
            (card.state, card.step, interval) = stepOutcome(
                currentStep: card.step!, rating: rating, steps: relearningSteps, graduatedState: .relearning, stability: card.stability!
            )
        }

        if enableFuzzing && card.state == .review {
            interval = Double(fuzzedIntervalDays(Int((interval / 86400).rounded()), randomSource: randomSource)) * 86400
        }

        card.due = reviewDate.addingTimeInterval(interval)
        card.lastReview = reviewDate
        card.updatedAt = reviewDate

        let reviewLog = ReviewLog(cardID: card.id, rating: rating, reviewedAt: reviewDate)
        return (card, reviewLog)
    }

    /// Shared step-transition logic for the Learning and Relearning states:
    /// walk `steps` according to `rating`, or graduate to `.review` once the
    /// steps are exhausted (mirrors py-fsrs's identical inline blocks for
    /// `State.Learning` and `State.Relearning`).
    private func stepOutcome(
        currentStep: Int, rating: Rating, steps: [TimeInterval], graduatedState: CardState, stability: Double
    ) -> (state: CardState, step: Int?, interval: TimeInterval) {
        let exhausted = steps.isEmpty || (currentStep >= steps.count && rating != .again)
        if exhausted {
            let days = nextIntervalDays(stability: stability)
            return (.review, nil, Double(days) * 86400)
        }

        switch rating {
        case .again:
            return (graduatedState, 0, steps[0])

        case .hard:
            if currentStep == 0 && steps.count == 1 {
                return (graduatedState, currentStep, steps[0] * 1.5)
            } else if currentStep == 0 && steps.count >= 2 {
                return (graduatedState, currentStep, (steps[0] + steps[1]) / 2.0)
            } else {
                return (graduatedState, currentStep, steps[currentStep])
            }

        case .good:
            if currentStep + 1 == steps.count {
                let days = nextIntervalDays(stability: stability)
                return (.review, nil, Double(days) * 86400)
            } else {
                return (graduatedState, currentStep + 1, steps[currentStep + 1])
            }

        case .easy:
            let days = nextIntervalDays(stability: stability)
            return (.review, nil, Double(days) * 86400)
        }
    }

    // MARK: - Stability / difficulty formulas

    private func initialStability(rating: Rating) -> Double {
        max(parameters[rating.rawValue - 1], FSRSParameters.stabilityMin)
    }

    private func initialDifficulty(rating: Rating, clamp: Bool) -> Double {
        let difficulty = parameters[4] - (exp(parameters[5] * Double(rating.rawValue - 1))) + 1
        return clamp ? clampDifficulty(difficulty) : difficulty
    }

    private func nextDifficulty(difficulty: Double, rating: Rating) -> Double {
        let deltaDifficulty = -(parameters[6] * Double(rating.rawValue - 3))
        let dampedDelta = (10.0 - difficulty) * deltaDifficulty / 9.0
        let arg1 = initialDifficulty(rating: .easy, clamp: false)
        let arg2 = difficulty + dampedDelta
        let next = parameters[7] * arg1 + (1 - parameters[7]) * arg2
        return clampDifficulty(next)
    }

    private func nextStability(
        oldStability: Double, oldDifficulty: Double, rating: Rating,
        daysSinceLastReview: Int?, card: Card, reviewDate: Date
    ) -> Double {
        if let days = daysSinceLastReview, days < 1 {
            return shortTermStability(stability: oldStability, rating: rating)
        }

        let r = retrievability(of: card, at: reviewDate)
        let next: Double
        switch rating {
        case .again:
            next = nextForgetStability(difficulty: oldDifficulty, stability: oldStability, retrievability: r)
        case .hard, .good, .easy:
            next = nextRecallStability(difficulty: oldDifficulty, stability: oldStability, retrievability: r, rating: rating)
        }
        return max(next, FSRSParameters.stabilityMin)
    }

    private func shortTermStability(stability: Double, rating: Rating) -> Double {
        var increase = exp(parameters[17] * (Double(rating.rawValue - 3) + parameters[18])) * pow(stability, -parameters[19])
        if rating == .good || rating == .easy {
            increase = max(increase, 1.0)
        }
        return max(stability * increase, FSRSParameters.stabilityMin)
    }

    private func nextForgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let longTerm = parameters[11]
            * pow(difficulty, -parameters[12])
            * (pow(stability + 1, parameters[13]) - 1)
            * exp((1 - retrievability) * parameters[14])
        let shortTerm = stability / exp(parameters[17] * parameters[18])
        return min(longTerm, shortTerm)
    }

    private func nextRecallStability(difficulty: Double, stability: Double, retrievability: Double, rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? parameters[15] : 1
        let easyBonus = rating == .easy ? parameters[16] : 1
        return stability * (
            1
                + exp(parameters[8])
                * (11 - difficulty)
                * pow(stability, -parameters[9])
                * (exp((1 - retrievability) * parameters[10]) - 1)
                * hardPenalty
                * easyBonus
        )
    }

    private func clampDifficulty(_ difficulty: Double) -> Double {
        min(max(difficulty, FSRSParameters.minDifficulty), FSRSParameters.maxDifficulty)
    }

    // MARK: - Interval calculation

    private func nextIntervalDays(stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        let rounded = Int(raw.rounded())
        return min(max(rounded, 1), maximumIntervalDays)
    }

    private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7.0, 0.15),
        (7.0, 20.0, 0.10),
        (20.0, .infinity, 0.05),
    ]

    private func fuzzedIntervalDays(_ intervalDays: Int, randomSource: () -> Double) -> Int {
        guard Double(intervalDays) >= 2.5 else { return intervalDays }

        var delta = 1.0
        for range in Self.fuzzRanges {
            delta += range.factor * max(min(Double(intervalDays), range.end) - range.start, 0.0)
        }

        var minInterval = Int((Double(intervalDays) - delta).rounded())
        var maxInterval = Int((Double(intervalDays) + delta).rounded())
        minInterval = max(2, minInterval)
        maxInterval = min(maxInterval, maximumIntervalDays)
        minInterval = min(minInterval, maxInterval)

        let fuzzed = randomSource() * Double(maxInterval - minInterval + 1) + Double(minInterval)
        return min(Int(fuzzed.rounded()), maximumIntervalDays)
    }

    // MARK: - Date helpers

    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 86400).rounded(.towardZero))
    }
}
