import SwiftUI

/// The paper itself: a warm page with blue rules and a red margin.
/// This is only the background — the writing happens on a canvas on top.
struct RuledPaper: View {
    var body: some View {
        Canvas { context, size in
            // Blue rules, evenly down the page
            var y = NotebookLayout.lineHeight
            while y < size.height {
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(rule, with: .color(.blue.opacity(0.18)), lineWidth: 1)

                y += NotebookLayout.lineHeight
            }

            // The red margin down the left
            var margin = Path()
            margin.move(to: CGPoint(x: NotebookLayout.marginWidth, y: 0))
            margin.addLine(to: CGPoint(x: NotebookLayout.marginWidth, y: size.height))
            context.stroke(margin, with: .color(.red.opacity(0.25)), lineWidth: 1)
        }
        .background(Color(red: 0.99, green: 0.98, blue: 0.94))
    }
}

#Preview {
    RuledPaper()
}
