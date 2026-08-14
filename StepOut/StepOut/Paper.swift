import SwiftUI

/// The page itself: how it is ruled, and what shade it is.
///
/// Ink colours live here too rather than being scattered through the views,
/// because every one of them depends on the paper. Blue rules and near-black
/// ink read well on cream and disappear on a dark page.
@Observable
final class Paper {
    var ruling: Ruling = .ruled
    var shade: Shade = .cream

    enum Ruling: String, CaseIterable, Identifiable {
        case ruled
        case dotted
        case plain

        var id: String { rawValue }

        var name: String {
            switch self {
            case .ruled: "Ruled"
            case .dotted: "Dotted"
            case .plain: "Plain"
            }
        }

        var symbol: String {
            switch self {
            case .ruled: "list.dash"
            case .dotted: "circle.grid.3x3"
            case .plain: "rectangle"
            }
        }
    }

    enum Shade: String, CaseIterable, Identifiable {
        case cream
        case white
        case slate

        var id: String { rawValue }

        var name: String {
            switch self {
            case .cream: "Cream"
            case .white: "White"
            case .slate: "Dark"
            }
        }
    }

    // MARK: - Colours

    var background: Color {
        switch shade {
        case .cream: Theme.paper
        case .white: Theme.paper
        case .slate: Color(red: 0.11, green: 0.11, blue: 0.13)
        }
    }

    var isDark: Bool { shade == .slate }

    /// What lies beyond the edge of the page.
    ///
    /// Only ever seen once the page has been pinched smaller than the screen,
    /// and the whole job of it is to not be the page. Without it, zooming out
    /// leaves the paper ending in the middle of a field of the same colour,
    /// and it stops being obvious where the sheet you are writing on stops.
    var desk: Color {
        isDark ? Color(red: 0.05, green: 0.05, blue: 0.06) : Color(red: 0.87, green: 0.88, blue: 0.9)
    }

    /// The printed rules or dots.
    var rule: Color {
        isDark ? .white.opacity(0.14) : Theme.sky.opacity(0.55)
    }

    /// The margin line down the left.
    var margin: Color {
        isDark ? Theme.pink.opacity(0.5) : Theme.pink.opacity(0.7)
    }

    /// What a pen should default to, so writing is never invisible.
    var defaultInk: Color {
        isDark ? .white : Theme.ink
    }

    /// The question at the top of the page.
    var questionInk: Color {
        isDark ? Theme.sky : Theme.ink
    }

    /// The tutor's own hand.
    var tutorInk: Color {
        isDark ? Theme.pink.opacity(0.9) : Theme.pink
    }

    /// A quieter version of the tutor's hand, for folded-away writing.
    var tutorInkFaded: Color {
        tutorInk.opacity(0.55)
    }
}
