import Foundation

/// A short lesson the tutor writes onto the page.
///
/// The question is deliberately not the student's own. Working their problem
/// for them ends the lesson; working one just like it leaves them something to
/// do. Every step has already been through the same checker that marks their
/// work, so nothing written here can be wrong.
struct Lesson: Codable {
    /// What this is called, in a few words. "Difference of two squares".
    let concept: String

    /// The rule itself, short enough to copy down. "a^2 - b^2 = (a-b)(a+b)".
    let rule: String

    /// A different question needing the same move.
    let question: String

    /// That question solved, one line per step, starting from the question.
    let steps: [String]

    /// The lesson as it goes onto the page, top line first.
    ///
    /// The steps already open with the question, so writing it out separately
    /// would only say the same thing twice.
    var lines: [String] {
        [concept, rule] + steps
    }
}

/// What the server heard when it read a row as words.
struct WordsReply: Codable {
    let words: [String]
}
