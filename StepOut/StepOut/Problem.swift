import Foundation

// One question to solve, as sent by GET /problem/{index}.
// The answer is deliberately not included — the server keeps that to itself.
struct Problem: Codable {
    let index: Int
    let total: Int
    let prompt: String
    let equation: String
}
