import Foundation

/// Something the student wrote on the page and asked the tutor about.
///
/// Carries the problem and the working alongside the words, because most real
/// questions lean on them. "why doesn't that work" means nothing on its own.
struct Question: Codable {
    let question: String

    let problem: String?
    let work: [String]?

    /// How the tutor should speak when it answers.
    var style: String?

    /// What the tutor knows about them from before today.
    var history: [String]?
}

/// A short answer, written back onto the page.
struct AnswerReply: Codable {
    let answer: String
}
