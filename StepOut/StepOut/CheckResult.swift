import Foundation

// Matches the JSON that backend/main.py sends back, for example:
// { "ok": true, "solved": true, "answer": "x = 4", "recognized": [...] }
// { "ok": false, "error_step": 3, "message": "..." }
struct CheckResult: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?

    // What MyScript thought each row said. Useful for showing the student
    // how their handwriting was read.
    let recognized: [String]?

    // True once a row is a finished answer like "x = 4"
    let solved: Bool?

    // The finished answer itself, so we can repeat it back
    let answer: String?

    // True when there are more rows written after the answer
    let extraSteps: Bool?

    // Lines that weren't equations, so they took no part in the check.
    // Usually annotations like "-5  -5", or a cross-out the recognizer
    // turned into nonsense. Shown so a surprising verdict is explainable.
    let ignored: [String]?

    // Everything a lesson about this mistake would need, when the step was
    // wrong. Held onto in case the student asks for help, and handed straight
    // back so nothing has to work out what went wrong a second time.
    let help: HelpContext?

    // Anything written on the page and marked as a question, already answered.
    let questions: [AnsweredQuestion]?

    // Which rows the answers were written on, counted from 1. The tick and the
    // ring go here. Without it the only guess available is the last row on the
    // page, which is a note in the margin as often as it is the answer.
    let answerSteps: [Int]?
}

/// A question the student wrote on their page, and what the tutor said back.
struct AnsweredQuestion: Codable {
    let asked: String
    let answer: String

    /// The row the question was written on, counted from 1, so the answer can
    /// go beside it. Without it the answer lands at the foot of the page,
    /// which on a page of working is a long way from what was asked.
    let row: Int?
}

/// One mistake, described well enough to teach the idea behind it.
///
/// Travels in both directions: the server fills it in when a step fails, and
/// the app sends the same thing back if help is asked for.
struct HelpContext: Codable {
    let wrongLine: String
    let question: String?
    let previousLine: String?

    /// What the checker decided was wrong, in its own words. Without this the
    /// tutor has to guess from two equations, and a dropped answer looks like
    /// sound working until you count the answers.
    let reason: String?
}
