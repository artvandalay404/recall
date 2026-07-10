import Foundation

/// The 21 model weights driving the FSRS-6 formulas, plus the bounds the
/// optimizer is required to keep them within.
///
/// Ported from the reference implementation at
/// https://github.com/open-spaced-repetition/py-fsrs (`fsrs/scheduler.py`),
/// which is itself the algorithm the Anki desktop/mobile clients ship.
public struct FSRSParameters: Equatable, Sendable {
    public static let count = 21

    public var weights: [Double]

    public init(weights: [Double] = FSRSParameters.defaultWeights) {
        precondition(weights.count == FSRSParameters.count, "FSRS expects exactly \(FSRSParameters.count) parameters, got \(weights.count).")
        self.weights = weights
    }

    public static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    public static let `default` = FSRSParameters()

    public static let lowerBounds: [Double] = [
        stabilityMin, stabilityMin, stabilityMin, stabilityMin,
        1.0, 0.001, 0.001, 0.001, 0.0, 0.0, 0.001, 0.001, 0.001, 0.001,
        0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.1,
    ]

    public static let upperBounds: [Double] = [
        initialStabilityMax, initialStabilityMax, initialStabilityMax, initialStabilityMax,
        10.0, 4.0, 4.0, 0.75, 4.5, 0.8, 3.5, 5.0, 0.25, 0.9, 4.0, 1.0, 6.0, 2.0, 2.0, 0.8, 0.8,
    ]

    public static let stabilityMin = 0.001
    public static let initialStabilityMax = 100.0
    public static let minDifficulty = 1.0
    public static let maxDifficulty = 10.0

    /// Whether every weight falls within the bounds the FSRS optimizer enforces.
    public var isValid: Bool {
        zip(weights, zip(Self.lowerBounds, Self.upperBounds)).allSatisfy { weight, bounds in
            bounds.0 <= weight && weight <= bounds.1
        }
    }

    subscript(index: Int) -> Double { weights[index] }
}
