import PencilKit

/// The student's canvas.
///
/// Apple's floating tool palette is deliberately not used: it is a fixed-size
/// system control and too large for this page. PenPalette replaces it, and
/// this class covers the two things that palette used to handle for us — the
/// pencil squeeze, and being the view that owns the undo history.
final class NotebookCanvas: PKCanvasView {

    /// Called when the student squeezes an Apple Pencil Pro.
    var onSqueeze: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // becomeFirstResponder() is ignored while a view has no window, and a
        // view has none yet inside makeUIView. By here it does.
        guard window != nil else { return }

        becomeFirstResponder()

        if pencilInteraction.delegate == nil {
            pencilInteraction.delegate = self
            addInteraction(pencilInteraction)
        }
    }

    private let pencilInteraction = UIPencilInteraction()

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

extension NotebookCanvas: UIPencilInteractionDelegate {
    // Implementing this replaces whatever the squeeze does system-wide, which
    // is the point: on this page it should always reach for the eraser.
    func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        guard squeeze.phase == .ended else { return }
        onSqueeze?()
    }
}
