import SwiftUI

/// Slides over the notebook when Questions is tapped on the rail.
struct QuestionsDrawer: View {
    let problems: [Problem]
    let currentIndex: Int
    let solvedProblems: Set<Int>
    let onSelect: (Problem) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.ink.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Questions")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(Theme.yellow, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Theme.sky)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(problems) { problem in
                            Button {
                                onSelect(problem)
                                onClose()
                            } label: {
                                row(for: problem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(width: 320)
            .background(Theme.paper)
            .overlay(
                Rectangle()
                    .strokeBorder(Theme.ink, lineWidth: Theme.outline)
            )
        }
    }

    private func row(for problem: Problem) -> some View {
        let chosen = problem.index == currentIndex

        return HStack(spacing: 12) {
            Text("\(problem.index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 22, alignment: .trailing)

            Text(problem.equation)
                .font(.callout.weight(chosen ? .bold : .regular))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if solvedProblems.contains(problem.index) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.13, green: 0.52, blue: 0.32))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(chosen ? Theme.yellow : Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: chosen ? Theme.outline : 1)
        )
    }
}
