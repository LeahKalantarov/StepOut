import Foundation

/// What the tutor knows about this student from before today.
///
/// The name is the point. A doctor does not start from nothing every visit —
/// they open the chart, see what has happened before, and that is most of what
/// makes the next ten minutes useful. A tutor that forgets you between
/// sessions gives you the same explanation for the same slip four times and
/// never notices it is the same slip.
///
/// What goes in here is deliberately narrow: counts and names, and every one
/// of them comes from the checker rather than from the model. The checker
/// decides that a step dropped a solution; nothing here is a language model's
/// impression of how a student is getting on. That keeps the record small
/// enough to send with every request and true enough to act on.
struct Chart: Codable {
    /// How many questions have been finished.
    var solved = 0

    /// How many were marked wrong along the way. Not a judgement — the ratio
    /// of these two is roughly what "how hard is this for them" means.
    var slips = 0

    /// The checker's own name for each mistake, and how often it has happened.
    /// Keyed on the reason so "dropped a solution" in April and the same thing
    /// in August are one entry, not two.
    var mistakes: [String: Int] = [:]

    /// The ideas already taught, oldest first. Something taught twice is
    /// nearly always something the first lesson failed to land.
    var taught: [String] = []

    var lastSeen: Date?

    // MARK: - Writing to the chart

    mutating func solvedOne() {
        solved += 1
        lastSeen = Date()
    }

    mutating func slipped(_ reason: String?) {
        slips += 1
        lastSeen = Date()

        guard let reason, !reason.isEmpty else { return }

        mistakes[reason, default: 0] += 1
    }

    mutating func learned(_ concept: String) {
        let idea = concept.trimmingCharacters(in: .whitespaces).lowercased()

        guard !idea.isEmpty else { return }

        taught.append(idea)
        lastSeen = Date()

        // A chart is only useful while it is short. Beyond this it stops being
        // a record of what this student is like and turns into a transcript,
        // and it still has to fit in a prompt.
        if taught.count > 20 {
            taught.removeFirst(taught.count - 20)
        }
    }

    // MARK: - Reading it back

    /// The chart as sentences, ready to be handed to the tutor.
    ///
    /// Only things worth acting on. A student who has made a mistake once has
    /// not got a habit, and telling the tutor about it invites a lecture about
    /// a pattern that does not exist.
    var forTheTutor: [String] {
        guard solved + slips > 0 else { return [] }

        var notes = ["They have finished \(solved) question(s) with me and been marked wrong \(slips) time(s)."]

        let repeated = mistakes
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }

        for (reason, times) in repeated.prefix(3) {
            notes.append("They have made this mistake \(times) times before: \(reason).")
        }

        if let recent = lastTaught {
            notes.append("Ideas you have already taught them: \(recent).")
        }

        return notes
    }

    /// The last few ideas taught, most recent first, without repeats.
    private var lastTaught: String? {
        var seen: [String] = []

        for idea in taught.reversed() where !seen.contains(idea) {
            seen.append(idea)
            if seen.count == 4 { break }
        }

        return seen.isEmpty ? nil : seen.joined(separator: ", ")
    }

    /// The mistakes that have happened more than once, worst first, for showing
    /// the student their own chart.
    var habits: [(reason: String, times: Int)] {
        mistakes
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .map { (reason: $0.key, times: $0.value) }
    }
}

// MARK: - Keeping it between sessions

/// The chart, held in memory and written to disk whenever it changes.
///
/// On the iPad rather than on the server, because there are no accounts and
/// nothing here needs one. It is the student's own record of their own work,
/// and the only reason any of it leaves the device is that the tutor is asking
/// what happened last time.
@Observable
final class ChartKeeper {
    private(set) var chart: Chart

    private static let key = "studentChart"

    init() {
        if let saved = UserDefaults.standard.data(forKey: Self.key),
           let read = try? JSONDecoder().decode(Chart.self, from: saved) {
            chart = read
        } else {
            chart = Chart()
        }
    }

    func update(_ change: (inout Chart) -> Void) {
        change(&chart)
        save()
    }

    func forget() {
        chart = Chart()
        save()
    }

    private func save() {
        guard let written = try? JSONEncoder().encode(chart) else { return }

        UserDefaults.standard.set(written, forKey: Self.key)
    }
}
