/// Per-deck due/new counts shown in the deck list (PRD §7.1), already capped
/// by whatever's left of that deck's daily new/review allowance for today.
public struct DeckStats: Equatable, Sendable {
    public var dueCount: Int
    public var newCount: Int

    public init(dueCount: Int, newCount: Int) {
        self.dueCount = dueCount
        self.newCount = newCount
    }
}
