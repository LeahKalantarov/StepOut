import Foundation

/// One line the tutor has written on the page.
///
/// Each line carries when to start writing rather than working it out from its
/// position in the list, because lines get added at different moments: the
/// explanation arrives with the verdict, the offer of help a beat later, and a
/// lesson only if it is asked for. Anything already on the page should stay
/// still while the new line writes itself.
struct TutorLine: Identifiable {
    /// Whether the line should survive the next check.
    enum Kind {
        /// A verdict or an offer of help. Stays on the page across rechecks so
        /// earlier notes can still be read — new feedback is appended beside
        /// the work it refers to, not written over the old.
        case remark

        /// Something taught. It was asked for, and it stays until the page is
        /// cleared — taking it away mid-problem removes the very thing they
        /// are working from.
        case lesson
    }

    let id = UUID()

    /// Which sitting of writing this line belongs to.
    ///
    /// `delay` is counted from the start of its own batch, so it only means
    /// anything alongside the batch it came from. Without this, stopping would
    /// compare a fresh line's delay against an older line's and rub out
    /// writing that finished minutes ago.
    let batch: UUID

    let kind: Kind

    let text: String

    /// Which ruled line it rests on, counting from the top of the page.
    let line: Int

    /// How far in from the left the pen touches down. Tutor columns sit beside
    /// the student's work rather than underneath it.
    let originX: CGFloat

    /// How long to wait before starting, so lines follow one another instead
    /// of appearing together.
    let delay: Double

    /// Whether the pen has finished with this line. Set once its batch is
    /// done, so redrawing it elsewhere shows it whole rather than writing it
    /// out all over again.
    var written = false
}

/// One sitting of the tutor's writing — a verdict, an offer, or a lesson.
struct TutorBatch: Identifiable {
    let id: UUID
    let kind: TutorLine.Kind
    let lines: [TutorLine]

    var firstLine: Int { lines.first?.line ?? 0 }
}
