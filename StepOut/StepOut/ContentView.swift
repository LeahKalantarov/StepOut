import PencilKit
import SwiftUI

struct ContentView: View {
    // One canvas per step. Three lines of notebook paper.
    @State private var canvases = [PKCanvasView(), PKCanvasView(), PKCanvasView()]

    @State private var resultText = "Write your steps, then tap Check"

    // What the recognizer thought each row said, shown so the student can
    // tell a math mistake apart from messy handwriting.
    @State private var recognized: [String] = []

    // Which row failed. nil means nothing is marked wrong yet.
    @State private var wrongRow: Int?

    // True once the student has reached the answer, so we can say to stop.
    @State private var isSolved = false

    // True while we wait on the server, so the button can't be tapped twice.
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 20) {
            Text("StepOut")
                .font(.largeTitle)

            notebook

            HStack(spacing: 16) {
                Button(isChecking ? "Checking..." : "Check my work") {
                    Task {
                        await runCheck()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)

                Button("Clear") {
                    clearAll()
                }
                .buttonStyle(.bordered)
                .disabled(isChecking)
            }

            Text(resultText)
                .multilineTextAlignment(.center)
                .foregroundStyle(resultColor)

            if !recognized.isEmpty {
                VStack(spacing: 2) {
                    Text("Read as:")
                        .font(.caption)
                    // Keyed by position, not by text: two rows can easily read
                    // the same, and duplicate ids confuse SwiftUI.
                    ForEach(recognized.indices, id: \.self) { row in
                        Text(recognized[row])
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // Red for a bad step, green once solved, plain otherwise.
    var resultColor: Color {
        if wrongRow != nil { return .red }
        if isSolved { return .green }
        return .primary
    }

    var notebook: some View {
        VStack(spacing: 0) {
            ForEach(canvases.indices, id: \.self) { row in
                NotebookRow(canvas: canvases[row])
                    .frame(height: 90)
                    .background(wrongRow == row ? Color.red.opacity(0.1) : Color.clear)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.gray.opacity(0.4))
                            .frame(height: 1)
                    }
                    .overlay {
                        // Red outline only on the row that failed
                        if wrongRow == row {
                            Rectangle()
                                .stroke(.red, lineWidth: 3)
                        }
                    }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.gray.opacity(0.3))
        }
    }

    func clearAll() {
        for canvas in canvases {
            canvas.drawing = PKDrawing()
        }
        wrongRow = nil
        isSolved = false
        recognized = []
        resultText = "Write your steps, then tap Check"
    }

    func runCheck() async {
        isChecking = true
        defer { isChecking = false }

        wrongRow = nil
        isSolved = false
        recognized = []
        resultText = "Reading your handwriting..."

        // Turn each row of ink into coordinates the server can read
        let rows = canvases.map { $0.asRowData() }

        do {
            let result = try await checkHandwriting(rows)

            recognized = result.recognized ?? []

            if result.ok {
                if recognized.isEmpty {
                    resultText = "Write some steps first."
                } else if result.solved == true {
                    isSolved = true
                    resultText = "Solved! \(result.answer ?? "")"

                    if result.extraSteps == true {
                        resultText += "\nYou can stop here — the rest isn't needed."
                    }
                } else {
                    resultText = "Correct so far. Keep going."
                }
            } else {
                // The API counts rows from 1, but our array starts at 0
                if let step = result.errorStep {
                    wrongRow = step - 1
                }
                resultText = result.message ?? "Something doesn't follow."
            }
        } catch {
            resultText = "Could not reach the server.\n\(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
