import Foundation

// Matches the JSON that backend/main.py sends back:
// { "ok": false, "error_step": 3, "message": "..." }
struct CheckResult: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?
}
