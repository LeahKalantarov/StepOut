import SwiftUI

/// Blocks plus ascending type — the name continues the climb.
struct StepOutWordmark: View {
    var height: CGFloat = 58

    private let letters = Array("StepOut")

    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.16) {
            blocks
                .frame(height: blockColumnHeight)

            HStack(alignment: .bottom, spacing: height * 0.01) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(.system(size: letterSize(at: index), weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .offset(y: -letterLift(at: index))
                }
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("StepOut")
    }

    private var blockColumnHeight: CGFloat {
        height * 0.88
    }

    private var blocks: some View {
        HStack(alignment: .bottom, spacing: height * 0.05) {
            IsometricBlock(color: Color(red: 1.0, green: 0.84, blue: 0.35), rise: 0.38)
            IsometricBlock(color: Color(red: 0.36, green: 0.83, blue: 0.98), rise: 0.66)
            IsometricBlock(color: Theme.pink, rise: 1.0)
        }
    }

    /// S matches the tallest block; each letter grows through the word.
    private func letterSize(at index: Int) -> CGFloat {
        let base = blockColumnHeight * 0.92
        let growth = height * 0.038
        return base + growth * CGFloat(index)
    }

    /// Baselines step up so the word reads as a continuing staircase.
    private func letterLift(at index: Int) -> CGFloat {
        height * 0.032 * CGFloat(index)
    }
}

private struct IsometricBlock: View {
    let color: Color
    let rise: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.78
            let h = geo.size.height * rise
            let d = w * 0.36

            Canvas { context, _ in
                let front = Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.closeSubpath()
                }

                let right = Path { path in
                    path.move(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: w + d, y: h - d * 0.45))
                    path.addLine(to: CGPoint(x: w + d, y: -d * 0.45))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.closeSubpath()
                }

                let top = Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: d, y: -d * 0.45))
                    path.addLine(to: CGPoint(x: w + d, y: -d * 0.45))
                    path.addLine(to: CGPoint(x: w, y: 0))
                    path.closeSubpath()
                }

                context.fill(front, with: .color(color))
                context.fill(right, with: .color(color.opacity(0.82)))
                context.fill(top, with: .color(color.opacity(0.94)))
            }
            .frame(width: w + d, height: h, alignment: .bottomLeading)
        }
        .aspectRatio(0.68, contentMode: .fit)
    }
}

#Preview {
    StepOutWordmark()
        .padding(24)
        .background(Color.white)
}
