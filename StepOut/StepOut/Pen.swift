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
    var colour: Color = Theme.ink
    var width: CGFloat = 3
    var isErasing = false

    /// A colour the student mixed themselves, kept beside the fixed ones so
    /// choosing it back does not mean finding it again.
    var custom: Color = .purple

    /// The everyday colours, in the order they appear in the palette. Deep
    /// rather than bright: these are pens on paper, not highlighters.
    static let colours: [Color] = [
        Theme.ink,
        Theme.sky,
        Theme.pink,
        Theme.yellow,
        Color(red: 0.13, green: 0.52, blue: 0.32),
        .white,
    ]

    /// The four swatches shown in the pen tray.
    static let paletteColours: [Color] = [
        Theme.ink,
        Theme.sky,
        Theme.pink,
        Theme.yellow,
    ]

    static let widths: [CGFloat] = [2, 4, 8]

    /// Follow the paper, so a change of page never leaves the pen invisible.
    ///
    /// Only moves a pen that was still on a default. Someone who has picked
    /// red means it, whatever colour the page is.
    func follow(_ paper: Paper) {
        if colour == Theme.ink && paper.isDark {
            colour = .white
        } else if colour == .white && !paper.isDark {
            colour = Theme.ink
        }
    }

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
