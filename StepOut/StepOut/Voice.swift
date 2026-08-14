import Foundation

/// How the student wants the tutor to talk to them.
///
/// The marking is the same either way — it is done by a computer algebra
/// system and does not have a mood. This changes only the wrapping around it,
/// which is not nothing: a student who has been stuck for twenty minutes and
/// one who wants the mistake named and nothing else are badly served by the
/// same voice, and the wrong one reads as either patronising or cold.
enum Voice: String, CaseIterable, Identifiable {
    case encouraging
    case direct
    case thorough

    var id: String { rawValue }

    var name: String {
        switch self {
        case .encouraging: "Encouraging"
        case .direct: "Straight to the point"
        case .thorough: "Explain everything"
        }
    }

    var summary: String {
        switch self {
        case .encouraging:
            "Notices what you got right before naming what went wrong."
        case .direct:
            "Names the mistake in a sentence. No warm-up."
        case .thorough:
            "Gives the reason behind the rule, not just the rule."
        }
    }

    var symbol: String {
        switch self {
        case .encouraging: "hand.thumbsup"
        case .direct: "bolt"
        case .thorough: "book"
        }
    }
}
