import PencilKit
import SwiftUI

/// Where a finger gesture has got to.
enum GesturePhase {
    case began
    case moved
    case ended
}

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

    /// Called once the pencil has been still long enough to count as stopped.
    ///
    /// Worked out down here, on the pencil's own pen-up, rather than up in the
    /// view. Anything that touches SwiftUI state while a stroke is being drawn
    /// redraws the whole page under the student's hand, and a page carrying a
    /// sheet of notes and a graph cannot be redrawn at writing speed.
    let onSettled: () -> Void

    /// Called as the page is scrolled, with where the corner of the screen now
    /// sits on it. Sideways as well as down, because a page pinched larger
    /// than the screen can be moved either way.
    let onScroll: (CGPoint) -> Void

    /// Called as the page is pinched, with how much bigger it now is.
    let onZoom: (CGFloat) -> Void

    /// A finger tapped twice on the page, at a point in page coordinates.
    let onDoubleTap: (CGPoint) -> Void

    /// A finger was held down on the page, and then possibly dragged.
    let onHold: (CGPoint, GesturePhase) -> Void

    /// Two fingers pinched, with how much they have spread since they landed.
    let onPinch: (CGPoint, CGFloat, GesturePhase) -> Void

    /// Whether a point is on something the tutor wrote.
    ///
    /// Pinching means two things on this page — make the tutor's note bigger,
    /// or make the whole page bigger — and this is what tells them apart.
    /// Fingers landing on the tutor's writing resize it; fingers landing on
    /// paper zoom the page.
    let isTutorText: (CGPoint) -> Bool

    func makeUIView(context: Context) -> NotebookCanvas {
        // Only the pencil writes. A hand resting on the page is how people
        // write, and it leaves marks if fingers draw too. It also hands the
        // whole of touch back to scrolling, so one finger moves the page.
        canvas.drawingPolicy = .pencilOnly

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.showsVerticalScrollIndicator = false

        // A canvas is a scroll view, so it already knows how to be pinched —
        // it only had nowhere to go. Out to two thirds, for taking in a whole
        // sheet of notes at once; in to two and a half, for writing small
        // working in a gap without it turning into a scrawl.
        canvas.minimumZoomScale = 0.65
        canvas.maximumZoomScale = 2.5
        canvas.bouncesZoom = false

        canvas.delegate = context.coordinator

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)

        // Folding and unfolding the tutor's writing, done to the canvas rather
        // than to a layer over it. Anything laid over the canvas to catch a
        // tap catches the Pencil as well, and then there is a patch of page
        // that cannot be written on — which is the opposite of what folding
        // the writing away was for.
        let finger = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pageDoubleTapped)
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = finger
        canvas.addGestureRecognizer(doubleTap)

        let hold = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pageHeld)
        )
        hold.allowedTouchTypes = finger

        // Short, and forgiving about drift. Half a second of holding perfectly
        // still is a long time to wait to find out whether something can be
        // picked up at all, and the smallest movement while waiting used to
        // cancel it and scroll the page instead.
        hold.minimumPressDuration = 0.2
        hold.allowableMovement = 60

        // Asked at touch-down whether the finger landed on the tutor's writing,
        // so that everywhere else it gives up at once.
        hold.delegate = context.coordinator
        canvas.addGestureRecognizer(hold)

        // The reason a finger on the tutor's writing did nothing. A canvas is a
        // scroll view, and its pan starts the moment a finger moves — well
        // before a hold has had time to be a hold — so the page slid away
        // underneath and the writing was never picked up. Now the pan waits to
        // see whether the hold takes it. On plain paper the hold refuses the
        // touch outright, so there is nothing to wait for and scrolling is as
        // immediate as it ever was.
        canvas.panGestureRecognizer.require(toFail: hold)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pagePinched)
        )
        pinch.allowedTouchTypes = finger
        // Asked, before it starts, whether the fingers landed on the tutor's
        // writing. If they did not, it never begins and the canvas's own pinch
        // zooms the page instead.
        pinch.delegate = context.coordinator
        canvas.addGestureRecognizer(pinch)

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

        // Multiplied by the pinch, because a scroll view's content size is the
        // size the content is being shown at, not the size it was drawn at.
        // Setting the drawn size here while the page is pinched would tell the
        // canvas the paper had shrunk, and it would jump.
        let shown = CGSize(
            width: paper.width * uiView.zoomScale,
            height: paper.height * uiView.zoomScale
        )

        if uiView.contentSize != shown {
            uiView.contentSize = shown
        }

        context.coordinator.centre(uiView)

        // Hand the coordinator the current closures. They are rebuilt every
        // time the view is, and the coordinator outlives all of those copies.
        context.coordinator.onSqueeze = onSqueeze
        context.coordinator.onWriting = onWriting
        context.coordinator.onSettled = onSettled
        context.coordinator.onScroll = onScroll
        context.coordinator.onZoom = onZoom
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onHold = onHold
        context.coordinator.onPinch = onPinch
        context.coordinator.isTutorText = isTutorText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSqueeze: onSqueeze,
            onWriting: onWriting,
            onSettled: onSettled,
            onScroll: onScroll,
            onZoom: onZoom,
            onDoubleTap: onDoubleTap,
            onHold: onHold,
            onPinch: onPinch,
            isTutorText: isTutorText
        )
    }

    /// Listens to the canvas on the page's behalf.
    ///
    /// This has to be its own object rather than the canvas itself.
    /// `PKCanvasView` is a scroll view, and `PKCanvasViewDelegate` inherits
    /// from `UIScrollViewDelegate`, so a canvas set as its own delegate is a
    /// scroll view calling itself back mid-layout — it recurses until the app
    /// stops responding to touch altogether.
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate,
        UIGestureRecognizerDelegate {
        var onSqueeze: () -> Void
        var onWriting: () -> Void
        var onSettled: () -> Void
        var onScroll: (CGPoint) -> Void
        var onZoom: (CGFloat) -> Void
        var onDoubleTap: (CGPoint) -> Void
        var onHold: (CGPoint, GesturePhase) -> Void
        var onPinch: (CGPoint, CGFloat, GesturePhase) -> Void
        var isTutorText: (CGPoint) -> Bool

        init(
            onSqueeze: @escaping () -> Void,
            onWriting: @escaping () -> Void,
            onSettled: @escaping () -> Void,
            onScroll: @escaping (CGPoint) -> Void,
            onZoom: @escaping (CGFloat) -> Void,
            onDoubleTap: @escaping (CGPoint) -> Void,
            onHold: @escaping (CGPoint, GesturePhase) -> Void,
            onPinch: @escaping (CGPoint, CGFloat, GesturePhase) -> Void,
            isTutorText: @escaping (CGPoint) -> Bool
        ) {
            self.onSqueeze = onSqueeze
            self.onWriting = onWriting
            self.onSettled = onSettled
            self.onScroll = onScroll
            self.onZoom = onZoom
            self.onDoubleTap = onDoubleTap
            self.onHold = onHold
            self.onPinch = onPinch
            self.isTutorText = isTutorText
        }

        /// Decides which pinch this is before either of them starts.
        ///
        /// Only our own pinch is asked. Refusing it here leaves the canvas's
        /// built-in pinch to zoom the page, which is what should happen
        /// everywhere except on top of the tutor's own writing.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard gesture is UIPinchGestureRecognizer, let view = gesture.view else {
                return true
            }

            return isTutorText(gesture.location(in: view))
        }

        /// Turns away touches that landed on plain paper.
        ///
        /// A hold that never receives the touch fails immediately, which lets
        /// the scrolling waiting behind it start without a pause. Only the hold
        /// is filtered this way: a pinch arrives as two separate touches and
        /// the second one often lands off the writing, so it is judged as a
        /// whole in `gestureRecognizerShouldBegin` instead.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard gesture is UILongPressGestureRecognizer, let view = gesture.view else {
                return true
            }

            return isTutorText(touch.location(in: view))
        }

        // A scroll view reports a touch in its content coordinates, so these
        // points are already measured down the whole page rather than down
        // the screen — which is how the tutor's writing is placed too.
        @objc func pageDoubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            onDoubleTap(gesture.location(in: view))
        }

        @objc func pageHeld(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view, let phase = phase(of: gesture.state) else {
                return
            }

            onHold(gesture.location(in: view), phase)
        }

        @objc func pagePinched(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view, let phase = phase(of: gesture.state) else {
                return
            }

            onPinch(gesture.location(in: view), gesture.scale, phase)
        }

        /// A gesture cancelled has to end like any other, or whatever it picked
        /// up is left held: dropped halfway across the page with scrolling
        /// still switched off.
        private func phase(of state: UIGestureRecognizer.State) -> GesturePhase? {
            switch state {
            case .began: .began
            case .changed: .moved
            case .ended, .cancelled, .failed: .ended
            default: nil
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onWriting()
        }

        /// How long the pencil has to be still before the page counts as ready
        /// to read.
        ///
        /// Long on purpose. Anything shorter catches people between one step
        /// and the next — thinking, or reaching for the next line — and being
        /// stopped there is being interrupted rather than helped. Four seconds
        /// is longer than a pause inside a piece of working and shorter than
        /// the wait before you would wonder whether anything was going to
        /// happen at all.
        private static let stillFor: TimeInterval = 4

        /// The wait for a pen that has stopped, torn up by the next stroke.
        private var settling: DispatchWorkItem?

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            settling?.cancel()
            settling = nil
        }

        /// The pencil has been lifted.
        ///
        /// This fires once per stroke, unlike a drawing change, and only ever
        /// between strokes — which is exactly when it is safe to read the page.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            settling?.cancel()

            let quiet = DispatchWorkItem { [weak self] in
                self?.onSettled()
            }

            settling = quiet

            DispatchQueue.main.asyncAfter(
                deadline: .now() + Coordinator.stillFor,
                execute: quiet
            )
        }

        // The ruled paper and everything written on it are drawn behind the
        // canvas rather than inside it, so they have to be told to move with
        // it. Otherwise the ink scrolls and the lines under it stay put.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onScroll(scrollView.contentOffset)
        }

        // And to grow with it, for the same reason.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centre(scrollView)
            onZoom(scrollView.zoomScale)
            onScroll(scrollView.contentOffset)
        }

        /// Keep the page in the middle once it is smaller than the screen.
        ///
        /// A scroll view holds its content against the top-left corner, which
        /// looks like the page has slid into the corner rather than been made
        /// smaller. Padding the space around it puts it back in the middle,
        /// and does it for the ink and the paper at once: the paper is drawn
        /// against the same scroll position, so it follows without being told.
        func centre(_ scrollView: UIScrollView) {
            let across = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let down = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)

            let wanted = UIEdgeInsets(top: down, left: across, bottom: down, right: across)

            // Setting an inset moves the content, which comes back through
            // scrollViewDidScroll. Only changing it when it differs is what
            // stops that being a loop.
            guard scrollView.contentInset != wanted else { return }

            scrollView.contentInset = wanted
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
