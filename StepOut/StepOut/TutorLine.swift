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
        /// A verdict or an offer of help. Only true of the work as it stood
        /// when it was written, so it is rubbed out and written afresh each
        /// time the work is checked.
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

    /// How long to wait before starting, so lines follow one another instead
    /// of appearing together.
    let delay: Double
}
