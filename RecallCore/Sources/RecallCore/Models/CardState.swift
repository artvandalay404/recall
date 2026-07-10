import GRDB

/// A card's position in the FSRS learning lifecycle.
///
/// `new` has no counterpart in the upstream FSRS reference scheduler (which starts
/// cards directly in `.learning` with a nil stability) — it is kept here as a distinct
/// state because the product needs to distinguish "never studied" cards from
/// "mid learning-steps" cards for daily new-card limits and deck new/due counts.
public enum CardState: Int, Codable, Sendable, DatabaseValueConvertible {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}
