import Foundation

#if targetEnvironment(simulator)
let serverAddress = "http://localhost:8000"
#else
let serverAddress = "http://10.0.0.29:8000"
#endif

struct StrokeData: Codable {
    let x: [Double]
    let y: [Double]
}

struct RowData: Codable {
    let strokes: [StrokeData]
}

struct HandwritingRequest: Codable {
    let rows: [RowData]
    let sessionId: String?
    let notes: String?
}

struct TutorRequestBody: Codable {
    let sessionId: String?
    let recognized: [String]
    let checkResult: TutorCheckPayload
    let studentMessage: String?
    let notes: String?
}

/// Nested check result for the tutor endpoint — mirrors backend keys.
struct TutorCheckPayload: Codable {
    let ok: Bool
    let errorStep: Int?
    let message: String?
    let reason: String?
    let expectedAnswer: String?
    let studentAnswer: String?
    let solved: Bool?
    let answer: String?
}

struct NotesRequestBody: Codable {
    let sessionId: String
    let notes: String
}

struct PhotoRequestBody: Codable {
    let sessionId: String
    let filename: String
    let caption: String?
    let imageBase64: String?
}

private let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.keyEncodingStrategy = .convertToSnakeCase
    return value
}()

private let decoder: JSONDecoder = {
    let value = JSONDecoder()
    value.keyDecodingStrategy = .convertFromSnakeCase
    return value
}()

private func post<Response: Decodable>(path: String, body: Encodable, timeout: TimeInterval = 30) async throws -> Response {
    var request = URLRequest(url: URL(string: serverAddress + path)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(body)
    request.timeoutInterval = timeout

    let (data, _) = try await URLSession.shared.data(for: request)
    return try decoder.decode(Response.self, from: data)
}

func checkSteps(_ steps: [String]) async throws -> CheckResult {
    struct Body: Encodable { let steps: [String] }
    return try await post(path: "/check", body: Body(steps: steps))
}

func checkHandwriting(_ rows: [RowData], sessionId: String, notes: String?) async throws -> CheckResult {
    let body = HandwritingRequest(rows: rows, sessionId: sessionId, notes: notes)
    return try await post(path: "/check-handwriting", body: body)
}

func saveNotes(sessionId: String, notes: String) async throws -> NotesUploadResponse {
    try await post(path: "/context/notes", body: NotesRequestBody(sessionId: sessionId, notes: notes))
}

func uploadPhoto(sessionId: String, filename: String, caption: String?, imageBase64: String?) async throws -> PhotoUploadResponse {
    try await post(
        path: "/context/photo",
        body: PhotoRequestBody(sessionId: sessionId, filename: filename, caption: caption, imageBase64: imageBase64),
        timeout: 45
    )
}

func askTutor(
    sessionId: String,
    recognized: [String],
    lastResult: CheckResult,
    studentMessage: String?,
    notes: String?
) async throws -> TutorResponse {
    let payload = TutorCheckPayload(
        ok: lastResult.ok,
        errorStep: lastResult.errorStep,
        message: lastResult.message,
        reason: lastResult.reason,
        expectedAnswer: lastResult.expectedAnswer,
        studentAnswer: lastResult.studentAnswer,
        solved: lastResult.solved,
        answer: lastResult.answer
    )

    return try await post(
        path: "/tutor/respond",
        body: TutorRequestBody(
            sessionId: sessionId,
            recognized: recognized,
            checkResult: payload,
            studentMessage: studentMessage,
            notes: notes
        )
    )
}

/// Send tutor-row ink to MyScript via a one-row handwriting check, return joined text.
func readFreeform(_ strokes: [StrokeData]) async throws -> String {
    let result = try await checkHandwriting([RowData(strokes: strokes)], sessionId: nil, notes: nil)
    return result.recognized?.joined(separator: " ") ?? ""
}

extension CheckResult {
    func tutorPayload() -> TutorCheckPayload {
        TutorCheckPayload(
            ok: ok,
            errorStep: errorStep,
            message: message,
            reason: reason,
            expectedAnswer: expectedAnswer,
            studentAnswer: studentAnswer,
            solved: solved,
            answer: answer
        )
    }
}
