import Foundation

/// One thing the tutor wrote that the student can keep, collapse, or remove.
struct TutorNote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let prompt: String?
    var isCollapsed = false
}
