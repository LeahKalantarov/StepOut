import SwiftUI

/// A page of notes, laid out the way a revision sheet is.
///
/// The tutor's writing on a question page is a running commentary — lines
/// appended as they are earned, in the order they happened. A sheet is not
/// that. It is a thing to look something up in later, which means the
/// discriminant has to be in the same sort of box on every sheet, and the
/// definition has to be at the top on every sheet.
///
/// So the model never lays anything out. It says what belongs in which kind of
/// box, and everything about how a box of that kind looks is decided here.
struct NoteSheet: Codable {
    var title: String
    var cards: [NoteCard]
}

struct NoteCard: Identifiable, Codable {
    /// What a box can be. The one word the model chooses, and the only say it
    /// has in how the sheet looks.
    enum Kind: String, Codable {
        case definition
        case formula
        case method
        case example
        case keypoints
        case tip
        case graph

        /// The fill. Colour carries meaning here rather than decoration — the
        /// yellow box is always the one with the formula in it, so a sheet can
        /// be skimmed for the thing you came back for.
        var colour: Color {
            switch self {
            case .definition: Theme.sky.opacity(0.35)
            case .formula: Theme.yellow.opacity(0.55)
            case .tip: Theme.pink.opacity(0.18)
            case .example, .method, .keypoints, .graph: Theme.paper
            }
        }

        /// Drawn small beside the heading, so the kind reads before the words.
        var symbol: String {
            switch self {
            case .definition: "text.book.closed.fill"
            case .formula: "function"
            case .method: "list.number"
            case .example: "pencil.line"
            case .keypoints: "checklist"
            case .tip: "star.fill"
            case .graph: "chart.xyaxis.line"
            }
        }

        /// Whether the box wants the full width of the sheet.
        ///
        /// A worked example is a column of steps that have to line up under
        /// one another, and a graph needs room to be square-ish. Squeezed into
        /// half a page both stop being readable.
        var isWide: Bool {
            self == .example || self == .graph
        }
    }

    var id = UUID()

    var heading: String
    var kind: Kind
    var lines: [String]
    var graph: NoteGraph?

    /// The identity is this end's business, so it is left out of both reading
    /// and writing.
    ///
    /// It has to be said explicitly. A `var` with a default value is still
    /// demanded when decoding — the default covers a card being made here, not
    /// one being read — so without this the server would have to invent an id
    /// for every card, and a reply that did not carry one would be thrown out
    /// whole. Only `let` properties with defaults are quietly skipped.
    ///
    /// Nothing needs it to survive a relaunch. It exists so the drawing can
    /// tell one box from another while laying out a sheet, and that lasts as
    /// long as the sheet is on screen.
    enum CodingKeys: String, CodingKey {
        case heading
        case kind
        case lines
        case graph
    }
}

/// A curve, as points on it.
///
/// Every number here was worked out by SymPy on the server. Nothing on the
/// iPad parses the expression or solves anything — it joins up the points it
/// was given and puts a dot where it was told the roots are. A graph is the
/// most convincing thing on a page of notes, and the most damaging to get
/// wrong, so nothing about it is guessed at either end.
struct NoteGraph: Codable {
    var expression: String
    var variable: String

    /// The curve. Each is an x and the height of the function there.
    var points: [[Double]]

    /// Where it crosses the axis, and where it turns.
    var roots: [Double]
    var turningPoint: [Double]?
    var yIntercept: Double?

    /// The stretch of graph these points cover.
    var xRange: [Double]
    var yRange: [Double]

    /// Where a point on the graph falls inside a box on screen.
    ///
    /// The whole of plotting, in three lines: squash the value to somewhere
    /// between 0 and 1 across the range being shown, multiply up by the box,
    /// and flip — because a screen counts downwards and a graph counts up.
    func place(x: Double, y: Double, in box: CGRect) -> CGPoint {
        let across = (x - xRange[0]) / max(xRange[1] - xRange[0], .ulpOfOne)
        let up = (y - yRange[0]) / max(yRange[1] - yRange[0], .ulpOfOne)

        return CGPoint(
            x: box.minX + across * box.width,
            y: box.maxY - up * box.height
        )
    }

    /// The curve as a path through the box, in the order it is drawn.
    func curve(in box: CGRect) -> Path {
        var path = Path()

        path.addLines(points.map { place(x: $0[0], y: $0[1], in: box) })

        return path
    }

    /// Whether zero falls inside what is being shown, on each axis. An axis
    /// drawn along the edge of the box because zero is off-screen is a lie
    /// about where the origin is.
    var showsVerticalAxis: Bool { xRange[0] < 0 && xRange[1] > 0 }
    var showsHorizontalAxis: Bool { yRange[0] < 0 && yRange[1] > 0 }
}
