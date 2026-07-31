import Foundation

/// One question from the server.
///
/// Deliberately no answer. The iPad never needs it, and anything sent to the
/// app could be read by the student.
struct Problem: Codable, Identifiable {
    let index: Int
    let prompt: String
    let equation: String

    var id: Int { index }
}

/// The shape the server replies with: {"problems": [...]}.
struct ProblemList: Codable {
    let problems: [Problem]
}
