import Foundation

// The simulator shares the Mac's network, so localhost works there.
// A real iPad is a separate machine, so it needs the Mac's Wi-Fi address.
// Find it with: ipconfig getifaddr en0
#if targetEnvironment(simulator)
let serverAddress = "http://localhost:8000"
#else
let serverAddress = "http://10.0.0.29:8000"
#endif

// MARK: - What we send when the student writes by hand

// One continuous pen line, as two lists of coordinates.
struct StrokeData: Codable {
    let x: [Double]
    let y: [Double]
}

// One line of notebook paper.
struct RowData: Codable {
    let strokes: [StrokeData]
}

struct HandwritingRequest: Codable {
    let rows: [RowData]
}

// MARK: - Talking to the server

/// Send a JSON body to the server and read the answer back.
/// Both checks below use this, so the networking lives in one place.
private func post(path: String, jsonBody: Data) async throws -> CheckResult {
    var request = URLRequest(url: URL(string: serverAddress + path)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonBody

    // Handwriting has to travel to MyScript and back, so allow extra time.
    request.timeoutInterval = 30

    let (data, _) = try await URLSession.shared.data(for: request)

    // Turns "error_step" in the JSON into errorStep in Swift
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    return try decoder.decode(CheckResult.self, from: data)
}

/// Check steps that are already text, like "2x + 5 = 13".
func checkSteps(_ steps: [String]) async throws -> CheckResult {
    let body = try JSONEncoder().encode(["steps": steps])
    return try await post(path: "/check", jsonBody: body)
}

/// Send handwriting to be read and checked.
func checkHandwriting(_ rows: [RowData]) async throws -> CheckResult {
    let body = try JSONEncoder().encode(HandwritingRequest(rows: rows))
    return try await post(path: "/check-handwriting", jsonBody: body)
}
