import Foundation
import PencilKit

/// One page in the notebook.
///
/// A page either has a question at the top of it or it does not, and that one
/// difference is the whole model. A page with a question gets marked against
/// it; a page without is somewhere to write — notes copied off a photograph,
/// a worked example, rough practice — and the checker only asks that each line
/// follows from the one above.
///
/// The notebook starts empty. There is no set of questions shipped with the
/// app, because the questions that matter are the ones on the student's own
/// homework, and those arrive by photograph.
struct Page: Identifiable, Codable {
    // Mutable so a page read back from disk keeps the identity it was saved
    // with — that identity is what ties it to the work stored against it.
    var id = UUID()

    /// What the page is called in the drawer.
    var name: String

    /// The question to mark against, if there is one.
    var question: String?

    /// Set once the checker says the question on this page is finished.
    var solved = false

    var isQuestion: Bool { question != nil }

    static func question(_ equation: String) -> Page {
        Page(name: equation, question: equation)
    }

    static func notes(_ name: String = "Notes") -> Page {
        Page(name: name, question: nil)
    }
}

/// Everything written on a page, kept while another page is open.
///
/// Without this, pages would be a way to lose work: turning to a second
/// question and back would find the first one blank. So the ink and the
/// tutor's writing are put away together and brought back out on return.
struct PageWork: Codable {
    /// The student's own strokes, as PencilKit stores them.
    var drawing = Data()

    /// The notes printed on the page, if it is a sheet read off a photograph.
    /// Underneath the writing rather than part of it, so the student can work
    /// on top of their own notes.
    var sheet: NoteSheet?

    /// Everything the tutor has written on this page, and how the student has
    /// since folded, moved, and resized it.
    var tutorLines: [TutorLine] = []
    var collapsed: Set<UUID> = []
    var offsets: [UUID: CGSize] = [:]
    var scales: [UUID: CGFloat] = [:]

    /// Questions asked on this page that have already been answered.
    ///
    /// Optional so that work saved before this existed still reads back. A
    /// page put down mid-question and picked up tomorrow would otherwise have
    /// its question answered a second time on the first check.
    var answered: [String]?

    var strokes: PKDrawing {
        (try? PKDrawing(data: drawing)) ?? PKDrawing()
    }
}
