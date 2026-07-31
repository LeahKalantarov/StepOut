import PencilKit
import SwiftUI

/// What the student is currently writing with.
///
/// Apple's own tool palette is a fixed-size system control, and it is bigger
/// than this page can spare. So we keep Apple's *tools* — their ink, their
/// pressure and tilt handling, their eraser — and only replace the buttons
/// that choose between them.
@Observable
final class Pen {
    var colour: Color = .black
    var width: CGFloat = 3
    var isErasing = false

    static let colours: [Color] = [.black, .blue, .red, .green]
    static let widths: [CGFloat] = [2, 4, 8]

    /// The PencilKit tool these settings add up to.
    var tool: PKTool {
        if isErasing {
            // Rubs out a whole stroke at a time rather than nibbling pixels,
            // which is what you want when a single digit came out wrong.
            return PKEraserTool(.vector)
        }

        return PKInkingTool(.pen, color: UIColor(colour), width: width)
    }
}
