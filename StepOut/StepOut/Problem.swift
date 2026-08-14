import Foundation

/// One question the server read off a photographed page.
///
/// Deliberately no answer. The iPad never needs it, and anything sent to the
/// app could be read by the student.
struct Problem: Codable, Identifiable {
    let index: Int
    let prompt: String
    let equation: String

    var id: Int { index }
}
