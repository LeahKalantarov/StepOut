import Foundation

// Matches the JSON that backend/main.py sends back.
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

    /// Why the step failed — wrong_answer, wrong_divisor, divided_one_side, …
    let reason: String?

    /// What the previous line actually implies, e.g. "x = 4"
    let expectedAnswer: String?

    /// What we think the student wrote for the bad step
    let studentAnswer: String?

    // Everything a lesson about this mistake would need, when the step was
    // wrong. Held onto in case the student asks for help, and handed straight
    // back so nothing has to work out what went wrong a second time.
    let help: HelpContext?

    // Anything written on the page and marked as a question, already answered.
    let questions: [AnsweredQuestion]?
}

/// A question the student wrote on their page, and what the tutor said back.
struct AnsweredQuestion: Codable {
    let asked: String
    let answer: String
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

    let expectedAnswer: String?
    let expectedDivisor: String?
    let guessedDivisor: String?
}

struct TutorResponse: Codable {
    let reply: String
    let prompt: String?
    let source: String?
    let isPushback: Bool?
}

struct PhotoUploadResponse: Codable {
    let ok: Bool
    let photos: [String]?
}

struct NotesUploadResponse: Codable {
    let ok: Bool
    let notes: String?
}

struct TutorCheckPayload: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?
    let reason: String?
    let expectedAnswer: String?
    let studentAnswer: String?
    let solved: Bool?
    let answer: String?
}

/// Turns a CheckResult into the dictionary the tutor endpoint expects.
extension CheckResult {
    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = ["ok": ok]

        if let errorStep { dict["error_step"] = errorStep }
        if let message { dict["message"] = message }
        if let reason { dict["reason"] = reason }
        if let expectedAnswer { dict["expected_answer"] = expectedAnswer }
        if let studentAnswer { dict["student_answer"] = studentAnswer }
        if let solved { dict["solved"] = solved }
        if let answer { dict["answer"] = answer }

        return dict
    }

    func tutorPayload() -> TutorCheckPayload {
        TutorCheckPayload(
            ok: ok,
            errorStep: errorStep,
            message: message,
            reason: reason,
            expectedAnswer: expectedAnswer,
            studentAnswer: studentAnswer,
            solved: solved,
            answer: answer
        )
    }
}
