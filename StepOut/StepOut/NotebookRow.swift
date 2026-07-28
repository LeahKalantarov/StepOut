import PencilKit
import SwiftUI

// PencilKit is UIKit, so this wrapper lets SwiftUI use it.
struct NotebookRow: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        // .anyInput lets you draw with a mouse in the simulator, not just Pencil
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
