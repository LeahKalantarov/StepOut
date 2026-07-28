import Foundation

// Simulator can use localhost. A real iPad needs your Mac's IP.
let apiAddress = "http://localhost:8000/check"
// let apiAddress = "http://10.0.0.22:8000/check"

func checkSteps(_ steps: [String]) async throws -> CheckResult {
    var request = URLRequest(url: URL(string: apiAddress)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["steps": steps])

    let (data, _) = try await URLSession.shared.data(for: request)

    // Turns "error_step" in the JSON into errorStep in Swift
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    return try decoder.decode(CheckResult.self, from: data)
}
