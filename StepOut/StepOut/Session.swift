import Foundation

/// One sitting of work: a set of pages that belong together.
///
/// Nearly always this is one photograph — a worksheet becomes a page of notes
/// and a page per question, all made at the same moment and all about the same
/// thing. Grouping them is what stops the app becoming a flat list of
/// equations with no way to tell Monday's homework from Wednesday's.
struct Session: Identifiable, Codable {
    // Mutable so a session read back from disk keeps the identity it was
    // saved with, which is what its pages are found by.
    var id = UUID()

    var name: String
    var started = Date()

    var pages: [Page] = []

    /// Which page was open, so returning to a session returns you to your
    /// place in it rather than to the front.
    var openPage: UUID?

    var questions: [Page] { pages.filter(\.isQuestion) }

    var solved: Int { questions.filter(\.solved).count }

    /// What the dashboard says under the name.
    var summary: String {
        guard !pages.isEmpty else { return "Empty" }

        let notes = pages.count - questions.count

        var parts: [String] = []

        if !questions.isEmpty {
            parts.append("\(solved)/\(questions.count) done")
        }

        if notes > 0 {
            parts.append("\(notes) page\(notes == 1 ? "" : "s") of notes")
        }

        return parts.joined(separator: " · ")
    }

    var isFinished: Bool {
        !questions.isEmpty && solved == questions.count
    }
}
