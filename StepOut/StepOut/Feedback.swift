import SwiftUI

/// Something to tell the student after a check.
///
/// This is deliberately short-lived. The lasting record of a mistake is the
/// cross in the margin next to the line it belongs to, which stays put; these
/// words only explain it, so they can leave once read.
struct Feedback: Equatable {
    enum Tone {
        case good
        case bad
        case plain
    }

    let text: String
    let tone: Tone

    /// Lines the checker passed over, if any. Shown small, because it only
    /// matters when a verdict looks wrong and you need to know why.
    var skipped: [String] = []
}

/// The note itself, floating over the page.
struct FeedbackNote: View {
    let feedback: Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(feedback.text)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(colour)
            }

            if !feedback.skipped.isEmpty {
                Text("Skipped \(feedback.skipped.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(colour.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var symbol: String {
        switch feedback.tone {
        case .good: "checkmark.circle.fill"
        case .bad: "exclamationmark.circle.fill"
        case .plain: "info.circle.fill"
        }
    }

    private var colour: Color {
        switch feedback.tone {
        case .good: .green
        case .bad: .red
        case .plain: .secondary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        FeedbackNote(feedback: Feedback(text: "Solved! x = 7", tone: .good))
        FeedbackNote(feedback: Feedback(text: "x = 5 doesn't follow from 2x = 8", tone: .bad))
        FeedbackNote(
            feedback: Feedback(text: "Correct so far. Keep going.", tone: .plain, skipped: ["s - s"])
        )
    }
    .padding(40)
    .background(Color(red: 0.99, green: 0.98, blue: 0.94))
}
