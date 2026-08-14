import Foundation

/// When the student's working gets checked.
///
/// The two are genuinely different ways to be taught, not a fast and a slow
/// version of one. Being stopped on the line where the mistake happened is
/// worth a great deal — the alternative is finding out six lines later, when
/// the wrong thing has already been built on. But being stopped is also being
/// interrupted, and a student who is halfway through a thought and knows they
/// are halfway through it does not want a verdict yet.
///
/// So it is asked rather than guessed at, and neither is the "advanced" one.
enum Marking: String, CaseIterable, Identifiable {
    /// Read the page whenever the writing stops for a moment.
    case watching

    /// Say nothing until Check is tapped.
    case onAsk

    var id: String { rawValue }

    var name: String {
        switch self {
        case .watching: "Check as I go"
        case .onAsk: "Only when I ask"
        }
    }

    var summary: String {
        switch self {
        case .watching:
            "The tutor reads your working each time you pause, and stops you on the line that went wrong."
        case .onAsk:
            "Work as far as you like undisturbed. Nothing is marked until you tap Check."
        }
    }

    var symbol: String {
        switch self {
        case .watching: "eye"
        case .onAsk: "hand.raised"
        }
    }
}
