import PencilKit

// PencilKit stores a drawing as smooth curves with pressure and tilt.
// MyScript only wants plain x/y coordinates, so we walk each stroke and
// sample points along it.

// How far apart to sample, in points. Smaller means more detail but a
// bigger request; 2 keeps the shape of handwriting without being wasteful.
private let sampleSpacing: CGFloat = 2

extension PKCanvasView {
    /// Convert everything drawn on this canvas into coordinates for the server.
    func asRowData() -> RowData {
        var strokes: [StrokeData] = []

        for stroke in drawing.strokes {
            var xs: [Double] = []
            var ys: [Double] = []

            for point in stroke.path.interpolatedPoints(by: .distance(sampleSpacing)) {
                // A stroke can carry its own transform, so apply it to get
                // the position the student actually sees on screen.
                let location = point.location.applying(stroke.transform)
                xs.append(location.x)
                ys.append(location.y)
            }

            // A single dot is not enough for the recognizer to work with.
            if xs.count >= 2 {
                strokes.append(StrokeData(x: xs, y: ys))
            }
        }

        return RowData(strokes: strokes)
    }
}
