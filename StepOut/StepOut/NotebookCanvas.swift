import PencilKit

/// The student's canvas, carrying Apple's floating tool palette.
///
/// This is the same palette Notes and Freeform use, and it brings the pen,
/// pencil, marker, eraser, lasso, colours, thickness and undo with it.
///
/// The palette follows whichever view is first responder, so claiming that
/// role is what puts it on screen. That is also what makes the palette's undo
/// and redo buttons reach this canvas.
final class NotebookCanvas: PKCanvasView {
    // Held for as long as the canvas lives. The palette stops working if its
    // picker is released, and SwiftUI is free to rebuild the surrounding
    // NotebookPage struct as often as it likes.
    private let toolPicker = PKToolPicker()

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // becomeFirstResponder() is ignored while a view has no window, and a
        // view has none yet inside makeUIView. By here it does.
        guard window != nil else { return }

        // Finger and pencil both draw on this page, so the palette's "Draw
        // with finger" switch would have nothing left to change.
        toolPicker.showsDrawingPolicyControls = false

        toolPicker.addObserver(self)
        toolPicker.setVisible(true, forFirstResponder: self)
        becomeFirstResponder()
    }
}
