import PencilKit

// PencilKit stores a drawing as smooth curves carrying pressure and tilt.
// MyScript only wants plain x/y coordinates, so we walk each stroke and
// sample points along it.

// How far apart to sample, in points. Smaller means more detail but a bigger
// request; 2 keeps the shape of handwriting without being wasteful.
private let sampleSpacing: CGFloat = 2

/// One ruled line that has writing on it.
struct WrittenLine {
    /// Which ruled line this sits on, counting from the top of the page.
    /// We keep it so a mark can be drawn beside the right line later.
    let lineNumber: Int

    let strokes: [StrokeData]
}

extension PKCanvasView {
    /// Gather the writing on this page into lines, ordered top to bottom.
    ///
    /// A stroke belongs to whichever ruled line its middle sits on. That is
    /// what lets one page hold several steps without needing a separate
    /// canvas for each one.
    func writtenLines() -> [WrittenLine] {
        var strokesByLine: [Int: [StrokeData]] = [:]

        for stroke in drawing.strokes {
            guard let coordinates = coordinates(of: stroke) else { continue }

            let middle = stroke.renderBounds.midY
            let lineNumber = Int(middle / NotebookLayout.lineHeight)

            strokesByLine[lineNumber, default: []].append(coordinates)
        }

        return strokesByLine.keys.sorted().map { lineNumber in
            WrittenLine(
                lineNumber: lineNumber,
                strokes: movedToOrigin(strokesByLine[lineNumber] ?? [])
            )
        }
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
