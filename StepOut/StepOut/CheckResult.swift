import Foundation

// Matches the JSON that backend/main.py sends back:
// { "ok": false, "error_step": 3, "message": "...", "recognized": ["2x + 5 = 13", ...] }
struct CheckResult: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?

    // What MyScript thought each row said. Useful for showing the student
    // how their handwriting was read.
    let recognized: [String]?
}
