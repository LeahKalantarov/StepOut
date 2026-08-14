import Foundation

// Where the server lives.
//
// Set StepOutServer in Info.plist to a hosted https address and the app talks
// to that from anywhere. Leave it empty while building and it falls back to
// the Mac on this Wi-Fi.
//
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
let serverAddress: String = {
    let hosted = Bundle.main.object(forInfoDictionaryKey: "StepOutServer") as? String

    if let hosted, !hosted.trimmingCharacters(in: .whitespaces).isEmpty {
        return hosted.trimmingCharacters(in: .whitespaces)
    }

    #if targetEnvironment(simulator)
    return "http://localhost:8000"
    #else
    return "http://MacBook-Pro-4.local:8000"
    #endif
}()

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

    // The question this page is marked against, so the server can catch a
    // first line that doesn't follow from it. Nil for a page with no question
    // on it, where we only check that each line follows the one above.
    var problemText: String? = nil

    // How the student wants to be spoken to.
    var style: String? = nil

    // What the tutor knows about them from before today.
    var history: [String]? = nil
}

struct PhotoRequest: Codable {
    let image: String

    // What the student wants done with the page, in their words. Empty means
    // they didn't say, and the page itself has to suggest what it is for.
    let instruction: String?
}

/// What came back from a photographed page: a sheet of notes to print on it,
/// questions to work through, or both.
struct PageReading: Codable {
    let sheet: NoteSheet?
    let problems: [Problem]

    /// Why nothing came back, when the fault was the server's rather than the
    /// photograph's. Nil means the picture was read — an empty reading then
    /// really is a page with nothing on it to teach from, and saying so is
    /// the truth. Saying so when the server never reached the model is not,
    /// and it sends someone off to photograph the same page again.
    var trouble: String?
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

    // Handwriting travels to MyScript and back, and a photographed page is
    // read and then taught from, which takes longer still.
    request.timeoutInterval = 120

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

/// Asking for a lesson: what went wrong, and how to talk about it.
///
/// `HelpContext` arrives from the server and goes back out again; the voice is
/// the student's own setting and is added here rather than kept on it.
struct LessonRequest: Codable {
    let wrongLine: String
    let question: String?
    let previousLine: String?
    let reason: String?
    let style: String?
    let history: [String]?

    init(_ help: HelpContext, style: String, history: [String]) {
        wrongLine = help.wrongLine
        question = help.question
        previousLine = help.previousLine
        reason = help.reason
        self.style = style
        self.history = history
    }
}

/// Send handwriting to be read and checked.
func checkHandwriting(
    _ rows: [RowData],
    problemText: String?,
    style: String,
    history: [String]
) async throws -> CheckResult {
    try await post(
        path: "/check-handwriting",
        body: HandwritingRequest(
            rows: rows,
            problemText: problemText,
            style: style,
            history: history
        )
    )
}

/// Send a photograph of a page, and say what to do with it.
///
/// Both lists can come back empty, and that is an ordinary answer rather than
/// a failure: the picture may have been of a blurred desk, or of a page with
/// nothing on it this app knows how to teach or mark.
func readPhoto(_ jpeg: Data, asking instruction: String?) async throws -> PageReading {
    try await post(
        path: "/read-photo",
        body: PhotoRequest(
            image: jpeg.base64EncodedString(),
            instruction: instruction
        )
    )
}

/// Read handwriting as words rather than as algebra.
///
/// For the moments the tutor has asked something and is waiting to be
/// answered. Read as algebra, "yes" comes back as y times e times s.
func readWords(_ rows: [RowData]) async throws -> [String] {
    let reply: WordsReply = try await post(path: "/read-words", body: HandwritingRequest(rows: rows))

    return reply.words
}

/// Ask for a short lesson about a mistake.
func fetchLesson(for help: HelpContext, style: String, history: [String]) async throws -> Lesson {
    try await post(path: "/lesson", body: LessonRequest(help, style: style, history: history))
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
