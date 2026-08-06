import Foundation

// Matches the JSON that backend/main.py sends back.
struct CheckResult: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?
    let recognized: [String]?
    let solved: Bool?
    let answer: String?
    let extraSteps: Bool?

    /// Why the step failed — wrong_answer, wrong_divisor, divided_one_side, …
    let reason: String?

    /// What the previous line actually implies, e.g. "x = 4"
    let expectedAnswer: String?

    /// What we think the student wrote for the bad step
    let studentAnswer: String?

    /// Extra detail the tutor can use when help is asked for
    let help: HelpContext?
}

struct HelpContext: Codable {
    let wrongLine: String?
    let previousLine: String?
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
}
