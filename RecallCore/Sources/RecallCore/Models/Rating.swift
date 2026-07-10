import GRDB

/// The four grades a learner can give a card during study, matching the FSRS reference model.
public enum Rating: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}
