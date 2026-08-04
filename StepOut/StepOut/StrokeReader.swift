import PencilKit

// PencilKit stores a drawing as smooth curves carrying pressure and tilt.
// MyScript only wants plain x/y coordinates, so we walk each stroke and
// sample points along it.

// How far apart to sample, in points. Smaller means more detail but a bigger
// request; 2 keeps the shape of handwriting without being wasteful.
private let sampleSpacing: CGFloat = 2

// How far a stroke can sit below the line it is joining. Writing tilts as it
// crosses the page, so this has to be forgiving — but it must stay well under
// a full line height, or two rows of writing merge into one.
private let sameLineDistance = NotebookLayout.lineHeight * 0.6

/// One line of writing.
struct WrittenLine {
    /// The ruled line this sits closest to, counting from the top of the page.
    /// Only used to put a tick or a cross beside the right line afterwards.
    let lineNumber: Int

    let strokes: [StrokeData]
}

/// A stroke and the height it was written at, while we work out which line it
/// belongs to.
private struct PlacedStroke {
    let height: CGFloat
    let coordinates: StrokeData
}

extension PKCanvasView {
    /// Gather the writing on this page into lines, ordered top to bottom.
    ///
    /// The printed rules are there for the student, not for us. People write
    /// across them, and a line that sags as it crosses the page would be torn
    /// in half by anything that trusted the grid — half an equation is not an
    /// equation, so the step would be quietly dropped and the student's work
    /// would appear to vanish.
    ///
    /// So we find the lines in the writing itself: strokes at similar heights
    /// belong together, and a real vertical gap starts a new line.
    func writtenLines() -> [WrittenLine] {
        var strokes: [PlacedStroke] = []

        for stroke in drawing.strokes {
            guard let coordinates = coordinates(of: stroke) else { continue }
            strokes.append(PlacedStroke(height: stroke.renderBounds.midY, coordinates: coordinates))
        }

        // Top to bottom, so strokes sharing a line arrive together whatever
        // order they were written in — people go back to cross a t, or squeeze
        // in a minus sign they forgot.
        strokes.sort { $0.height < $1.height }

        var lines: [[PlacedStroke]] = []

        for stroke in strokes {
            // Measured against the line's own average height, not a fixed
            // grid. That average follows the writing down the page, so a
            // gradual drift never builds up into a split.
            if let line = lines.last, stroke.height - averageHeight(of: line) < sameLineDistance {
                lines[lines.count - 1].append(stroke)
            } else {
                lines.append([stroke])
            }
        }

        return lines.map { line in
            WrittenLine(
                lineNumber: Int(averageHeight(of: line) / NotebookLayout.lineHeight),
                strokes: movedToOrigin(line.map(\.coordinates))
            )
        }
    }

    private func averageHeight(of line: [PlacedStroke]) -> CGFloat {
        line.reduce(0) { $0 + $1.height } / CGFloat(line.count)
    }

    /// Sample evenly spaced points along one stroke.
    /// Returns nil for a stray dot, which the recognizer cannot use.
    private func coordinates(of stroke: PKStroke) -> StrokeData? {
        var xs: [Double] = []
        var ys: [Double] = []

        for point in stroke.path.interpolatedPoints(by: .distance(sampleSpacing)) {
            let location = point.location.applying(stroke.transform)
            xs.append(location.x)
            ys.append(location.y)
        }

        guard xs.count >= 2 else { return nil }

        return StrokeData(x: xs, y: ys)
    }

    /// Shift one line's writing up against the origin.
    ///
    /// MyScript cares about the shape of the writing, not where on the page it
    /// happens to sit. Sending every line from the same starting point means a
    /// step written near the bottom is read exactly like one near the top.
    private func movedToOrigin(_ strokes: [StrokeData]) -> [StrokeData] {
        let smallestX = strokes.flatMap(\.x).min() ?? 0
        let smallestY = strokes.flatMap(\.y).min() ?? 0

        return strokes.map { stroke in
            StrokeData(
                x: stroke.x.map { $0 - smallestX },
                y: stroke.y.map { $0 - smallestY }
            )
        }
    }
}
