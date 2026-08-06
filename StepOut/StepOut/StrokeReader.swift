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

// How wide a blank space has to be before it reads as a gap between two
// columns of work rather than a space inside one line.
//
// Deliberately large. Splitting one equation in half would leave two
// fragments that parse as nothing and get quietly dropped, so the cost of
// splitting too eagerly is much higher than the cost of not splitting at all.
// Two line heights of untouched paper is not something anyone leaves in the
// middle of writing 2x + 5 = 13.
private let columnGap = NotebookLayout.lineHeight * 2

/// One side-by-side column of student writing.
struct InkColumn {
    let lines: [WrittenLine]
    var minX: CGFloat { lines.map(\.bounds.minX).min() ?? 0 }
}

/// One line of writing.
struct WrittenLine {
    /// The ruled line this sits closest to, counting from the top of the page.
    /// Only used to put a tick or a cross beside the right line afterwards.
    let lineNumber: Int

    /// Where the writing actually sits on the page, so a mark can be drawn
    /// around it. In page coordinates, not screen ones — the canvas scrolls
    /// underneath and these have to keep meaning the same place.
    let bounds: CGRect

    let strokes: [StrokeData]
}

/// A stroke, and where it sits on the page, while we work out which line and
/// which column it belongs to.
private struct PlacedStroke {
    let height: CGFloat
    let bounds: CGRect
    let coordinates: StrokeData

    var left: CGFloat { bounds.minX }
    var right: CGFloat { bounds.maxX }
}

extension PKCanvasView {
    /// Gather the writing on this page into lines, in the order they should be
    /// read.
    ///
    /// The printed rules are there for the student, not for us. People write
    /// across them, and a line that sags as it crosses the page would be torn
    /// in half by anything that trusted the grid — half an equation is not an
    /// equation, so the step would be quietly dropped and the student's work
    /// would appear to vanish.
    ///
    /// So we find the lines in the writing itself: strokes at similar heights
    /// belong together, and a real vertical gap starts a new line.
    ///
    /// Height alone is not enough once there is anything else on the page. A
    /// student who has been given a worked example takes the empty half of the
    /// paper beside it and works there, and that second column sits at the
    /// same heights as the first. Read by height alone, the two run together
    /// into lines that are nonsense in both directions. So each row is also
    /// cut at any wide blank space, and the pieces are handed back a column at
    /// a time — down the left, then down the right, the way they were written.
    func writtenLines() -> [WrittenLine] {
        var strokes: [PlacedStroke] = []

        for stroke in drawing.strokes {
            guard let coordinates = coordinates(of: stroke) else { continue }

            let bounds = stroke.renderBounds
            strokes.append(
                PlacedStroke(
                    height: bounds.midY,
                    bounds: bounds,
                    coordinates: coordinates
                )
            )
        }

        // Top to bottom, so strokes sharing a line arrive together whatever
        // order they were written in — people go back to cross a t, or squeeze
        // in a minus sign they forgot.
        strokes.sort { $0.height < $1.height }

        var rows: [[PlacedStroke]] = []

        for stroke in strokes {
            // Measured against the line's own average height, not a fixed
            // grid. That average follows the writing down the page, so a
            // gradual drift never builds up into a split.
            if let row = rows.last, stroke.height - averageHeight(of: row) < sameLineDistance {
                rows[rows.count - 1].append(stroke)
            } else {
                rows.append([stroke])
            }
        }

        return inReadingOrder(rows.flatMap(columnsAcross))
    }

    /// The column the checker should read — the rightmost when the page holds
    /// more than one.
    ///
    /// Working again beside a tutor's example leaves the old attempt on the
    /// left. Reading every column in order chains those old steps with the new
    /// ones and marks good work wrong.
    func workingLines(pageWidth: CGFloat) -> [WrittenLine] {
        let columns = inkColumns(pageWidth: pageWidth)
        guard columns.count > 1 else { return writtenLines() }

        return columns.last!.lines.sorted { $0.lineNumber < $1.lineNumber }
    }

    /// How far right the student's ink reaches on one ruled line.
    func rightEdgeOfInk(onLine lineNumber: Int, pageWidth: CGFloat) -> CGFloat {
        let working = workingLines(pageWidth: pageWidth)
        let lineY = NotebookLayout.penStart(onLine: lineNumber).y
        let band = NotebookLayout.lineHeight * 0.65

        var edge = NotebookLayout.penStart(onLine: lineNumber).x

        for line in working where line.lineNumber == lineNumber || abs(line.bounds.midY - lineY) < band {
            edge = max(edge, line.bounds.maxX)
        }

        return edge
    }

    /// Group writing into side-by-side columns.
    func inkColumns(pageWidth: CGFloat) -> [InkColumn] {
        let lines = writtenLines()
        guard !lines.isEmpty else { return [] }

        let pageMid = pageWidth / 2
        let left = lines.filter { $0.bounds.midX < pageMid }
        let right = lines.filter { $0.bounds.midX >= pageMid }

        if !left.isEmpty, !right.isEmpty {
            return [
                InkColumn(lines: left.sorted { $0.lineNumber < $1.lineNumber }),
                InkColumn(lines: right.sorted { $0.lineNumber < $1.lineNumber }),
            ]
        }

        // Fall back to stroke-gap clustering when both sides sit near the middle.
        var clusters: [[WrittenLine]] = []
        var clusterStarts: [CGFloat] = []

        for line in lines.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            let start = line.bounds.minX
            if let last = clusterStarts.last, start - last <= columnGap {
                clusters[clusters.count - 1].append(line)
            } else {
                clusterStarts.append(start)
                clusters.append([line])
            }
        }

        return clusters.map { cluster in
            InkColumn(lines: cluster.sorted { $0.lineNumber < $1.lineNumber })
        }
    }

    /// Cut one row of writing wherever it leaves a wide blank space.
    ///
    /// A page with a single column of work has no such gaps, so this hands
    /// back the row exactly as it came in and nothing about the old behaviour
    /// changes.
    private func columnsAcross(_ row: [PlacedStroke]) -> [[PlacedStroke]] {
        var pieces: [[PlacedStroke]] = []

        // The right-hand edge of everything in the piece being built. Measured
        // against the furthest right we have reached rather than the previous
        // stroke, so a long division bar or a bracket drawn last does not look
        // like the start of a new column.
        var edge: CGFloat = 0

        for stroke in row.sorted(by: { $0.left < $1.left }) {
            if pieces.isEmpty || stroke.left - edge > columnGap {
                pieces.append([stroke])
                edge = stroke.right
            } else {
                pieces[pieces.count - 1].append(stroke)
                edge = max(edge, stroke.right)
            }
        }

        return pieces
    }

    /// Put the pieces in the order a person would read them: each column in
    /// full, top to bottom, left column first.
    ///
    /// Reading straight down the page instead would interleave the two
    /// columns, and the checker would try to follow a chain of steps that
    /// jumps back and forth between two separate pieces of working.
    private func inReadingOrder(_ pieces: [[PlacedStroke]]) -> [WrittenLine] {
        let starts = pieces.compactMap { $0.map(\.left).min() }.sorted()

        // Where each column begins. Same idea as grouping strokes into lines,
        // turned on its side.
        var columnStarts: [CGFloat] = []

        for start in starts {
            if let last = columnStarts.last, start - last <= columnGap { continue }
            columnStarts.append(start)
        }

        func column(of piece: [PlacedStroke]) -> Int {
            let left = piece.map(\.left).min() ?? 0
            return columnStarts.lastIndex { left >= $0 } ?? 0
        }

        let sorted = pieces.sorted { first, second in
            let columns = (column(of: first), column(of: second))

            if columns.0 != columns.1 { return columns.0 < columns.1 }
            return averageHeight(of: first) < averageHeight(of: second)
        }

        return sorted.map { piece in
            WrittenLine(
                lineNumber: Int(averageHeight(of: piece) / NotebookLayout.lineHeight),
                bounds: piece.dropFirst().reduce(piece[0].bounds) { $0.union($1.bounds) },
                strokes: movedToOrigin(piece.map(\.coordinates))
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
