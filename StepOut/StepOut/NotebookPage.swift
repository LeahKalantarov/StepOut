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

    /// How far down the paper runs.
    ///
    /// A canvas only scrolls as far as its content, and left alone PencilKit
    /// stretches that to fit the ink and no further — so there would be no
    /// blank paper below the last stroke to scroll down to.
    let pageHeight: CGFloat

    let onSqueeze: () -> Void

    /// Called whenever the student writes something.
    let onWriting: () -> Void

    /// Called as the page is scrolled, with how far down it now sits.
    let onScroll: (CGFloat) -> Void

    func makeUIView(context: Context) -> NotebookCanvas {
        canvas.drawingPolicy = .anyInput

        // One finger writes, so scrolling takes two. Without this the canvas
        // would read a scroll as a stroke and draw a line across the page.
        canvas.panGestureRecognizer.minimumNumberOfTouches = 2

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.showsVerticalScrollIndicator = false

        canvas.delegate = context.coordinator

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)

        return canvas
    }

    func updateUIView(_ uiView: NotebookCanvas, context: Context) {
        uiView.tool = tool

        // Set from out here, never from inside the canvas's own layout.
        // PencilKit works out how to tile the drawing from the content size,
        // so changing it mid-layout sends it round in circles until the stack
        // runs out — which it does on the first touch.
        let paper = CGSize(
            width: uiView.bounds.width,
            height: max(pageHeight, uiView.bounds.height)
        )

        if uiView.contentSize != paper {
            uiView.contentSize = paper
        }

        // Hand the coordinator the current closures. They are rebuilt every
        // time the view is, and the coordinator outlives all of those copies.
        context.coordinator.onSqueeze = onSqueeze
        context.coordinator.onWriting = onWriting
        context.coordinator.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSqueeze: onSqueeze, onWriting: onWriting, onScroll: onScroll)
    }

    /// Listens to the canvas on the page's behalf.
    ///
    /// This has to be its own object rather than the canvas itself.
    /// `PKCanvasView` is a scroll view, and `PKCanvasViewDelegate` inherits
    /// from `UIScrollViewDelegate`, so a canvas set as its own delegate is a
    /// scroll view calling itself back mid-layout — it recurses until the app
    /// stops responding to touch altogether.
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var onSqueeze: () -> Void
        var onWriting: () -> Void
        var onScroll: (CGFloat) -> Void

        init(
            onSqueeze: @escaping () -> Void,
            onWriting: @escaping () -> Void,
            onScroll: @escaping (CGFloat) -> Void
        ) {
            self.onSqueeze = onSqueeze
            self.onWriting = onWriting
            self.onScroll = onScroll
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onWriting()
        }

        // The ruled paper and everything written on it are drawn behind the
        // canvas rather than inside it, so they have to be told to move with
        // it. Otherwise the ink scrolls and the lines under it stay put.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset.y)
        }

        // Implementing this replaces whatever the squeeze does system-wide,
        // which is the point: on this page it should always reach for the
        // eraser.
        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard squeeze.phase == .ended else { return }
            onSqueeze()
        }
    }
}
