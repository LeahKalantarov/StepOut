import SwiftUI

struct ContentView: View {
    // Hardcoded for now. Step 3 is wrong on purpose.
    let steps = ["2x + 5 = 13", "2x = 8", "x = 5"]

    @State private var resultText = "Tap Check to test the API"

    var body: some View {
        VStack(spacing: 24) {
            Text("StepOut")
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps, id: \.self) { step in
                    Text(step)
                        .font(.title2)
                }
            }

            Button("Check my work") {
                Task {
                    await runCheck()
                }
            }
            .buttonStyle(.borderedProminent)

            Text(resultText)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
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
