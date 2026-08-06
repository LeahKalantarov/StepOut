import Foundation

// The simulator shares the Mac's network, so localhost works there.
//
// A real iPad is a separate machine and has to be told where the Mac is. By
// name rather than by address: an IP changes every time the Mac joins a
// different network, and a wrong one here looks exactly like a broken app.
// The name follows the Mac around.
//
// It must be the same Wi-Fi, and some guest and campus networks stop devices
// talking to each other at all, in which case nothing here will help.
// Check the name with: scutil --get LocalHostName
#if targetEnvironment(simulator)
let serverAddress = "http://localhost:8000"
#else
let serverAddress = "http://MacBook-Pro-4.local:8000"
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

    // Which problem the student is on, so the server can catch a first line
    // that doesn't match the question.
    let problemIndex: Int?
}

/// A photograph of work done on real paper.
struct PhotoRequest: Codable {
    // Sent inside the JSON rather than as a file upload, so a photograph
    // travels the same way everything else does and there is only one piece of
    // networking code to keep working.
    let imageBase64: String

    let mediaType: String
    let problemIndex: Int?
}

// MARK: - Talking to the server

/// Send a JSON body to the server and read the answer back.
/// Everything below uses this, so the networking lives in one place.
///
/// The kind of answer expected is whatever the caller assigns the result to,
/// which is how one function can serve a check, a reading and a lesson.
private func post<Reply: Decodable>(path: String, jsonBody: Data) async throws -> Reply {
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

    return try decoder.decode(Reply.self, from: data)
}

/// The same, for a body we build from a Swift value.
private func post<Body: Encodable, Reply: Decodable>(
    path: String,
    body: Body
) async throws -> Reply {
    let encoder = JSONEncoder()

    // Turns problemIndex in Swift into "problem_index" in the JSON,
    // which is the spelling the Python side expects.
    encoder.keyEncodingStrategy = .convertToSnakeCase

    return try await post(path: path, jsonBody: encoder.encode(body))
}

/// Check steps that are already text, like "2x + 5 = 13".
func checkSteps(_ steps: [String]) async throws -> CheckResult {
    let body = try JSONEncoder().encode(["steps": steps])
    return try await post(path: "/check", jsonBody: body)
}

/// Send handwriting to be read and checked.
func checkHandwriting(_ rows: [RowData], problemIndex: Int?) async throws -> CheckResult {
    try await post(
        path: "/check-handwriting",
        body: HandwritingRequest(rows: rows, problemIndex: problemIndex)
    )
}

/// Send a photograph of working to be read and checked.
///
/// Given longer than a written check: the picture has to travel, be read, and
/// then be marked, and a photograph is a great deal more to send than a list
/// of coordinates.
func checkPhoto(_ jpeg: Data, problemIndex: Int?) async throws -> CheckResult {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    let body = try encoder.encode(
        PhotoRequest(
            imageBase64: jpeg.base64EncodedString(),
            mediaType: "image/jpeg",
            problemIndex: problemIndex
        )
    )

    var request = URLRequest(url: URL(string: serverAddress + "/check-photo")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    request.timeoutInterval = 60

    let (data, _) = try await URLSession.shared.data(for: request)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    return try decoder.decode(CheckResult.self, from: data)
}

/// Read handwriting as words rather than as algebra.
///
/// For the moments the tutor has asked something and is waiting to be
/// answered. Read as algebra, "yes" comes back as y times e times s.
func readWords(_ rows: [RowData]) async throws -> [String] {
    let reply: WordsReply = try await post(path: "/read-words", body: HandwritingRequest(
        rows: rows,
        problemIndex: nil
    ))

    return reply.words
}

/// Ask for a short lesson about a mistake.
func fetchLesson(for help: HelpContext) async throws -> Lesson {
    try await post(path: "/lesson", body: help)
}

/// Ask a question the student wrote, and get a short answer back.
func fetchAnswer(to question: Question) async throws -> String {
    let reply: AnswerReply = try await post(path: "/ask", body: question)
    return reply.answer
}

/// Ask for an example worked through, in answer to a question.
func fetchWorkedExample(for question: Question) async throws -> Lesson {
    try await post(path: "/work-through", body: question)
}

/// Ask the server for every problem, so the sidebar can list them.
func fetchProblems() async throws -> [Problem] {
    let url = URL(string: serverAddress + "/problems")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(ProblemList.self, from: data).problems
}
