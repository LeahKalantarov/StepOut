import PencilKit
import SwiftUI

/// One canvas covering the whole page, so you can write anywhere on it.
///
/// It is see-through on purpose: the ruled paper sits behind it and needs to
/// stay visible.
struct NotebookPage: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
