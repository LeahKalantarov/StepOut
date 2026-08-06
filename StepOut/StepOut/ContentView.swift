import PhotosUI
import PencilKit
import SwiftUI

struct ContentView: View {
    @State private var mathCanvases = [PKCanvasView(), PKCanvasView(), PKCanvasView()]
    @State private var tutorCanvas = PKCanvasView()

    @State private var resultText = "Write your steps — I'll check as you go."
    @State private var recognized: [String] = []
    @State private var wrongRow: Int?
    @State private var isSolved = false
    @State private var isChecking = false
    @State private var isTutorThinking = false

    @State private var lastResult: CheckResult?
    @State private var tutorNotes: [TutorNote] = []

    @State private var notes = ""
    @State private var attachedPhotos: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var sessionId = UUID().uuidString

    @State private var checkTask: Task<Void, Never>?
    @State private var tutorTask: Task<Void, Never>?
    @State private var notesTask: Task<Void, Never>?

    private let autoCheckDelay: Duration = .milliseconds(1400)
    private let pushbackDelay: Duration = .milliseconds(900)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("StepOut")
                        .font(.largeTitle)

                    Text(AppBuild.marker)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                contextSection

                notebook

                statusSection

                if !tutorNotes.isEmpty {
                    TutorNotesSection(notes: $tutorNotes)
                }

                HStack(spacing: 16) {
                    Button(isChecking ? "Checking…" : "Check now") {
                        checkTask = Task { await runCheck(manual: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)

                    Button("Clear") { clearAll() }
                        .buttonStyle(.bordered)
                        .disabled(isChecking)
                }
            }
            .padding()
        }
    }

    var contextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes for the tutor")
                .font(.subheadline.weight(.semibold))

            TextField("Class notes, what the problem is, what you tried…", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .onChange(of: notes) { _, newValue in
                    notesTask?.cancel()
                    notesTask = Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        if !Task.isCancelled {
                            _ = try? await saveNotes(sessionId: sessionId, notes: newValue)
                        }
                    }
                }

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Add photo", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.bordered)

                if !attachedPhotos.isEmpty {
                    Text("\(attachedPhotos.count) attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await attachPhoto(item) }
            }

            if !attachedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(attachedPhotos, id: \.self) { name in
                            Text(name)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    var notebook: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your steps")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(mathCanvases.indices, id: \.self) { row in
                    rowView(canvas: mathCanvases[row], label: "Step \(row + 1)", row: row)
                }

                rowView(
                    canvas: tutorCanvas,
                    label: "Talk to the tutor — e.g. “you are wrong”",
                    row: nil,
                    isTutorRow: true
                )
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.gray.opacity(0.3))
            }
        }
    }

    func rowView(canvas: PKCanvasView, label: String, row: Int?, isTutorRow: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            NotebookRow(canvas: canvas) {
                if isTutorRow {
                    scheduleTutorRead()
                } else if let row {
                    scheduleAutoCheck(from: row)
                }
            }
            .frame(height: isTutorRow ? 72 : 90)
            .background(row.map { wrongRow == $0 ? Color.red.opacity(0.1) : Color.clear } ?? Color.blue.opacity(0.04))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.gray.opacity(0.35)).frame(height: 1)
            }
            .overlay {
                if let row, wrongRow == row {
                    Rectangle().stroke(.red, lineWidth: 3)
                }
            }
        }
    }

    var statusSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if isChecking || isTutorThinking {
                    ProgressView().controlSize(.small)
                }

                Text(resultText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(resultColor)
            }

            if !recognized.isEmpty {
                VStack(spacing: 2) {
                    Text("Read as:")
                        .font(.caption)
                    ForEach(recognized.indices, id: \.self) { row in
                        Text(recognized[row])
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    var resultColor: Color {
        if wrongRow != nil { return .red }
        if isSolved { return .green }
        return .primary
    }

    func scheduleAutoCheck(from row: Int) {
        checkTask?.cancel()
        checkTask = Task {
            try? await Task.sleep(for: autoCheckDelay)
            if !Task.isCancelled {
                await runCheck(manual: false, changedRow: row)
            }
        }
    }

    func scheduleTutorRead() {
        tutorTask?.cancel()
        tutorTask = Task {
            try? await Task.sleep(for: pushbackDelay)
            if !Task.isCancelled {
                await readPushback()
            }
        }
    }

    func attachPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let base64 = data.base64EncodedString()
            let name = item.itemIdentifier ?? "photo-\(attachedPhotos.count + 1)"
            let response = try await uploadPhoto(
                sessionId: sessionId,
                filename: name,
                caption: "Student work photo",
                imageBase64: base64
            )
            attachedPhotos = response.photos ?? attachedPhotos
            photoItem = nil
        } catch {
            resultText = "Could not upload photo."
        }
    }

    func runCheck(manual: Bool, changedRow: Int? = nil) async {
        isChecking = true
        defer { isChecking = false }

        wrongRow = nil
        isSolved = false

        if manual {
            resultText = "Reading your handwriting…"
        } else {
            resultText = "Checking…"
        }

        let rows = mathCanvases.map { $0.asRowData() }

        do {
            let result = try await checkHandwriting(rows, sessionId: sessionId, notes: notes)
            lastResult = result
            recognized = result.recognized ?? []
            applyResult(result, manual: manual, changedRow: changedRow)
        } catch {
            if manual {
                resultText = "Could not reach the server.\n\(error.localizedDescription)"
            }
        }
    }

    func applyResult(_ result: CheckResult, manual: Bool, changedRow: Int?) {
        if result.ok {
            if recognized.isEmpty {
                resultText = "Write some steps first."
            } else if result.solved == true {
                isSolved = true
                resultText = "Solved! \(result.answer ?? "")"
                if result.extraSteps == true {
                    resultText += "\nYou can stop here."
                }
            } else {
                resultText = manual ? "Correct so far. Keep going." : "Looks good so far."
            }
        } else {
            if let step = result.errorStep {
                wrongRow = step - 1
            }
            resultText = result.message ?? "Something doesn't follow."
        }
    }

    func readPushback() async {
        guard let lastResult else {
            appendTutorNote("Check your work first, then tell me what feels wrong.")
            return
        }

        let row = tutorCanvas.asRowData()
        guard !row.strokes.isEmpty else { return }

        isTutorThinking = true
        defer { isTutorThinking = false }

        do {
            let message = try await readFreeform(row.strokes)
            guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }

            let response = try await askTutor(
                sessionId: sessionId,
                recognized: recognized,
                lastResult: lastResult,
                studentMessage: message,
                notes: notes
            )

            appendTutorNote(response.reply, prompt: response.prompt)
            resultText = response.isPushback == true
                ? "Got it — I'm looking at what you wrote."
                : resultText
        } catch {
            appendTutorNote("I couldn't reach the tutor right now.")
        }
    }

    func appendTutorNote(_ text: String, prompt: String? = nil) {
        withAnimation(.snappy) {
            tutorNotes.append(TutorNote(text: text, prompt: prompt))
        }
    }

    func clearAll() {
        checkTask?.cancel()
        tutorTask?.cancel()

        for canvas in mathCanvases {
            canvas.drawing = PKDrawing()
        }
        tutorCanvas.drawing = PKDrawing()

        wrongRow = nil
        isSolved = false
        recognized = []
        lastResult = nil
        tutorNotes = []
        attachedPhotos = []
        sessionId = UUID().uuidString
        resultText = "Write your steps — I'll check as you go."
    }
}

#Preview {
    ContentView()
}
