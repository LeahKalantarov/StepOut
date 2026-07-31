import SwiftUI

/// Writes a line of text onto the page, stroke by stroke, as if by hand.
///
/// The trick is `trim`. A path knows its own length, and trimming it to 0.4
/// gives you the first 40% of the pen's journey. So we animate that fraction
/// from 0 to 1 and the line draws itself, in the order a hand would write it.
struct HandwrittenLine: View {
    let text: String

    /// Where the pen touches down: the left end of the line it writes on.
    let origin: CGPoint

    /// Height of a capital letter, in points.
    var height: CGFloat = 30

    var color: Color = .blue.opacity(0.75)

    /// Wait this long before starting, so a line can follow the one above it
    /// instead of both being written at once.
    var delay: Double = 0

    /// How much of the line has been written so far, from 0 to 1.
    @State private var written: CGFloat = 0

    var body: some View {
        StrokeFont.path(for: text, from: origin, height: height)
            .trim(from: 0, to: written)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            // Rewrite from the start whenever the text changes, so moving to
            // the next question animates instead of appearing all at once.
            .task(id: text) {
                written = 0
                try? await Task.sleep(for: .seconds(delay))

                withAnimation(.easeInOut(duration: Self.writingTime(for: text))) {
                    written = 1
                }
            }
    }

    /// Longer lines take longer to write, so the pen keeps a steady pace
    /// instead of racing through a long question and crawling through a short
    /// one. Callers use this to work out how long to wait their turn.
    static func writingTime(for text: String) -> Double {
        max(0.6, Double(text.count) * 0.11)
    }
}
