import PencilKit
import SwiftUI
import UIKit

struct ContentView: View {
    // The whole page is one canvas, so writing can go anywhere on it.
    @State private var canvas = NotebookCanvas()

    @State private var pen = Pen()

    @State private var problems: [Problem] = []
    @State private var currentIndex = 0

    // Which questions have been finished, for the ticks in the sidebar.
    @State private var solvedProblems: Set<Int> = []

    // Which ruled line to mark, and whether the mark is a cross or a tick.
    @State private var errorLine: Int?
    @State private var solvedLine: Int?

    // Where on the page those two lines were written, so the writing itself
    // can be marked and not just the margin beside it. A tick eight inches to
    // the left of the answer is a footnote; a ring around the answer is the
    // thing a teacher actually does with a red pen.
    @State private var errorInk: CGRect?
    @State private var solvedInk: CGRect?

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

    // The page: how it is ruled, what shade, and every ink colour that
    // depends on those.
    @State private var paper = Paper()

    // True while the tutor is waiting on the server. Without a sign of this,
    // a lesson that takes a few seconds looks like nothing happening, and the
    // obvious thing to do is press Check.
    @State private var thinking = false

    // MARK: Asking for help

    // What the tutor has offered. Non-nil means the question is on the page
    // and the answer written under it counts for something.
    @State private var offer: Offer?

    // How the last check read the student's writing, so a question about it
    // can be asked with the working attached.
    @State private var lastRead: [String] = []

    // The step that was wrong last time, to notice when it is the same one
    // coming back rather than a fresh mistake.
    @State private var lastWrongLine: String?

    // The line the question was written on. Kept for placing a reply on the
    // page, but strokes written after the offer are what we actually read.
    @State private var offerLine: Int?

    // How much ink was on the page when the question appeared. Anything added
    // after that is treated as the answer, which is far more reliable than
    // guessing from height alone.
    @State private var strokesWhenOffered = 0

    // What the answer was last read as. Held on to so that a reply is only
    // acted on when it changes, rather than every time a stroke moves.
    @State private var answered: Reply?

    // What the answer looked like when it was last read, so that carrying on
    // with the problem underneath does not send the same unchanged "yes" off
    // to be recognised over and over.
    @State private var answerSeen: CGRect?

    // Waits for a pause in the writing before reading the reply, so we don't
    // try to read "yes" while the y is still being drawn.
    @State private var replyTask: Task<Void, Never>?

    // Everything the tutor has written on the page: what went wrong, the offer
    // of help, and any lesson that followed.
    //
    // Deliberately not the feedback note. A note is the app talking — it can
    // say "could not reach the server" and then get out of the way. This is
    // the tutor talking, in its own hand, and it stays put like anything else
    // written on paper.
    @State private var tutorLines: [TutorLine] = []

    // How much of the page is on screen at once.
    @State private var visibleHeight: CGFloat = 0

    // How far the paper runs, and how far down it we have scrolled.
    @State private var pageHeight: CGFloat = 0
    @State private var scrolledBy: CGFloat = 0

    // Whether the tutor writes in a panel of its own rather than on the page.
    @State private var tutorApart = false

    // When the tutor started its current sitting of writing, and which sitting
    // that is. Non-nil means the pen is still moving and can be stopped.
    @State private var writingSince: Date?
    @State private var writingBatch: UUID?
    @State private var writingTask: Task<Void, Never>?

    // Batches the student has folded away so the tutor's writing does not
    // keep eating the page.
    @State private var collapsedBatches: Set<UUID> = []

    // The batch a long press opened the keep-or-remove menu for.
    @State private var batchMenu: TutorBatch?

    // Which way a picture is being brought in, and what for.
    @State private var photoChoice: PhotoChoice?
    @State private var photoPurpose: PhotoPurpose = .markWork

    // Whether the problems on offer were read off a photographed worksheet
    // rather than sent by the server, so the drawer can say where they
    // came from and offer a way back to the built-in ones.
    @State private var problemsFromAssignment = false

    // How wide the notebook is, so the tutor can use the full line.
    @State private var pageWidth: CGFloat = 700

    @State private var showQuestions = false
    @State private var showMore = false

    private var problem: Problem? {
        problems.indices.contains(currentIndex) ? problems[currentIndex] : nil
    }

    /// How wide a column the tutor writes in.
    ///
    /// The same in both layouts, and narrower than the page on purpose. It
    /// means a line wrapped for the page still fits the panel, so moving the
    /// tutor from one to the other never has to break its writing up again —
    /// and half-written text does not jump about mid-sentence.
    private let tutorWidth: CGFloat = 380

    /// How wide the tutor writes. Full width on the page; fixed in the panel
    /// so toggling layouts does not have to re-break every line.
    private var tutorWritableWidth: CGFloat {
        tutorApart ? tutorWidth : max(200, pageWidth - NotebookLayout.marginWidth - 24)
    }

    /// Height of the tutor's handwriting — a little smaller than the question.
    private let tutorHeight: CGFloat = 18

    /// Narrowest column the tutor will write in beside the student's work.
    ///
    /// Without a floor, a remark that starts an inch from the right edge gets
    /// wrapped into two words a line all the way down the margin, which is
    /// decoding rather than reading. Below this the tutor moves under the work
    /// and uses the whole width instead.
    private let leastTutorColumn: CGFloat = 300

    /// Lines sit closer together in the panel than on ruled paper.

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                appHeader
                page
            }
            // Kept on the page rather than on the whole screen: two dialogs
            // hung off the same view get in each other's way, and the other
            // one belongs to the More button.
            .confirmationDialog(
                "Tutor note",
                isPresented: Binding(
                    get: { batchMenu != nil },
                    set: { if !$0 { batchMenu = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let batch = batchMenu {
                    Button(collapsedBatches.contains(batch.id) ? "Expand" : "Collapse to one line") {
                        toggleBatchCollapsed(batch)
                    }

                    Button("Remove", role: .destructive) {
                        removeBatch(batch)
                    }
                }

                Button("Cancel", role: .cancel) {}
            }

            FloatingNavRail(
                showQuestions: $showQuestions,
                tutorApart: $tutorApart,
                showMore: $showMore,
                isChecking: isChecking
            ) {
                checkTask = Task { await runCheck() }
            }
            .padding(.leading, 10)
            .padding(.top, 76)

            if showQuestions {
                QuestionsDrawer(
                    problems: problems,
                    currentIndex: currentIndex,
                    solvedProblems: solvedProblems,
                    onSelect: select,
                    onClose: { showQuestions = false }
                )
                .transition(.move(edge: .leading))
            }
        }
        .animation(.snappy, value: showQuestions)
        .animation(.snappy, value: tutorApart)
        .confirmationDialog("More", isPresented: $showMore, titleVisibility: .hidden) {
            Button("Ask about this") {
                checkTask = Task { await askQuestion() }
            }
            .disabled(isChecking)

            Button("Upload an assignment") {
                photoPurpose = .readAssignment
                photoChoice = .library
            }
            .disabled(isChecking)

            Button("Upload work you did on paper") {
                photoPurpose = .markWork
                photoChoice = .library
            }
            .disabled(isChecking)

            if PhotoChoice.camera.isAvailable {
                Button("Take a photo of your work") {
                    photoPurpose = .markWork
                    photoChoice = .camera
                }
                .disabled(isChecking)
            }

            if problemsFromAssignment {
                Button("Back to the built-in questions") {
                    problemsFromAssignment = false
                    checkTask = Task { await loadProblems() }
                }
                .disabled(isChecking)
            }

            Button(tutorApart ? "Tutor on the page" : "Tutor in its own panel") {
                tutorApart.toggle()
            }

            Button("Undo") {
                canvas.undoManager?.undo()
            }

            Button("Redo") {
                canvas.undoManager?.redo()
            }

            Button("Clear page", role: .destructive) {
                clearPage()
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $photoChoice) { choice in
            PhotoSource(source: choice.source) { image in
                photoChoice = nil

                guard let image else { return }

                switch photoPurpose {
                case .markWork:
                    checkTask = Task { await checkPhotograph(image) }
                case .readAssignment:
                    checkTask = Task { await takeOnAssignment(image) }
                }
            }
            .ignoresSafeArea()
        }
        .task {
            await loadProblems()
        }
        .onChange(of: paper.shade) {
            pen.follow(paper)
        }
        .tint(Theme.pink)
    }

    // MARK: - Header

    var appHeader: some View {
        HStack(spacing: 16) {
            // Drawn rather than set: the blocks are part of the name, and
            // the two have to keep their spacing. Height is fixed and the
            // width follows, so the lockup is never squashed.
            Image("Wordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("StepOut")

            Spacer()

            if !problems.isEmpty {
                Text("\(currentIndex + 1) of \(problems.count)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .brutalBorder(radius: 20, lineWidth: 1.5)
            }

            Button {
                checkTask = Task { await runCheck() }
            } label: {
                Text(isChecking ? "Checking…" : "Check")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.pink, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
            .disabled(isChecking)
            .opacity(isChecking ? 0.6 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.ink.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - The page

    var page: some View {
        HStack(spacing: 0) {
            notebook

            if tutorApart {
                Divider()

                tutorPanel
                    .frame(width: tutorWidth + 48)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: tutorApart)
    }

    var notebook: some View {
        // The paper is an overlay rather than a child so that its height —
        // which runs well past the bottom of the screen — has no say in how
        // big this view is. What is on screen stays one screenful.
        Color(.systemBackground)
            .background(Theme.paper)
            .overlay(alignment: .topLeading) {
                paperLayer
                    .frame(height: pageHeight, alignment: .top)
                    .offset(y: -scrolledBy)
            }
            .overlay {
                NotebookPage(
                    canvas: canvas,
                    tool: pen.tool,
                    pageHeight: pageHeight,
                    onSqueeze: { pen.isErasing.toggle() },
                    onWriting: { noticeWriting() },
                    onScroll: { scrolledBy = $0 }
                )
            }
            // Finger gestures on tutor writing sit above the canvas. Double-tap
            // collapses; long-press opens keep / remove.
            .overlay(alignment: .topLeading) {
                if !tutorApart {
                    tutorBatchGestures
                        .frame(height: pageHeight, alignment: .topLeading)
                        .offset(y: -scrolledBy)
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                pageWidth = size.width
                visibleHeight = size.height
                growPage()
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    if thinking {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)

                            Text("Working it out…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .brutalBorder(radius: 24)
                        .transition(.scale.combined(with: .opacity))
                    }

                    if writingSince != nil {
                        Button("Stop", systemImage: "stop.fill") {
                            stopWriting()
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.pink)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Tapping is the reliable way to answer: a written "yes" is
                    // ink you then have to rub out, and it lands wherever there
                    // happened to be room. Writing one still works for anyone
                    // who would rather not leave the page.
                    if offer != nil, answered == nil {
                        HStack(spacing: 12) {
                            Text("Want a hand?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)

                            Button("Yes") { replyTask = Task { await answer(.yes) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(Theme.pink)

                            Button("No") { replyTask = Task { await answer(.no) } }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .brutalBorder(radius: 24)
                        .transition(.scale.combined(with: .opacity))
                    }

                    PenPalette(pen: pen, paper: paper)
                }
                .padding(20)
                .animation(.snappy, value: writingSince)
                .animation(.snappy, value: answered)
                .animation(.snappy, value: thinking)
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
    }

    /// Where the tutor writes when it is kept off the student's page.
    ///
    /// Lines are laid out one after another here rather than at the ruled line
    /// they were given, because those numbers describe a place on the notebook
    /// page and mean nothing over here.
    var tutorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.footnote)
                    .foregroundStyle(paper.tutorInk)

                Text("Tutor")
                    .font(.subheadline.weight(.semibold))

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tutorLines.isEmpty {
                        Text("Nothing yet. Check your math, or ask a question.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(24)
                    } else {
                        ForEach(tutorBatches) { batch in
                            tutorPanelBatch(batch)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.paper)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.ink)
                .frame(width: Theme.outline)
        }
    }

    /// Everything printed or written on the paper, behind the canvas.
    ///
    /// This is one tall layer that slides up as the canvas scrolls, so a ruled
    /// line and the ink resting on it never come apart.
    var paperLayer: some View {
        ZStack(alignment: .topLeading) {
            RuledPaper(paper: paper)

            inkMarks

            marginMarks

            // The question, written onto the page a stroke at a time: what to
            // do, then the equation underneath once that line is finished.
            if let problem {
                HandwrittenLine(
                    text: problem.prompt,
                    origin: NotebookLayout.penStart(onLine: 0),
                    color: paper.questionInk
                )

                HandwrittenLine(
                    text: problem.equation,
                    origin: NotebookLayout.penStart(onLine: 1),
                    color: paper.questionInk,
                    delay: HandwrittenLine.writingTime(for: problem.prompt) + 0.25
                )
            }

            if !tutorApart {
                lessonOnThePage
            }
        }
    }

    /// The tutor's writing, grouped by sitting so each can be folded away.
    var tutorBatches: [TutorBatch] {
        var order: [UUID] = []
        var grouped: [UUID: [TutorLine]] = [:]

        for line in tutorLines {
            if grouped[line.batch] == nil {
                order.append(line.batch)
            }
            grouped[line.batch, default: []].append(line)
        }

        return order.compactMap { batch in
            guard let lines = grouped[batch], let kind = lines.first?.kind else { return nil }
            return TutorBatch(id: batch, kind: kind, lines: lines)
        }
    }

    /// The tutor's lesson, written out below the student's own work.
    ///
    /// Each line waits for the ones above it to finish, so the page fills the
    /// way a person would fill it rather than all at once.
    var lessonOnThePage: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tutorBatches) { batch in
                if collapsedBatches.contains(batch.id) {
                    collapsedBatch(batch)
                } else {
                    ForEach(batch.lines) { line in
                        HandwrittenLine(
                            text: line.text,
                            origin: NotebookLayout.penStart(onLine: line.line, x: line.originX),
                            height: tutorHeight,
                            color: paper.tutorInk,
                            delay: line.delay,
                            alreadyWritten: line.written
                        )
                    }
                }

            }
        }
    }

    /// Invisible hit areas over tutor ink on the page — finger only, no buttons.
    var tutorBatchGestures: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tutorBatches) { batch in
                tutorBatchHitArea(batch)
            }
        }
    }

    func tutorBatchHitArea(_ batch: TutorBatch) -> some View {
        let bounds = batchBounds(batch)

        return FingerTapArea(
            onDoubleTap: { toggleBatchCollapsed(batch) },
            onLongPress: { batchMenu = batch }
        )
        .frame(width: bounds.width, height: bounds.height)
        .offset(x: bounds.minX, y: bounds.minY)
    }

    func tutorPanelBatch(_ batch: TutorBatch) -> some View {
        Group {
            if collapsedBatches.contains(batch.id) {
                Text(batch.lines.map(\.text).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(paper.tutorInkFaded)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(batch.lines) { line in
                        HandwrittenLine(
                            text: line.text,
                            origin: CGPoint(x: 0, y: 0),
                            height: tutorHeight,
                            color: paper.tutorInk,
                            delay: line.delay,
                            alreadyWritten: line.written
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            toggleBatchCollapsed(batch)
        }
        .contextMenu {
            tutorBatchMenu(batch)
        }
    }

    @ViewBuilder
    func tutorBatchMenu(_ batch: TutorBatch) -> some View {
        let folded = collapsedBatches.contains(batch.id)

        Button(folded ? "Expand" : "Collapse to one line") {
            toggleBatchCollapsed(batch)
        }

        Divider()

        Button("Remove", role: .destructive) {
            removeBatch(batch)
        }
    }

    /// One line of summary when a batch is folded away.
    func collapsedBatch(_ batch: TutorBatch) -> some View {
        let summary = batch.lines.map(\.text).joined(separator: " ")

        return Text(summary)
            .font(.caption)
            .foregroundStyle(paper.tutorInkFaded)
            .lineLimit(1)
            .frame(maxWidth: pageWidth - (batch.lines.first?.originX ?? NotebookLayout.marginWidth) - 24, alignment: .leading)
            .padding(.leading, batch.lines.first?.originX ?? NotebookLayout.marginWidth + 16)
            .padding(.top, NotebookLayout.penStart(onLine: batch.firstLine).y - tutorHeight)
    }

    /// The patch of paper a batch is tappable on — what you can see of it, so a
    /// folded batch stops claiming the lines it is no longer using.
    func batchBounds(_ batch: TutorBatch) -> CGRect {
        let folded = collapsedBatches.contains(batch.id)
        let originX = batch.lines.first?.originX ?? NotebookLayout.marginWidth + 16
        let firstLine = batch.firstLine
        let lastLine = folded ? firstLine : (batch.lines.map(\.line).max() ?? firstLine)

        let rightEdge = folded
            ? originX + 220
            : (batch.lines.map { $0.originX + StrokeFont.width(of: $0.text, height: tutorHeight) }.max() ?? originX + 120)

        let top = NotebookLayout.penStart(onLine: firstLine).y - tutorHeight - 6
        let bottom = NotebookLayout.penStart(onLine: lastLine).y + 10

        return CGRect(
            x: originX - 10,
            y: top,
            width: max(72, rightEdge - originX + 20),
            height: max(NotebookLayout.lineHeight * 0.6, bottom - top)
        )
    }

    func toggleBatchCollapsed(_ batch: TutorBatch) {
        if collapsedBatches.contains(batch.id) {
            collapsedBatches.remove(batch.id)
        } else {
            markWritten(batch.id)
            collapsedBatches.insert(batch.id)
        }
    }

    func removeBatch(_ batch: TutorBatch) {
        collapsedBatches.remove(batch.id)
        tutorLines.removeAll { $0.batch == batch.id }
        growPage()
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

    /// The verdict drawn onto the writing itself.
    ///
    /// Sits behind the canvas with the rest of the paper, so it reads as
    /// something on the page rather than something floating over it, and it
    /// never takes a touch meant for the pen.
    var inkMarks: some View {
        ZStack(alignment: .topLeading) {
            if let solvedInk {
                highlight(solvedInk, color: .green)
            }

            if let errorInk {
                highlight(errorInk, color: .red)
            }
        }
    }

    /// A soft band behind one line of writing, the width of the writing.
    func highlight(_ ink: CGRect, color: Color) -> some View {
        let padded = ink.insetBy(dx: -10, dy: -6)

        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.opacity(paper.isDark ? 0.28 : 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1.5)
            )
            .frame(width: padded.width, height: padded.height)
            .offset(x: padded.minX, y: padded.minY)
            .transition(.opacity)
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
            problemsFromAssignment = false
            currentIndex = 0
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
        hideFeedback()
        emptyPage()
    }

    /// Wipe the page without calling off the check or clearing the note.
    ///
    /// Kept apart from `clearPage` for the one caller that is itself running
    /// inside the check: cancelling the task you are in the middle of is a
    /// strange way to finish a job, and the note it is about to show would be
    /// hidden before anybody read it.
    func emptyPage() {
        canvas.erasePage()
        errorLine = nil
        solvedLine = nil
        errorInk = nil
        solvedInk = nil
        stopListening()
        writingTask?.cancel()
        writingSince = nil
        tutorLines = []
        lastWrongLine = nil
        collapsedBatches = []

        canvas.setContentOffset(.zero, animated: false)
        growPage()
    }

    // MARK: - Asking for help

    /// Write something on the page in the tutor's hand.
    ///
    /// Sentences are broken to fit the page first. A path does not wrap on its
    /// own; left alone it would run straight off the edge of the paper.
    func tutorWrites(
        _ sentences: [String],
        kind: TutorLine.Kind = .remark,
        nearLine: Int? = nil,
        beside bounds: CGRect? = nil
    ) {
        var line: Int
        var originX: CGFloat
        var columnWidth: CGFloat
        var delay = 0.0

        if kind == .lesson, let last = tutorLines.last(where: { $0.kind == .lesson }) {
            // Carry on where the last part of the lesson left off.
            line = last.line + 1
            originX = last.originX
            columnWidth = max(120, pageWidth - originX - 24)
        } else {
            // How much width this writing actually wants. A short remark is
            // happy in a gap beside the work; anything that has to wrap needs a
            // real column, or it comes out two words at a time down the margin.
            let longest = sentences
                .map { StrokeFont.width(of: $0, height: tutorHeight) }
                .max() ?? 0
            let wanted = min(max(longest, 120), leastTutorColumn)

            // A lesson is a paragraph rather than a note in the margin, so it
            // starts below the work instead of trying to squeeze in beside it.
            let from = kind == .lesson
                ? lowestUsedLine() + 1
                : anchorLine(nearLine: nearLine, beside: bounds)

            let spot = freeSpot(width: wanted, from: from)
            line = spot.line
            originX = spot.originX

            // Wrap to the clear run of paper, not to the edge of the page, so
            // the writing stops before whatever is sitting further along.
            columnWidth = max(120, min(spot.width, pageWidth - originX - 24))
        }

        let batch = UUID()

        for sentence in sentences {
            for text in StrokeFont.wrap(sentence, height: tutorHeight, into: columnWidth) {
                tutorLines.append(
                    TutorLine(
                        batch: batch,
                        kind: kind,
                        text: text,
                        line: line,
                        originX: originX,
                        delay: delay
                    )
                )

                delay += HandwrittenLine.writingTime(for: text) + 0.05
                line += 1
            }
        }

        growPage()
        scrollIntoView(line: line - 1)

        startWriting(batch, lasting: delay)
    }

    /// Note that the tutor has started writing, and when it will be done.
    func startWriting(_ batch: UUID, lasting: Double) {
        writingBatch = batch
        writingSince = Date()

        writingTask?.cancel()
        writingTask = Task {
            try? await Task.sleep(for: .seconds(lasting))

            if !Task.isCancelled {
                writingSince = nil
                markWritten(batch)
            }
        }
    }

    /// Note that a batch is finished, so it is never written out twice.
    func markWritten(_ batch: UUID) {
        for spot in tutorLines.indices where tutorLines[spot].batch == batch {
            tutorLines[spot].written = true
        }
    }

    /// Cut the tutor off mid-sentence.
    ///
    /// Keeps whatever has already been written and drops the rest. A line that
    /// is halfway across the page stays halfway across it — vanishing under
    /// the pen would look like a fault rather than an answer.
    func stopWriting() {
        guard let since = writingSince, let batch = writingBatch else { return }

        let written = Date().timeIntervalSince(since)
        tutorLines.removeAll { $0.batch == batch && $0.delay > written }

        writingTask?.cancel()
        writingSince = nil
        markWritten(batch)

        // A lesson still on its way would otherwise arrive and start writing
        // itself moments after being told to stop.
        replyTask?.cancel()
    }

    /// Which ruled line a remark is about, so it can be written beside it.
    func anchorLine(nearLine: Int? = nil, beside bounds: CGRect? = nil) -> Int {
        if let nearLine { return nearLine }

        if let bounds {
            return max(0, Int(bounds.midY / NotebookLayout.lineHeight))
        }

        return canvas.workingLines(pageWidth: pageWidth).last?.lineNumber ?? errorLine ?? 2
    }

    /// What is already written across one ruled line, left to right.
    ///
    /// A folded batch still counts for the room it takes when it is opened
    /// again. Otherwise the space it frees gets written into, and unfolding it
    /// drops a paragraph straight on top of whatever moved in.
    func occupiedSpans(onLine lineNumber: Int) -> [(minX: CGFloat, maxX: CGFloat)] {
        var spans: [(minX: CGFloat, maxX: CGFloat)] = []

        let lineY = NotebookLayout.penStart(onLine: lineNumber).y
        let band = NotebookLayout.lineHeight * 0.65

        for written in canvas.writtenLines() where abs(written.bounds.midY - lineY) < band {
            spans.append((minX: written.bounds.minX, maxX: written.bounds.maxX))
        }

        for written in tutorLines where written.line == lineNumber {
            spans.append((
                minX: written.originX,
                maxX: written.originX + StrokeFont.width(of: written.text, height: tutorHeight)
            ))
        }

        // The printed question sits on the first two lines and is not ink.
        if problem != nil, lineNumber <= 1 {
            spans.append((minX: 0, maxX: pageWidth))
        }

        return spans.sorted { $0.minX < $1.minX }
    }

    /// The first clear stretch of paper wide enough to write in.
    ///
    /// Walks down the page from a starting line, and across each line past
    /// anything already written, so the tutor lands in space that is actually
    /// free rather than wherever the arithmetic happened to point.
    func freeSpot(width: CGFloat, from line: Int) -> (line: Int, originX: CGFloat, width: CGFloat) {
        let leftEdge = NotebookLayout.penStart(onLine: 0).x
        let rightEdge = pageWidth - 24
        let start = max(0, line)

        for candidate in start...(start + 40) {
            var cursor = leftEdge

            for span in occupiedSpans(onLine: candidate) {
                let gap = span.minX - NotebookLayout.columnGap - cursor

                if gap >= width {
                    return (line: candidate, originX: cursor, width: gap)
                }

                cursor = max(cursor, span.maxX + NotebookLayout.columnGap)
            }

            if rightEdge - cursor >= width {
                return (line: candidate, originX: cursor, width: rightEdge - cursor)
            }
        }

        let below = lowestUsedLine() + 1
        return (below, leftEdge, rightEdge - leftEdge)
    }

    /// The lowest ruled line anything occupies, for growing the page.
    func lowestUsedLine() -> Int {
        var lowest = 0

        let ink = canvas.drawing.bounds
        if !ink.isNull {
            lowest = Int(ink.maxY / NotebookLayout.lineHeight)
        }

        for written in tutorLines {
            lowest = max(lowest, written.line)
        }

        return lowest
    }

    /// Keep blank paper below the last thing written.
    ///
    /// Deliberately not called while the student is drawing. Resizing the page
    /// changes the canvas's content size, and PencilKit is in the middle of
    /// working out how to tile the drawing at exactly that moment. It is called
    /// at the quiet points instead — a check, a lesson, a new problem — and
    /// leaves a screenful of room below the writing so there is always
    /// somewhere to carry on.
    func growPage() {
        var lowest = lowestUsedLine()

        for batch in tutorBatches {
            if collapsedBatches.contains(batch.id) {
                lowest = max(lowest, batch.firstLine)
            } else if let last = batch.lines.last?.line {
                lowest = max(lowest, last)
            }
        }

        let wanted = CGFloat(lowest) * NotebookLayout.lineHeight + visibleHeight
        let leastPage = CGFloat(NotebookLayout.leastLines) * NotebookLayout.lineHeight

        pageHeight = max(max(visibleHeight, leastPage), wanted)
    }

    /// Start waiting for an answer to a question on the page.
    func markOffer(_ newOffer: Offer) {
        offer = newOffer
        strokesWhenOffered = canvas.drawing.strokes.count
        offerLine = tutorLines.last?.line
        answered = nil
        answerSeen = nil
    }

    /// Scroll down far enough to see a given line, if it is below the fold.
    ///
    /// Only ever scrolls down. Being dragged back up while reading something
    /// further up the page would be worse than not following at all.
    func scrollIntoView(line: Int) {
        let bottom = CGFloat(line + 2) * NotebookLayout.lineHeight
        let target = max(0, bottom - visibleHeight)

        guard target > scrolledBy + 1 else { return }

        // The paper was made taller a moment ago, but the canvas is not told
        // until SwiftUI next updates it. Going now would scroll against the
        // old, shorter page and be clamped short of the writing.
        Task { @MainActor in
            canvas.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        }
    }


    /// Drop the open question. Leaves `answered` alone — the caller may have
    /// just set it.
    func clearOffer() {
        offer = nil
        offerLine = nil
        strokesWhenOffered = 0
        answerSeen = nil
    }

    func stopListening() {
        replyTask?.cancel()
        replyTask = nil
        clearOffer()
        answered = nil
    }

    /// The ink written in reply to the tutor's question.
    ///
    /// Anything added after the question appeared counts. "Yes" is often written
    /// beside the student's work on the mistake line, not underneath the
    /// tutor's "want a hand?" — so both those lines count as reply territory.
    func replyInk() -> [PKStroke] {
        guard offer != nil else { return [] }

        let sinceOffer = Array(canvas.drawing.strokes.dropFirst(strokesWhenOffered))
        guard !sinceOffer.isEmpty else { return [] }

        if tutorApart {
            return Array(sinceOffer.suffix(8))
        }

        let band = NotebookLayout.lineHeight * 0.7
        var replyLines = Set<Int>()
        if let offerLine { replyLines.insert(offerLine) }
        if let errorLine { replyLines.insert(errorLine) }

        let filtered = sinceOffer.filter { stroke in
            let bounds = stroke.renderBounds
            let y = bounds.midY

            // On or just below the question, or on the line that was wrong.
            if replyLines.contains(where: { abs(y - NotebookLayout.penStart(onLine: $0).y) < band }) {
                return true
            }

            // Written to the right of the student's work — a short reply beside
            // the algebra, not a new step underneath it.
            if let errorLine {
                let workEdge = canvas.rightEdgeOfInk(onLine: errorLine, pageWidth: pageWidth)
                let lineY = NotebookLayout.penStart(onLine: errorLine).y
                if abs(y - lineY) < band, bounds.minX >= workEdge - 12 {
                    return true
                }
            }

            if let offerLine, y >= NotebookLayout.penStart(onLine: offerLine).y - 8 {
                return true
            }

            return false
        }

        return Array((filtered.isEmpty ? sinceOffer : filtered).suffix(8))
    }

    /// The student has written something. If we asked them a question, this
    /// might be the answer — or a change of mind about the last one.
    func noticeWriting() {
        guard offer != nil else { return }

        replyTask?.cancel()

        replyTask = Task {
            try? await Task.sleep(for: .seconds(0.8))

            if !Task.isCancelled {
                await readReply()
            }
        }
    }

    /// Read the answer written under the question, and act on it if it changed.
    func readReply() async {
        guard offer != nil else { return }

        let ink = replyInk()

        // Rubbed out. The question is still on the page, so it still stands,
        // and the next thing written under it gets read afresh.
        guard !ink.isEmpty else {
            answered = nil
            answerSeen = nil
            return
        }

        // Bounds rather than a stroke count, because rubbing out a two-stroke
        // "yes" and writing a two-stroke "no" leaves the count where it was.
        let shape = ink.dropFirst().reduce(ink[0].renderBounds) { $0.union($1.renderBounds) }

        guard shape != answerSeen else { return }
        answerSeen = shape

        do {
            let words = try await readWords([RowData(strokes: coordinates(of: ink))])

            // Anything that isn't a reply is left alone: they have most likely
            // gone back to working on the problem, and interrupting that to
            // teach at them would be worse than missing a quiet "sure".
            guard let reply = Reply.read(words), reply != answered else { return }

            await answer(reply)
        } catch {
            // A reply we could not read is not worth telling anyone about.
            // They can ask again by writing again.
        }
    }

    /// Act on a yes or a no, however it arrived — written or tapped.
    func answer(_ reply: Reply) async {
        guard let currentOffer = offer else { return }

        answered = reply
        clearOffer()

        switch (reply, currentOffer) {
        case (.yes, .help(let help)):
            tutorWrites(
                ["sure — one moment."],
                nearLine: errorLine ?? tutorLines.last?.line,
                beside: errorInk
            )
            await write { try await fetchLesson(for: help) }

        case (.yes, .example(let question)):
            tutorWrites(["sure — one moment."], kind: .lesson, nearLine: tutorLines.last?.line)
            await write { try await fetchWorkedExample(for: question) }

        case (.no, _):
            tutorWrites(
                ["no problem. give it another go."],
                nearLine: errorLine ?? tutorLines.last?.line,
                beside: errorInk
            )
        }
    }

    /// Fetch a lesson and start it writing itself onto the page.
    ///
    /// Takes how to get the lesson rather than the lesson itself, because a
    /// mistake and a question are asked about at different addresses but write
    /// out exactly the same once they arrive.
    func write(_ fetch: () async throws -> Lesson) async {
        thinking = true
        defer { thinking = false }

        do {
            tutorWrites(try await fetch().lines, kind: .lesson)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            // Says what actually happened. A lesson is only ever thrown away
            // because it failed the same checker that marks the student's
            // work, and "I can't explain that" sounds like the tutor does not
            // understand the topic rather than that it declined to write
            // something it could not stand behind.
            tutorWrites(["i couldn't put together an example i'd trust for that one."])
        }
    }

    /// Read the last line written as a question, and answer it on the page.
    ///
    /// The last line, rather than anything cleverer, because that rule can be
    /// held in your head: write the question at the bottom, tap Ask. Working
    /// out which of the marks on a page are English and which are algebra is a
    /// guess, and a wrong guess answers a question nobody asked.
    func askQuestion() async {
        guard let written = canvas.workingLines(pageWidth: pageWidth).last else {
            tutorWrites(["write your question at the bottom, then tap ask."])
            return
        }

        stopListening()
        // Keep earlier tutor notes on the page — only append new answers.

        thinking = true
        defer { thinking = false }

        do {
            let words = try await readWords([RowData(strokes: written.strokes)])
            let asked = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)

            guard !asked.isEmpty else {
                tutorWrites(["i couldn't read that. write it again?"])
                return
            }

            let question = Question(
                question: asked,
                problem: problem?.equation,
                work: lastRead.isEmpty ? nil : lastRead
            )

            let reply = try await fetchAnswer(to: question)

            tutorWrites(
                [reply, "want me to work one through?"],
                nearLine: written.lineNumber,
                beside: written.bounds
            )

            markOffer(.example(question))
        } catch {
            tutorWrites(["sorry, i couldn't answer that one."])
        }
    }

    /// Turn raw strokes into the coordinates the server reads.
    ///
    /// The reply is one short word, so unlike the student's working there is no
    /// need to work out which lines it sits on.
    func coordinates(of strokes: [PKStroke]) -> [StrokeData] {
        strokes.compactMap { stroke in
            var xs: [Double] = []
            var ys: [Double] = []

            for point in stroke.path.interpolatedPoints(by: .distance(2)) {
                let location = point.location.applying(stroke.transform)
                xs.append(location.x)
                ys.append(location.y)
            }

            return xs.count >= 2 ? StrokeData(x: xs, y: ys) : nil
        }
    }

    /// Show a note over the page, and take it away again once it has been read.
    func show(_ newFeedback: Feedback) {
        feedbackTask?.cancel()

        withAnimation(.snappy) {
            feedback = newFeedback
        }

        // The cross in the margin is the lasting record of a mistake, so these
        // words don't have to sit there forever explaining themselves — but a
        // note has to outlast reading it, and an explanation of a wrong step
        // is a good deal longer than "solved".
        let readingTime = 3.5 + Double(newFeedback.text.count) * 0.06

        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(readingTime))

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

        growPage()

        // An open question is answered first — yes or no, written or tapped.
        if offer != nil {
            await readReply()
            if answered != nil { return }
        }

        errorLine = nil
        solvedLine = nil
        errorInk = nil
        solvedInk = nil
        hideFeedback()

        let lines = canvas.workingLines(pageWidth: pageWidth)
        let rows = lines.map { RowData(strokes: $0.strokes) }

        do {
            // The wording travels as well as the index, because a problem read
            // off a worksheet has no place in the server's list to be found in.
            let result = try await checkHandwriting(
                rows,
                problemIndex: problem?.index,
                problemEquation: problem?.equation
            )

            if Task.isCancelled { return }

            let skipped = result.ignored ?? []
            lastRead = result.recognized ?? []

            if !skipped.isEmpty {
                show(Feedback(text: "Skipped some writing.", tone: .plain, skipped: skipped))
            }

            // Tutor notes stay on the page across rechecks. New feedback is
            // appended beside the work it refers to.

            // Anything starred on the page was a question, and the server has
            // already answered it. Said first, because it is the thing they
            // stopped to ask, and the verdict on the algebra can wait a line.
            for asked in result.questions ?? [] {
                tutorWrites(
                    [asked.answer.lowercased()],
                    kind: .lesson,
                    nearLine: lines.last?.lineNumber,
                    beside: lines.last?.bounds
                )
            }

            if result.ok {
                stopListening()

                let readAnyAlgebra = !(result.recognized ?? []).isEmpty
                let near = lines.last?.lineNumber
                let ink = lines.last?.bounds

                if !readAnyAlgebra {
                    if let nudge = result.message {
                        tutorWrites([nudge.lowercased()], nearLine: near, beside: ink)
                    }
                } else if result.solved == true {
                    solvedLine = lines.last?.lineNumber
                    solvedInk = ink
                    solvedProblems.insert(currentIndex)
                    tutorWrites(["solved. \(result.answer ?? "")".lowercased()], nearLine: near, beside: ink)
                } else {
                    tutorWrites([(result.message ?? "correct so far. keep going.").lowercased()], nearLine: near, beside: ink)
                }
            } else {
                if let step = result.errorStep, step - 1 < lines.count {
                    errorLine = lines[step - 1].lineNumber
                    errorInk = lines[step - 1].bounds
                }

                let near = errorLine ?? lines.last?.lineNumber
                var says = [(result.message ?? "something doesn't follow.").lowercased()]

                if result.help?.wrongLine != nil, result.help?.wrongLine == lastWrongLine {
                    says.append("it's the line with the cross beside it, further up.")
                }

                lastWrongLine = result.help?.wrongLine

                if result.help != nil {
                    says.append("want a hand?")
                }

                tutorWrites(says, nearLine: near, beside: errorInk)

                if let help = result.help {
                    markOffer(.help(help))
                } else {
                    stopListening()
                }
            }
        } catch {
            // Clearing the page cancels the check, which is not a failure the
            // student needs telling about.
            if !Task.isCancelled {
                show(Feedback(text: "Could not reach the server.", tone: .bad))
            }
        }
    }

    /// Take on the questions from a photographed worksheet.
    ///
    /// The sheet replaces the built-in questions rather than joining them. An
    /// uploaded assignment is what the student sat down to do, and burying it
    /// at the end of a list of practice problems would make finding it a chore
    /// every time. The More menu offers the way back.
    func takeOnAssignment(_ image: UIImage) async {
        isChecking = true
        defer { isChecking = false }

        guard let jpeg = image.jpegForReading() else {
            show(Feedback(text: "Could not read that picture.", tone: .bad))
            return
        }

        do {
            let found = try await fetchProblemsFromPhoto(jpeg)

            if Task.isCancelled { return }

            guard !found.isEmpty else {
                show(
                    Feedback(
                        text: "I couldn't find any questions in that picture. Try again with the sheet flat and the whole page in shot.",
                        tone: .bad
                    )
                )
                return
            }

            problems = found
            problemsFromAssignment = true
            currentIndex = 0
            solvedProblems = []
            emptyPage()

            show(
                Feedback(
                    text: found.count == 1
                        ? "Got 1 question from your assignment."
                        : "Got \(found.count) questions from your assignment.",
                    tone: .good,
                    skipped: found.map(\.equation)
                )
            )
        } catch {
            if !Task.isCancelled {
                show(Feedback(text: "Could not reach the server.", tone: .bad))
            }
        }
    }

    /// Mark a photograph of work done on real paper.
    ///
    /// Written as a lesson rather than a remark, because there is nothing on
    /// this page for it to be a remark about. A cross in the margin would point
    /// at a ruled line the photographed working was never on, so the verdict
    /// names the line instead and stays put like anything else taught.
    func checkPhotograph(_ image: UIImage) async {
        isChecking = true
        defer { isChecking = false }

        guard let jpeg = image.jpegForReading() else {
            show(Feedback(text: "Could not read that photo.", tone: .bad))
            return
        }

        stopListening()
        growPage()

        do {
            let result = try await checkPhoto(jpeg, problemIndex: problem?.index)

            if Task.isCancelled { return }

            let read = result.recognized ?? []

            guard !read.isEmpty else {
                tutorWrites(
                    [(result.message ?? "i couldn't read any maths in that photo.").lowercased()],
                    kind: .lesson
                )
                return
            }

            // What it read, shown as plainly as possible. A photograph is read
            // by a model rather than traced from strokes, so a misreading is
            // likelier here than anywhere else in the app — and a verdict on
            // lines the student never wrote is only explainable if they can see
            // the lines it judged.
            show(Feedback(text: "Read from your photo:", tone: .plain, skipped: read))

            if result.ok {
                if result.solved == true {
                    solvedProblems.insert(currentIndex)
                    tutorWrites(
                        ["from your photo: solved. \(result.answer ?? "")".lowercased()],
                        kind: .lesson
                    )
                } else {
                    tutorWrites(
                        [(result.message ?? "that follows so far. keep going.").lowercased()],
                        kind: .lesson
                    )
                }
            } else {
                var says: [String] = []

                // Named rather than marked. The stroke font draws only what it
                // has a glyph for, so this stays to plain characters.
                if let step = result.errorStep, step >= 1, step - 1 < read.count {
                    says.append("in your photo, line \(step): \(read[step - 1])".lowercased())
                }

                says.append((result.message ?? "something doesn't follow.").lowercased())

                if result.help != nil {
                    says.append("want a hand?")
                }

                tutorWrites(says, kind: .lesson)

                if let help = result.help {
                    markOffer(.help(help))
                }
            }
        } catch {
            if !Task.isCancelled {
                show(Feedback(text: "Could not reach the server.", tone: .bad))
            }
        }
    }
}

#Preview {
    ContentView()
}
