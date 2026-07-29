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
}
