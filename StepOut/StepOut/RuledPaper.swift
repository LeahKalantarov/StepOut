import SwiftUI

/// The paper behind everything: rules or dots, a margin, and a shade.
///
/// This is only the background — the writing happens on a canvas on top.
struct RuledPaper: View {
    let paper: Paper

    var body: some View {
        Canvas { context, size in
            switch paper.ruling {
            case .ruled:
                drawRules(in: context, size: size)
            case .dotted:
                drawDots(in: context, size: size)
            case .plain:
                break
            }

            // The margin stays whatever the ruling is: the ticks and crosses
            // live in it, so it has to be clear where it ends.
            var margin = Path()
            margin.move(to: CGPoint(x: NotebookLayout.marginWidth, y: 0))
            margin.addLine(to: CGPoint(x: NotebookLayout.marginWidth, y: size.height))
            context.stroke(margin, with: .color(paper.margin), lineWidth: 1)
        }
        .background(paper.background)
    }

    private func drawRules(in context: GraphicsContext, size: CGSize) {
        var y = NotebookLayout.lineHeight

        while y < size.height {
            var rule = Path()
            rule.move(to: CGPoint(x: 0, y: y))
            rule.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(rule, with: .color(paper.rule), lineWidth: 1)

            y += NotebookLayout.lineHeight
        }
    }

    /// Dots sit on the same rules, spaced across at half a line, so writing
    /// lands in the same places whichever paper is chosen.
    private func drawDots(in context: GraphicsContext, size: CGSize) {
        let step = NotebookLayout.lineHeight / 2
        let radius: CGFloat = 1.3

        var y = NotebookLayout.lineHeight

        while y < size.height {
            var x = NotebookLayout.marginWidth + step

            while x < size.width {
                let dot = Path(
                    ellipseIn: CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                context.fill(dot, with: .color(paper.rule))

                x += step
            }

            y += step
        }
    }
}

#Preview {
    RuledPaper(paper: Paper())
}
