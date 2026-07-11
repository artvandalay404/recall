/// What an `.apkg` / `.colpkg` import produced, shown to the user once the
/// import finishes (PRD §7.7).
public struct ApkgImportSummary: Equatable, Sendable {
    public var deckCount: Int
    public var noteCount: Int
    public var cardCount: Int
    public var mediaFileCount: Int
    public var reviewLogCount: Int

    public init(
        deckCount: Int = 0,
        noteCount: Int = 0,
        cardCount: Int = 0,
        mediaFileCount: Int = 0,
        reviewLogCount: Int = 0
    ) {
        self.deckCount = deckCount
        self.noteCount = noteCount
        self.cardCount = cardCount
        self.mediaFileCount = mediaFileCount
        self.reviewLogCount = reviewLogCount
    }
}
