import PencilKit
import SwiftUI

struct ContentView: View {
    // One canvas per step. Three lines of notebook paper.
    @State private var canvases = [PKCanvasView(), PKCanvasView(), PKCanvasView()]

    // Still hardcoded. Step C will read these from the handwriting.
    let steps = ["2x + 5 = 13", "2x = 8", "x = 5"]

    @State private var resultText = "Write your steps, then tap Check"

    // Which row failed. nil means nothing is marked wrong yet.
    @State private var wrongRow: Int?

    var body: some View {
        VStack(spacing: 20) {
            Text("StepOut")
                .font(.largeTitle)

            notebook

            HStack(spacing: 16) {
                Button("Check my work") {
                    Task {
                        await runCheck()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    clearAll()
                }
                .buttonStyle(.bordered)
            }

            Text(resultText)
                .multilineTextAlignment(.center)
                .foregroundStyle(wrongRow == nil ? Color.primary : Color.red)

            Spacer()
        }
        .padding()
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
        resultText = "Write your steps, then tap Check"
    }

    func runCheck() async {
        do {
            let result = try await checkSteps(steps)

            if result.ok {
                wrongRow = nil
                resultText = "All steps look good!"
            } else {
                // The API counts steps from 1, but rows start at 0
                wrongRow = (result.errorStep ?? 1) - 1
                resultText = result.message ?? "Something doesn't follow."
            }
        } catch {
            wrongRow = nil
            resultText = "Could not reach the server.\n\(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
