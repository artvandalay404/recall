import GRDB
import Foundation

/// An HTML/CSS template belonging to a `NoteType` that generates one `Card`
/// per `Note`, rendered client-side in a WKWebView.
public struct CardTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var noteTypeID: String
    public var name: String
    public var ordinal: Int
    public var questionTemplate: String
    public var answerTemplate: String
    public var css: String

    public init(
        id: String = UUID().uuidString,
        noteTypeID: String,
        name: String,
        ordinal: Int,
        questionTemplate: String,
        answerTemplate: String,
        css: String = ""
    ) {
        self.id = id
        self.noteTypeID = noteTypeID
        self.name = name
        self.ordinal = ordinal
        self.questionTemplate = questionTemplate
        self.answerTemplate = answerTemplate
        self.css = css
    }
}

extension CardTemplate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cardTemplate"
}
