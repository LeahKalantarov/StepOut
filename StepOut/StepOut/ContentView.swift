import PencilKit
import SwiftUI

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

    // MARK: Asking for help

    // What the tutor has offered. Non-nil means the question is on the page
    // and the answer written under it counts for something.
    @State private var offer: Offer?

    // How the last check read the student's writing, so a question about it
    // can be asked with the working attached.
    @State private var lastRead: [String] = []

    // The line the question was written on. The answer is whatever is written
    // below it, so the two have to stay tied together.
    @State private var offerLine: Int?

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

    /// Height of the tutor's handwriting, a little smaller than the question.
    private let tutorHeight: CGFloat = 22

    /// Lines sit closer together in the panel than on ruled paper, which has to
    /// leave room for a student's writing between the rules.
    private let panelLineHeight: CGFloat = 38

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { pageTools }
    }

    var notebook: some View {
        // The paper is an overlay rather than a child so that its height —
        // which runs well past the bottom of the screen — has no say in how
        // big this view is. What is on screen stays one screenful.
        Color(.systemBackground)
            .overlay(alignment: .topLeading) {
                paper
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
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                visibleHeight = height
                growPage()
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 12) {
                    if writingSince != nil {
                        Button("Stop", systemImage: "stop.fill") {
                            stopWriting()
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Written answers still work, but there is no "underneath
                    // the question" once the tutor has its own panel, so the
                    // same two answers are always here to be tapped.
                    if offer != nil, answered == nil {
                        HStack(spacing: 8) {
                            Button("Yes") { replyTask = Task { await answer(.yes) } }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)

                            Button("No") { replyTask = Task { await answer(.no) } }
                                .buttonStyle(.bordered)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    PenPalette(
                        pen: pen,
                        undo: { canvas.undoManager?.undo() },
                        redo: { canvas.undoManager?.redo() }
                    )
                }
                .padding(20)
                .animation(.snappy, value: writingSince)
                .animation(.snappy, value: answered)
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

    @ToolbarContentBuilder
    var pageTools: some ToolbarContent {
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
            Button(
                tutorApart ? "Tutor on the page" : "Tutor in its own panel",
                systemImage: tutorApart ? "rectangle" : "rectangle.righthalf.inset.filled"
            ) {
                tutorApart.toggle()
            }
            .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Ask about this", systemImage: "questionmark.bubble") {
                checkTask = Task { await askQuestion() }
            }
            .labelStyle(.iconOnly)
            .disabled(isChecking)
        }

        ToolbarItem(placement: .topBarTrailing) {
            // A bin, not a circular arrow: the palette's undo arrow is right
            // there on the same page and means something else.
            Button("Clear page", systemImage: "trash") {
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
                // Spelled out on purpose. A toolbar shows icons alone by
                // default, and the one button the student has to find should
                // not be an unlabelled dot.
                Label(isChecking ? "Checking" : "Check my work", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)
        }
    }

    /// Where the tutor writes when it is kept off the student's page.
    ///
    /// Lines are laid out one after another here rather than at the ruled line
    /// they were given, because those numbers describe a place on the notebook
    /// page and mean nothing over here.
    var tutorPanel: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                ForEach(Array(tutorLines.enumerated()), id: \.element.id) { place, written in
                    HandwrittenLine(
                        text: written.text,
                        origin: CGPoint(
                            x: 24,
                            y: CGFloat(place + 1) * panelLineHeight
                        ),
                        height: tutorHeight,
                        color: .indigo.opacity(0.8),
                        delay: written.delay
                    )
                }

                if tutorLines.isEmpty {
                    Text("The tutor writes here.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(24)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: CGFloat(tutorLines.count + 2) * panelLineHeight,
                alignment: .topLeading
            )
        }
        .background(Color(.secondarySystemBackground))
    }

    /// Everything printed or written on the paper, behind the canvas.
    ///
    /// This is one tall layer that slides up as the canvas scrolls, so a ruled
    /// line and the ink resting on it never come apart.
    var paper: some View {
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

            if !tutorApart {
                lessonOnThePage
            }
        }
    }

    /// The tutor's lesson, written out below the student's own work.
    ///
    /// Each line waits for the ones above it to finish, so the page fills the
    /// way a person would fill it rather than all at once.
    var lessonOnThePage: some View {
        ForEach(tutorLines) { written in
            HandwrittenLine(
                text: written.text,
                origin: NotebookLayout.penStart(onLine: written.line),
                height: tutorHeight,
                color: .indigo.opacity(0.75),
                delay: written.delay
            )
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

        canvas.erasePage()
        errorLine = nil
        solvedLine = nil
        stopListening()
        writingTask?.cancel()
        writingSince = nil
        tutorLines = []
        hideFeedback()

        canvas.setContentOffset(.zero, animated: false)
        growPage()
    }

    // MARK: - Asking for help

    /// Write something on the page in the tutor's hand.
    ///
    /// Sentences are broken to fit the page first. A path does not wrap on its
    /// own; left alone it would run straight off the edge of the paper.
    func tutorWrites(_ sentences: [String], kind: TutorLine.Kind = .remark) {
        var line = nextFreeLine()
        var delay = 0.0

        let batch = UUID()

        for sentence in sentences {
            for text in StrokeFont.wrap(sentence, height: tutorHeight, into: tutorWidth) {
                tutorLines.append(
                    TutorLine(batch: batch, kind: kind, text: text, line: line, delay: delay)
                )

                delay += HandwrittenLine.writingTime(for: text) + 0.15
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
            }
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

        // A lesson still on its way would otherwise arrive and start writing
        // itself moments after being told to stop.
        replyTask?.cancel()
    }

    /// The first ruled line below everything already on the page.
    ///
    /// Counts the tutor's own writing as well as the student's, so a lesson
    /// never lands on top of the words that introduced it.
    func nextFreeLine() -> Int {
        var lowest = max(1, lastInkedLine())

        for written in tutorLines {
            lowest = max(lowest, written.line)
        }

        return lowest + 2
    }

    /// The lowest ruled line the student has written anything on.
    ///
    /// Read from the drawing's bounds rather than by grouping the strokes into
    /// lines, because this is checked on every stroke and grouping walks every
    /// point of every stroke.
    func lastInkedLine() -> Int {
        let ink = canvas.drawing.bounds
        guard !ink.isNull else { return 0 }

        return Int(ink.maxY / NotebookLayout.lineHeight)
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
        var lowest = lastInkedLine()

        for written in tutorLines {
            lowest = max(lowest, written.line)
        }

        let wanted = CGFloat(lowest) * NotebookLayout.lineHeight + visibleHeight
        let leastPage = CGFloat(NotebookLayout.leastLines) * NotebookLayout.lineHeight

        pageHeight = max(max(visibleHeight, leastPage), wanted)
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


    func stopListening() {
        replyTask?.cancel()
        offer = nil
        offerLine = nil
        answered = nil
        answerSeen = nil
    }

    /// The ink written in answer to the question.
    ///
    /// Found by where it sits rather than by when it arrived: everything below
    /// the line the question is on, down to whatever the tutor wrote next.
    ///
    /// Reading it back off the page like this is what lets the answer be
    /// changed. Counting the strokes that came after the question would work
    /// once and once only — rub the answer out and the count simply goes down,
    /// with nothing to say the question is open again.
    func replyInk() -> [PKStroke] {
        guard let offerLine else { return [] }

        let below = tutorLines.filter { $0.line > offerLine }.map(\.line).min()

        let top = CGFloat(offerLine + 1) * NotebookLayout.lineHeight
        let bottom = below.map { CGFloat($0) * NotebookLayout.lineHeight }

        return canvas.drawing.strokes.filter { stroke in
            let height = stroke.renderBounds.midY
            return height >= top && height < (bottom ?? .greatestFiniteMagnitude)
        }
    }

    /// The student has written something. If we asked them a question, this
    /// might be the answer — or a change of mind about the last one.
    func noticeWriting() {
        // With the tutor in its own panel there is no "underneath the
        // question" on this page, and reading the ink there anyway would take
        // the student's next step for an answer. The buttons handle it.
        guard offer != nil, !tutorApart else { return }

        // Wait for them to stop. Every stroke lands here, so reading after the
        // first one would try to make a word out of a single letter.
        replyTask?.cancel()

        replyTask = Task {
            try? await Task.sleep(for: .seconds(1.2))

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
            let said = words.joined().lowercased().filter(\.isLetter)

            let reply: Reply? =
                said.hasPrefix("yes") || said == "y" ? .yes :
                said.hasPrefix("no") || said == "n" ? .no : nil

            // Anything else is left alone: they have most likely gone back to
            // working on the problem, and interrupting that to teach at them
            // would be worse than missing a quiet "sure".
            guard let reply, reply != answered else { return }

            await answer(reply)
        } catch {
            // A reply we could not read is not worth telling anyone about.
            // They can ask again by writing again.
        }
    }

    /// Act on a yes or a no, however it arrived — written or tapped.
    func answer(_ reply: Reply) async {
        guard let offer else { return }

        answered = reply

        switch (reply, offer) {
        case (.yes, .help(let help)):
            await write { try await fetchLesson(for: help) }

        case (.yes, .example(let question)):
            await write { try await fetchWorkedExample(for: question) }

        case (.no, _):
            // If this is a change of mind, what they no longer want goes too.
            tutorLines.removeAll { $0.kind == .lesson }
            tutorWrites(["no problem. give it another go."])
        }
    }

    /// Fetch a lesson and start it writing itself onto the page.
    ///
    /// Takes how to get the lesson rather than the lesson itself, because a
    /// mistake and a question are asked about at different addresses but write
    /// out exactly the same once they arrive.
    func write(_ fetch: () async throws -> Lesson) async {
        do {
            tutorWrites(try await fetch().lines, kind: .lesson)
        } catch {
            tutorWrites(["sorry, i can't explain that one."])
        }
    }

    /// Read the last line written as a question, and answer it on the page.
    ///
    /// The last line, rather than anything cleverer, because that rule can be
    /// held in your head: write the question at the bottom, tap Ask. Working
    /// out which of the marks on a page are English and which are algebra is a
    /// guess, and a wrong guess answers a question nobody asked.
    func askQuestion() async {
        guard let written = canvas.writtenLines().last else {
            tutorWrites(["write your question at the bottom, then tap ask."])
            return
        }

        stopListening()
        tutorLines.removeAll { $0.kind == .remark }

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

            tutorWrites([reply, "want me to work one through? write yes"])

            offer = .example(question)
            offerLine = tutorLines.last?.line
            answered = nil
            answerSeen = nil
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

        // A safe moment to catch the paper up with how far down they have got.
        growPage()

        errorLine = nil
        solvedLine = nil

        // An offer from the last check is about work that has since changed,
        // so stop waiting on it, and rub out what was said about that work.
        // Without this the same verdict is written again on every check and
        // the page fills with copies of it. A lesson is kept: it was asked
        // for, and it is what they are working from.
        stopListening()
        tutorLines.removeAll { $0.kind == .remark }

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

            // Kept so a question asked afterwards carries the working with it.
            lastRead = result.recognized ?? []

            // Anything the recognizer could not make sense of stays in a note.
            // It is a remark about the reading, not something a tutor would
            // write on a student's page.
            if !skipped.isEmpty {
                show(Feedback(text: "Skipped some writing.", tone: .plain, skipped: skipped))
            }

            if result.ok {
                if lines.isEmpty {
                    tutorWrites(["write your first step underneath."])
                } else if result.solved == true {
                    // Tick the last line that was written
                    solvedLine = lines.last?.lineNumber
                    solvedProblems.insert(currentIndex)
                    tutorWrites(["solved. \(result.answer ?? "")".lowercased()])
                } else {
                    // A quadratic can be half done — one root written, the
                    // other still to find. The server knows how many answers
                    // the question has, so when it has something more useful
                    // to say than "keep going", it says it.
                    tutorWrites([(result.message ?? "correct so far. keep going.").lowercased()])
                }
            } else {
                // The server counts written lines from 1; turn that back into
                // the ruled line it was actually written on.
                if let step = result.errorStep, step - 1 < lines.count {
                    errorLine = lines[step - 1].lineNumber
                }

                var says = [(result.message ?? "something doesn't follow.").lowercased()]

                // A step is marked wrong until it is taken off the page, so
                // writing a better one underneath does not settle it. Left
                // unsaid, the same complaint comes back after work that looks
                // like it should have answered it, and the cross is by then
                // far enough up the page to be out of sight.
                if let marked = errorLine, marked < (lines.last?.lineNumber ?? 0) {
                    says.append("that line has a cross by it. rub it out and carry on from there.")
                }

                // The offer goes on the end of the same batch, so it writes
                // itself once the explanation above it has finished rather
                // than racing it down the page.
                if result.help != nil {
                    says.append("want a hand? write yes")
                }

                tutorWrites(says)

                if let help = result.help {
                    offer = .help(help)
                    offerLine = tutorLines.last?.line
                    answered = nil
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
}

#Preview {
    ContentView()
}
