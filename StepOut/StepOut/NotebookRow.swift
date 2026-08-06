import PencilKit
import SwiftUI

struct NotebookRow: UIViewRepresentable {
    let canvas: PKCanvasView
    var onDrawingChange: (() -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChange: onDrawingChange)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onDrawingChange: (() -> Void)?

        init(onDrawingChange: (() -> Void)?) {
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChange?()
        }
    }
}
