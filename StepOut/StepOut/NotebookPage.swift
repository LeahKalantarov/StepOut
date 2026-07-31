import PencilKit
import SwiftUI

/// The layer the student writes on, covering the whole page.
///
/// It is see-through on purpose: the ruled paper sits behind it and needs to
/// stay visible.
struct NotebookPage: UIViewRepresentable {
    let canvas: NotebookCanvas

    /// What to write with. Passed as a plain value so that choosing a new
    /// colour or the eraser reaches the canvas the moment it is tapped.
    let tool: PKTool

    let onSqueeze: () -> Void

    func makeUIView(context: Context) -> NotebookCanvas {
        canvas.drawingPolicy = .anyInput

        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        canvas.onSqueeze = onSqueeze

        return canvas
    }

    func updateUIView(_ uiView: NotebookCanvas, context: Context) {
        uiView.tool = tool
    }
}
