import PencilKit
import SwiftUI

struct ContentView: View {
    // The whole page is one canvas, so writing can go anywhere on it.
    @State private var canvas = PKCanvasView()

    // The question being worked on. nil until the server answers.
    @State private var problem: Problem?

    @State private var resultText = ""

    // Which ruled line to mark, and whether the mark is a cross or a tick.
    @State private var errorLine: Int?
    @State private var solvedLine: Int?

    // Lines the server passed over, so a surprising result can be explained.
    @State private var skipped: [String] = []

    // True while we wait on the server, so the button can't be tapped twice.
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 0) {
            page
            toolbar
        }
        .task {
            await loadProblem(at: 0)
        }
    }

    // MARK: - The page

    var page: some View {
        ZStack(alignment: .topLeading) {
            RuledPaper()

            marginMarks

            // The question, written onto the page a stroke at a time: what to
            // do, then the equation underneath once that line is finished.
            if let problem {
                HandwrittenLine(
                    text: problem.prompt,
                    origin: NotebookLayout.penStart(onLine: 0)
                )

                HandwrittenLine(
                    text: problem.equation,
                    origin: NotebookLayout.penStart(onLine: 1),
                    delay: HandwrittenLine.writingTime(for: problem.prompt) + 0.25
                )
            }

            NotebookPage(canvas: canvas)
        }
    }

    /// Ticks and crosses in the left margin, beside the line they refer to.
    var marginMarks: some View {
        ZStack(alignment: .topLeading) {
            if let errorLine {
                mark("✗", color: .red, onLine: errorLine)
            }

            if let solvedLine {
                mark("✓", color: .green, onLine: solvedLine)
            }
        }
    }

    /// Place one mark in the margin, level with a given ruled line.
    func mark(_ symbol: String, color: Color, onLine lineNumber: Int) -> some View {
        Text(symbol)
            .font(.title2.bold())
            .foregroundStyle(color)
            .padding(.leading, 18)
            // Sit the mark just above the rule the writing rests on
            .padding(.top, CGFloat(lineNumber) * NotebookLayout.lineHeight + 8)
    }

    // MARK: - The controls

    var toolbar: some View {
        HStack(spacing: 16) {
            Button(isChecking ? "Checking..." : "Check my work") {
                Task {
                    await runCheck()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)

            Button("Clear") {
                clearPage()
            }
            .buttonStyle(.bordered)
            .disabled(isChecking)

            // Only offer the next problem once this one is finished
            if solvedLine != nil, let problem, problem.index + 1 < problem.total {
                Button("Next problem") {
                    Task {
                        await loadProblem(at: problem.index + 1)
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(resultText)
                    .foregroundStyle(errorLine == nil ? .secondary : Color.red)

                if !skipped.isEmpty {
                    Text("Skipped: \(skipped.joined(separator: "   "))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    func loadProblem(at index: Int) async {
        clearPage()

        do {
            problem = try await fetchProblem(at: index)
        } catch {
            resultText = "Could not load the problem."
        }
    }

    func clearPage() {
        canvas.drawing = PKDrawing()
        errorLine = nil
        solvedLine = nil
        skipped = []
        resultText = ""
    }

    func runCheck() async {
        isChecking = true
        defer { isChecking = false }

        errorLine = nil
        solvedLine = nil
        skipped = []
        resultText = "Reading your handwriting..."

        // Bundle the page into lines, then send just the coordinates
        let lines = canvas.writtenLines()
        let rows = lines.map { RowData(strokes: $0.strokes) }

        do {
            let result = try await checkHandwriting(rows, problemIndex: problem?.index)

            skipped = result.ignored ?? []

            if result.ok {
                if lines.isEmpty {
                    resultText = "Write your first step underneath."
                } else if result.solved == true {
                    // Tick the last line that was written
                    solvedLine = lines.last?.lineNumber
                    resultText = "Solved! \(result.answer ?? "")"
                } else {
                    resultText = "Correct so far. Keep going."
                }
            } else {
                // The server counts written lines from 1; turn that back into
                // the ruled line it was actually written on.
                if let step = result.errorStep, step - 1 < lines.count {
                    errorLine = lines[step - 1].lineNumber
                }
                resultText = result.message ?? "Something doesn't follow."
            }
        } catch {
            resultText = "Could not reach the server."
        }
    }
}

#Preview {
    ContentView()
}
