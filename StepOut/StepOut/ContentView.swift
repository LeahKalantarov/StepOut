import PencilKit
import SwiftUI

struct ContentView: View {
    // The whole page is one canvas, so writing can go anywhere on it.
    @State private var canvas = NotebookCanvas()

    @State private var problems: [Problem] = []
    @State private var currentIndex = 0

    // Which questions have been finished, for the ticks in the sidebar.
    @State private var solvedProblems: Set<Int> = []

    // Which ruled line to mark, and whether the mark is a cross or a tick.
    @State private var errorLine: Int?
    @State private var solvedLine: Int?

    @State private var feedback: Feedback?

    // True while we wait on the server, so Check can't be tapped twice. Only
    // Check: a check is allowed half a minute, and Clear has to keep working
    // for the whole of it.
    @State private var isChecking = false

    // The check on its way to the server, kept so clearing the page can call
    // it off.
    @State private var checkTask: Task<Void, Never>?

    // Counts down to hiding the feedback note.
    @State private var feedbackTask: Task<Void, Never>?

    private var problem: Problem? {
        problems.indices.contains(currentIndex) ? problems[currentIndex] : nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page
        }
        .task {
            await loadProblems()
        }
    }

    // MARK: - The list of questions

    var sidebar: some View {
        List {
            Section("Questions") {
                ForEach(problems) { problem in
                    Button {
                        select(problem)
                    } label: {
                        row(for: problem)
                    }
                    .listRowBackground(
                        problem.index == currentIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("StepOut")
    }

    func row(for problem: Problem) -> some View {
        HStack(spacing: 12) {
            Text("\(problem.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)

            Text(problem.equation)
                .foregroundStyle(.primary)

            Spacer()

            if solvedProblems.contains(problem.index) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - The page

    var page: some View {
        ZStack(alignment: .topLeading) {
            RuledPaper()

            marginMarks

            // The question, written onto the page a stroke at a time: what to
            // do, then the equation underneath once that line is finished.
            if let problem {
                HandwrittenLine(
                    text: problem.prompt,
                    origin: NotebookLayout.penStart(onLine: 0)
                )

                HandwrittenLine(
                    text: problem.equation,
                    origin: NotebookLayout.penStart(onLine: 1),
                    delay: HandwrittenLine.writingTime(for: problem.prompt) + 0.25
                )
            }

            NotebookPage(canvas: canvas)
        }
        .overlay(alignment: .top) {
            if let feedback {
                FeedbackNote(feedback: feedback)
                    .padding(.top, 24)
                    // Never swallow a pen stroke aimed at the page beneath it.
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !problems.isEmpty {
                    Text("\(currentIndex + 1) of \(problems.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear page", systemImage: "arrow.counterclockwise") {
                    clearPage()
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    checkTask = Task {
                        await runCheck()
                    }
                } label: {
                    Label(isChecking ? "Checking" : "Check", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)
            }
        }
    }

    /// Ticks and crosses in the left margin, beside the line they refer to.
    var marginMarks: some View {
        ZStack(alignment: .topLeading) {
            if let errorLine {
                mark("✗", color: .red, onLine: errorLine)
            }

            if let solvedLine {
                mark("✓", color: .green, onLine: solvedLine)
            }
        }
    }

    /// Place one mark in the margin, level with a given ruled line.
    func mark(_ symbol: String, color: Color, onLine lineNumber: Int) -> some View {
        Text(symbol)
            .font(.title2.bold())
            .foregroundStyle(color)
            .padding(.leading, 18)
            // Sit the mark just above the rule the writing rests on
            .padding(.top, CGFloat(lineNumber) * NotebookLayout.lineHeight + 8)
    }

    // MARK: - Actions

    func loadProblems() async {
        do {
            problems = try await fetchProblems()
        } catch {
            show(Feedback(text: "Could not reach the server.", tone: .bad))
        }
    }

    func select(_ problem: Problem) {
        currentIndex = problem.index
        clearPage()
    }

    func clearPage() {
        // A check already on its way would come back and mark writing that is
        // about to be wiped, so call it off first.
        checkTask?.cancel()

        canvas.drawing = PKDrawing()
        errorLine = nil
        solvedLine = nil
        hideFeedback()
    }

    /// Show a note over the page, and take it away again once it has been read.
    func show(_ newFeedback: Feedback) {
        feedbackTask?.cancel()

        withAnimation(.snappy) {
            feedback = newFeedback
        }

        // The cross in the margin is the lasting record of a mistake, so these
        // words don't have to sit there forever explaining themselves.
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(6))

            if !Task.isCancelled {
                withAnimation(.snappy) {
                    feedback = nil
                }
            }
        }
    }

    func hideFeedback() {
        feedbackTask?.cancel()

        withAnimation(.snappy) {
            feedback = nil
        }
    }

    func runCheck() async {
        isChecking = true
        defer { isChecking = false }

        errorLine = nil
        solvedLine = nil
        hideFeedback()

        // Bundle the page into lines, then send just the coordinates
        let lines = canvas.writtenLines()
        let rows = lines.map { RowData(strokes: $0.strokes) }

        do {
            let result = try await checkHandwriting(rows, problemIndex: problem?.index)

            // The page was cleared while we waited, so this verdict is about
            // writing that is no longer on it.
            if Task.isCancelled { return }

            let skipped = result.ignored ?? []

            if result.ok {
                if lines.isEmpty {
                    show(Feedback(text: "Write your first step underneath.", tone: .plain))
                } else if result.solved == true {
                    // Tick the last line that was written
                    solvedLine = lines.last?.lineNumber
                    solvedProblems.insert(currentIndex)
                    show(Feedback(text: "Solved. \(result.answer ?? "")", tone: .good, skipped: skipped))
                } else {
                    show(Feedback(text: "Correct so far. Keep going.", tone: .plain, skipped: skipped))
                }
            } else {
                // The server counts written lines from 1; turn that back into
                // the ruled line it was actually written on.
                if let step = result.errorStep, step - 1 < lines.count {
                    errorLine = lines[step - 1].lineNumber
                }

                show(Feedback(
                    text: result.message ?? "Something doesn't follow.",
                    tone: .bad,
                    skipped: skipped
                ))
            }
        } catch {
            // Clearing the page cancels the check, which is not a failure the
            // student needs telling about.
            if !Task.isCancelled {
                show(Feedback(text: "Could not reach the server.", tone: .bad))
            }
        }
    }
}

#Preview {
    ContentView()
}
