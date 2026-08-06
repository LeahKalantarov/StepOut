import SwiftUI

// Shared measurements for the notebook page.
//
// The ruled lines, the grouping of strokes into lines, and the marks in the
// margin all read these numbers. Keeping them in one place is what stops a
// tick landing next to the wrong line.
enum NotebookLayout {
    /// Distance from one ruled line to the next.
    static let lineHeight: CGFloat = 64

    /// How far in the red margin rule sits.
    static let marginWidth: CGFloat = 56

    /// How long a page is before anything is written on it.
    ///
    /// A page that stops at the bottom of the screen cannot be scrolled at
    /// all, so there would be no way to look ahead at blank paper or back at
    /// what the tutor wrote further up.
    static let leastLines = 30

    /// Where writing rests on a given line: just above the rule, a little in
    /// from the margin, the way you would start writing on real paper.
    ///
    /// Line 0 is the top line. StrokeReader numbers lines the same way, so a
    /// line written here and a line read back there mean the same thing.
    static func penStart(onLine lineNumber: Int, x: CGFloat? = nil) -> CGPoint {
        CGPoint(
            x: x ?? marginWidth + 16,
            y: CGFloat(lineNumber + 1) * lineHeight - 12
        )
    }

    /// Gap between the student's column and the tutor's.
    static let columnGap: CGFloat = 24
}
