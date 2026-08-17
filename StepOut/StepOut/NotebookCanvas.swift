import PencilKit

/// The student's canvas.
///
/// Apple's floating tool palette is deliberately not used: it is a fixed-size
/// system control and too large for this page. PenPalette replaces it, and this
/// class covers the one thing that palette used to handle for us — being the
/// view that owns the undo history.
///
/// What the canvas reports (writing, pencil squeezes) is handled by
/// NotebookPage.Coordinator, not here.
final class NotebookCanvas: PKCanvasView {

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // becomeFirstResponder() is ignored while a view has no window, and a
        // view has none yet inside makeUIView. By here it does.
        guard window != nil else { return }

        becomeFirstResponder()
    }

    /// Never offer the system's editing menu.
    ///
    /// Holding a finger on the page means "pick up that piece of the tutor's
    /// writing" here. Left alone, iPadOS reads the same gesture as text
    /// editing and puts up Select All / Insert Space over the paper, which is
    /// both meaningless on a drawing and in the way of the gesture that was
    /// actually meant.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    /// Wipe the page in a way undo can put back.
    ///
    /// Assigning to `drawing` directly bypasses the undo history, which would
    /// leave the undo button lying about what it can restore.
    func erasePage() {
        let previous = drawing

        undoManager?.registerUndo(withTarget: self) { canvas in
            canvas.drawing = previous
        }

        drawing = PKDrawing()
    }
}
