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
}
