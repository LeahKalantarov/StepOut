import SwiftUI
import UIKit

/// An invisible patch of paper that answers fingers and ignores the pencil.
///
/// Tutor writing needs somewhere to be tapped, but it sits over the canvas —
/// and anything laid over the canvas takes the pen strokes aimed at it. That
/// turned the space around the tutor's writing into paper you could not write
/// on, which is worse than having no gestures at all.
///
/// So the pencil is refused at hit-test time and falls through to the canvas
/// underneath, while taps and long presses from a finger are handled here.
struct FingerTapArea: UIViewRepresentable {
    var onDoubleTap: () -> Void
    var onLongPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PencilFallsThroughView()
        view.backgroundColor = .clear

        let finger = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = finger
        view.addGestureRecognizer(doubleTap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress)
        )
        longPress.minimumPressDuration = 0.45
        longPress.allowedTouchTypes = finger
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap, onLongPress: onLongPress)
    }

    final class Coordinator: NSObject {
        var onDoubleTap: () -> Void
        var onLongPress: () -> Void

        init(onDoubleTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onDoubleTap = onDoubleTap
            self.onLongPress = onLongPress
        }

        @objc func handleDoubleTap() {
            onDoubleTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            // Once per press, at the moment it is recognised, rather than again
            // for every stage of the gesture as the finger moves and lifts.
            guard recognizer.state == .began else { return }
            onLongPress()
        }
    }
}

/// Refuses the pencil so strokes reach the canvas below.
private final class PencilFallsThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let touches = event?.allTouches, touches.contains(where: { $0.type == .pencil }) {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}
