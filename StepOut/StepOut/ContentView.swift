import PencilKit
import SwiftUI

struct ContentView: View {
    // One canvas per step. Three lines of notebook paper.
    @State private var canvases = [PKCanvasView(), PKCanvasView(), PKCanvasView()]

    // Still hardcoded. Step C will read these from the handwriting.
    let steps = ["2x + 5 = 13", "2x = 8", "x = 5"]

    @State private var resultText = "Write your steps, then tap Check"

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

            Spacer()
        }
        .padding()
    }

    var notebook: some View {
        VStack(spacing: 0) {
            ForEach(canvases.indices, id: \.self) { row in
                NotebookRow(canvas: canvases[row])
                    .frame(height: 90)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.gray.opacity(0.4))
                            .frame(height: 1)
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
        resultText = "Write your steps, then tap Check"
    }

    func runCheck() async {
        do {
            let result = try await checkSteps(steps)

            if result.ok {
                resultText = "All steps look good!"
            } else {
                resultText = "Step \(result.errorStep ?? 0): \(result.message ?? "")"
            }
        } catch {
            resultText = "Could not reach the server.\n\(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
