import PencilKit
import PhotosUI
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    // Every session and every page, owned above this view. The pages shown
    // here are one session's worth of it.
    let library: Library

    // What the tutor knows about this student from before today. Owned above
    // this view because the dashboard shows it too.
    let record: ChartKeeper

    // A photograph the student chose on the dashboard, which arrives with
    // them and is read once the page is up.
    @Binding var arriving: UIImage?

    // Back to the dashboard.
    let onClose: () -> Void

    // The whole page is one canvas, so writing can go anywhere on it.
    @State private var canvas = NotebookCanvas()

    @State private var pen = Pen()

    @State private var currentPageID: UUID?

    // Whether the open session has been read yet.
    @State private var restored = false

    // A question being typed into the drawer, and the page being renamed.
    @State private var typingQuestion = false
    @State private var typed = ""
    @State private var renaming: Page?

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

    // Where along that line the tutor was writing, so the two answers sit
    // under its question rather than under the margin.
    @State private var offerX: CGFloat = NotebookLayout.marginWidth + 16

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

    // How far the paper runs, and where on it the corner of the screen sits.
    @State private var pageHeight: CGFloat = 0
    @State private var scrolledTo: CGPoint = .zero

    // How much the page has been pinched. 1 is the size it is written at.
    @State private var zoom: CGFloat = 1

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

    // The batch a finger is being held on, waiting for keep-or-remove.
    @State private var heldBatch: TutorBatch?

    // Where each batch has been dragged to, and how big it has been pinched.
    @State private var batchOffsets: [UUID: CGSize] = [:]
    @State private var batchScales: [UUID: CGFloat] = [:]

    // The batch currently under a finger, and where that finger landed.
    @State private var draggingBatch: TutorBatch?
    @State private var dragFrom: CGPoint = .zero
    @State private var dragStartedAt: CGSize = .zero

    @State private var pinchingBatch: TutorBatch?
    @State private var pinchStartedAt: CGFloat = 1

    // How the tutor talks. Kept between launches — it is a preference about
    // being taught, not something to set again every time.
    @AppStorage("tutorVoice") private var voice = Voice.encouraging

    // Whether the tutor reads the page by itself. Off to begin with: a tutor
    // that speaks before it has been spoken to is a lot to meet on the first
    // page, and it is easier to turn watching on once you want it than to work
    // out how to make it stop.
    @AppStorage("marking") private var marking = Marking.onAsk

    @State private var showSettings = false

    // How much ink was on the page at the last check, so a pause in writing
    // with nothing new written since does not send the same page again.
    @State private var strokesWhenChecked = 0

    // A check that was ready to go while something was in the way. Whatever was
    // in the way calls back when it is done, rather than being asked again.
    @State private var checkWhenFree = false

    // True while the tutor is answering something nobody asked for. It writes
    // as usual but never moves the page, because the student is still writing
    // and having the paper slide out from under a pencil is worse than not
    // seeing the answer until you look up.
    @State private var writingQuietly = false

    // The last thing the tutor said, so that rechecking unchanged work does
    // not write the same verdict out underneath itself.
    @State private var lastSaid: [String] = []

    // How wide the notebook is, so the tutor can use the full line.
    @State private var pageWidth: CGFloat = 700

    @State private var showQuestions = false
    @State private var showMore = false

    // The homework photo being read, if one has just been chosen.
    @State private var photo: PhotosPickerItem?
    @State private var readingPhoto = false

    // The notes printed on this page, if it is a sheet read off a photograph.
    @State private var sheet: NoteSheet?

    // How far down the page the sheet of notes reaches, so the button that
    // follows it can sit at the end of the reading rather than over it.
    @State private var sheetBottom: CGFloat = 0

    // The chosen picture, held while we ask what to do with it.
    @State private var picture: ChosenPhoto?

    /// The pages of the open session.
    private var pages: [Page] {
        library.pages
    }

    private var currentPage: Page? {
        pages.first { $0.id == currentPageID }
    }

    /// The question this page is marked against, if it has one.
    private var question: String? {
        currentPage?.question
    }

    /// How wide a column the tutor writes in.
    ///
    /// The same in both layouts, and narrower than the page on purpose. It
    /// means a line wrapped for the page still fits the panel, so moving the
    /// tutor from one to the other never has to break its writing up again —
    /// and half-written text does not jump about mid-sentence.
    private let tutorWidth: CGFloat = 380

    /// Height of the tutor's handwriting — a little smaller than the question.
    private let tutorHeight: CGFloat = 18

    /// Lines sit closer together in the panel than on ruled paper.

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                appHeader
                page
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
                PagesDrawer(
                    pages: pages,
                    currentPageID: currentPageID,
                    onSelect: open,
                    onAddNotes: { add(.notes(nextNotesName())) },
                    onAddQuestion: { typed = ""; typingQuestion = true },
                    onRename: { renaming = $0; typed = $0.name },
                    onDelete: remove,
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

            Button(tutorApart ? "Tutor on the page" : "Tutor in its own panel") {
                tutorApart.toggle()
            }

            Button("Settings") {
                showSettings = true
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
        .confirmationDialog(
            "Tutor note",
            isPresented: Binding(
                get: { heldBatch != nil },
                set: { if !$0 { heldBatch = nil } }
            ),
            presenting: heldBatch
        ) { batch in
            tutorBatchMenu(batch)
        }
        .onChange(of: photo) { _, picked in
            guard let picked else { return }
            Task {
                // Held rather than sent. The same picture is wanted for
                // opposite reasons by different people, so it waits while
                // they say which.
                if let data = try? await picked.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    picture = ChosenPhoto(image: image)
                } else {
                    show(Feedback(text: "Could not open that photo.", tone: .bad))
                }

                // Cleared so choosing the same picture twice still counts.
                photo = nil
            }
        }
        .sheet(item: $picture) { chosen in
            PhotoPrompt(
                picture: chosen.image,
                onSend: { instruction in
                    picture = nil
                    // Its own task, not the check task: reading a page can
                    // choose a new question, and choosing one clears the page,
                    // which cancels the check task. That would be this one.
                    Task { await readPage(chosen.image, asking: instruction) }
                },
                onCancel: { picture = nil }
            )
        }
        .onAppear(perform: restore)
        .onChange(of: scenePhase) {
            // Anything that ends the app — swiped away, killed for memory,
            // replaced by a new build — goes through here first.
            if scenePhase != .active { keep() }
        }
        .alert("New question", isPresented: $typingQuestion) {
            TextField("2x + 5 = 13", text: $typed)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Add") {
                let equation = typed.trimmingCharacters(in: .whitespaces)
                if !equation.isEmpty { add(.question(equation)) }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Write it the way it goes on paper: 2x + 5 = 13, or x^2 - 9 = 0.")
        }
        .alert(
            "Rename page",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ),
            presenting: renaming
        ) { page in
            TextField("Name", text: $typed)

            Button("Rename") { rename(page, to: typed) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                voice: $voice,
                marking: $marking,
                chart: record.chart,
                onForget: { record.forget() },
                onClose: { showSettings = false }
            )
        }
        .onChange(of: paper.shade) {
            pen.follow(paper)
        }
        .tint(Theme.pink)
    }

    // MARK: - Header

    var appHeader: some View {
        HStack(spacing: 16) {
            Button {
                // Put the work down before leaving it. The dashboard counts
                // what is finished, and it should be counting this.
                keep()
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.bold))

                    Text(library.current?.name ?? "Sessions")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.sky, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 220)

            Spacer()

            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Label("Upload", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.sky, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
            .disabled(readingPhoto)
            .opacity(readingPhoto ? 0.6 : 1)

            if let currentPage {
                Text(currentPage.name)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
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
        paper.desk
            .overlay(alignment: .topLeading) {
                paperLayer
                    .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
                    // A sheet lying on a desk rather than a colour running to
                    // the edges, which is what makes the pinched-out page read
                    // as a page.
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    // Grown from the top-left corner and then slid by how far
                    // the canvas has been scrolled. The canvas measures that
                    // in pinched points, so scaling first and shifting second
                    // is what keeps the ruled lines under the ink.
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: -scrolledTo.x, y: -scrolledTo.y)
            }
            .overlay {
                NotebookPage(
                    canvas: canvas,
                    tool: pen.tool,
                    pageHeight: pageHeight,
                    onSqueeze: { pen.isErasing.toggle() },
                    onWriting: { noticeWriting() },
                    onSettled: { penStopped() },
                    onScroll: { scrolledTo = $0 },
                    onZoom: { zoom = $0 },
                    onDoubleTap: { point in
                        if let batch = batch(at: onPaper(point)) {
                            heldBatch = batch
                        }
                    },
                    onHold: { point, phase in
                        holdTutorText(at: onPaper(point), phase)
                    },
                    onPinch: { point, amount, phase in
                        pinchTutorText(at: onPaper(point), by: amount, phase)
                    },
                    isTutorText: { batch(at: onPaper($0)) != nil }
                )
            }
            // Finger gestures on tutor writing used to live in a layer above
            // the canvas, which meant the Pencil could not write anywhere the
            // tutor had written — the invisible tap targets took the strokes.
            // They belong on the canvas itself, where they can be told to
            // ignore the Pencil and leave writing alone.
            // The two answers, on the page under the question they answer.
            .overlay(alignment: .topLeading) {
                if !tutorApart {
                    replyOnThePage
                        .frame(height: pageHeight, alignment: .topLeading)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .offset(x: -scrolledTo.x, y: -scrolledTo.y)
                }
            }
            // Above the canvas rather than on the paper, because anything
            // drawn on the paper is behind the writing layer and a finger
            // never reaches it.
            .overlay(alignment: .topLeading) {
                readyForQuestions
                    .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: -scrolledTo.x, y: -scrolledTo.y)
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

                    // Written answers still work, but there is no "underneath
                    // the question" once the tutor has its own panel, so in
                    // that layout the two answers live here instead.
                    if tutorApart, offer != nil, answered == nil {
                        replyButtons
                            .transition(.scale.combined(with: .opacity))
                    }

                    PenPalette(
                        pen: pen,
                        paper: paper,
                        onUndo: { canvas.undoManager?.undo() },
                        onRedo: { canvas.undoManager?.redo() }
                    )
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

            // Under everything else, because a sheet of notes is what the page
            // is printed with, not something written on it. The student writes
            // on top of it with the Pencil exactly as they would on paper.
            if let sheet {
                NoteSheetView(sheet: sheet, width: pageWidth, ink: paper.questionInk)
            }

            inkMarks

            marginMarks

            // The question, written onto the page a stroke at a time: what to
            // do, then the equation underneath once that line is finished. A
            // page of notes has neither, and starts blank.
            if let question {
                HandwrittenLine(
                    text: "Solve for x",
                    origin: NotebookLayout.penStart(onLine: 0),
                    color: paper.questionInk
                )

                HandwrittenLine(
                    text: question,
                    origin: NotebookLayout.penStart(onLine: 1),
                    color: paper.questionInk,
                    delay: HandwrittenLine.writingTime(for: "Solve for x") + 0.25
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

    /// How many ruled lines something at this line is drawn higher up.
    ///
    /// A folded batch keeps one line for its summary and gives the rest back.
    /// Without this, folding hides the writing but not the hole it left: the
    /// gap stays, the notes below stay where they were, and the space you
    /// folded it to get is still not yours. Unfolding puts it all back.
    func shiftAbove(_ line: Int) -> Int {
        tutorBatches.reduce(0) { saved, batch in
            guard collapsedBatches.contains(batch.id), batch.lastLine < line else {
                return saved
            }

            return saved + (batch.span - 1)
        }
    }

    /// Where a tutor line is actually drawn, once folding above it is counted.
    func drawnLine(_ line: Int) -> Int {
        max(0, line - shiftAbove(line))
    }

    /// Where a touch landed on the paper itself.
    ///
    /// A scroll view reports touches in the space it is currently showing, so
    /// pinched to twice the size, a finger halfway down the screen comes back
    /// as twice as far down the page. Everything the tutor wrote was placed on
    /// the paper at its written size, so touches have to be brought back to
    /// that size before they can be compared with it.
    func onPaper(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    /// Where a batch has been dragged to, and how big it has been pinched.
    ///
    /// The tutor picks a place for its writing, and it picks reasonably, but
    /// it is guessing at what the page will look like by the time the student
    /// reads it. Being able to shove it somewhere else and make it bigger
    /// costs almost nothing here and saves arguing with the placement.
    func placement(of batch: TutorBatch) -> (offset: CGSize, scale: CGFloat) {
        (batchOffsets[batch.id] ?? .zero, batchScales[batch.id] ?? 1)
    }

    /// Where the pen touches down for one line, and how tall it writes.
    func penFor(_ line: TutorLine, in batch: TutorBatch) -> (origin: CGPoint, height: CGFloat) {
        let (offset, scale) = placement(of: batch)

        // Lines are spaced by the ruling when the writing is its normal size.
        // Pinched bigger, they have to spread by the same amount or the
        // letters grow into the line beneath.
        let stepsDown = CGFloat(line.line - batch.firstLine)
        let top = NotebookLayout.penStart(onLine: drawnLine(batch.firstLine), x: line.originX)

        return (
            CGPoint(
                x: top.x + offset.width,
                y: top.y + stepsDown * NotebookLayout.lineHeight * scale + offset.height
            ),
            tutorHeight * scale
        )
    }

    /// The tutor's lesson, written out below the student's own work.
    ///
    /// Each line waits for the ones above it to finish, so the page fills the
    /// way a person would fill it rather than all at once.
    var lessonOnThePage: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tutorBatches) { batch in
                // Something picked up should look picked up. Without this the
                // page gives no sign that a hold did anything, so it reads as a
                // gesture that failed rather than one waiting to be dragged.
                if draggingBatch?.id == batch.id {
                    let held = batchBounds(batch)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.pink.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(paper.tutorInk.opacity(0.5), lineWidth: 1.5)
                        )
                        .frame(width: held.width, height: held.height)
                        .offset(x: held.minX, y: held.minY)
                }

                if collapsedBatches.contains(batch.id) {
                    collapsedBatch(batch)
                } else {
                    ForEach(batch.lines) { line in
                        let pen = penFor(line, in: batch)

                        HandwrittenLine(
                            text: line.text,
                            origin: pen.origin,
                            height: pen.height,
                            color: paper.tutorInk,
                            delay: line.delay,
                            alreadyWritten: line.written
                        )
                    }
                }
            }
        }
    }

    /// Which batch of tutor writing is under a point on the page, if any.
    func batch(at point: CGPoint) -> TutorBatch? {
        tutorBatches.last { batchBounds($0).contains(point) }
    }

    /// Hold a piece of the tutor's writing to pick it up, and move it anywhere.
    ///
    /// Holding does one thing and one thing only. It used to double as a way to
    /// open a menu, which meant a hold that did not move opened something
    /// instead of picking anything up — so the gesture read as "this is a
    /// menu", and the moving was never found. The menu is on a double tap now.
    func holdTutorText(at point: CGPoint, _ phase: GesturePhase) {
        switch phase {
        case .began:
            guard let picked = batch(at: point) else { return }

            draggingBatch = picked
            dragFrom = point
            dragStartedAt = batchOffsets[picked.id] ?? .zero

            // The page must hold still while something on it is being moved,
            // or dragging the writing drags the paper out from under it.
            canvas.isScrollEnabled = false

        case .moved:
            guard let dragging = draggingBatch else { return }

            batchOffsets[dragging.id] = CGSize(
                width: dragStartedAt.width + point.x - dragFrom.x,
                height: dragStartedAt.height + point.y - dragFrom.y
            )

        case .ended:
            canvas.isScrollEnabled = true
            draggingBatch = nil

            // Once, on being put down, rather than on every frame of the drag:
            // the page only has to be long enough to hold the writing where it
            // ended up, and resizing the canvas mid-drag makes it stutter.
            growPage()
            keep()
        }
    }

    /// Pinch a piece of the tutor's writing to make it bigger or smaller.
    func pinchTutorText(at point: CGPoint, by amount: CGFloat, _ phase: GesturePhase) {
        switch phase {
        case .began:
            pinchingBatch = batch(at: point)
            pinchStartedAt = pinchingBatch.map { batchScales[$0.id] ?? 1 } ?? 1

            // The canvas would otherwise zoom the whole page at the same time,
            // since it has no idea there is writing under these fingers. One
            // pinch should do one thing.
            canvas.pinchGestureRecognizer?.isEnabled = pinchingBatch == nil

        case .moved:
            guard let pinching = pinchingBatch else { return }

            // Bounded at both ends: small enough to be unreadable and large
            // enough to bury the student's own work are both easy to reach by
            // accident and awkward to come back from.
            batchScales[pinching.id] = min(2.5, max(0.6, pinchStartedAt * amount))

        case .ended:
            pinchingBatch = nil
            canvas.pinchGestureRecognizer?.isEnabled = true
            keep()
        }
    }

    /// The question this session would move on to, if there is one left.
    ///
    /// Only ever offered at the foot of a sheet of notes, and only while there
    /// is something unanswered to move on to — a sheet whose questions are all
    /// done is a sheet to look things up in, not a starting line.
    var nextQuestion: Page? {
        guard sheet != nil else { return nil }

        return pages.first { $0.isQuestion && !$0.solved }
    }

    /// The button at the end of the reading.
    ///
    /// At the end rather than in a box the moment the notes land, because when
    /// the notes land the honest answer is always no — they have not read them
    /// yet. Put where finishing the reading puts them, it is asked at the only
    /// moment the answer could be yes.
    @ViewBuilder
    var readyForQuestions: some View {
        if let next = nextQuestion {
            Button {
                open(next)
            } label: {
                HStack(spacing: 8) {
                    Text("I'm ready to do questions on this")
                        .font(.subheadline.weight(.bold))

                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.bold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.yellow, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: Theme.outline))
            }
            .buttonStyle(.plain)
            .padding(.leading, SheetLayout.leftMargin)
            .padding(.top, sheetBottom)
        }
    }

    /// The tutor's two answers, sitting on the page under the question.
    ///
    /// In the corner of the screen they were a long way from what they were
    /// about: a question written beside your working, answered somewhere near
    /// the pens. Here they read as part of the same conversation, and tapping
    /// one leaves nothing behind — where writing "yes" leaves a "yes" sitting
    /// in the middle of your working for the rest of the problem.
    var replyOnThePage: some View {
        ZStack(alignment: .topLeading) {
            if offer != nil, answered == nil, let offerLine {
                replyButtons
                    .offset(
                        x: offerX,
                        y: CGFloat(drawnLine(offerLine) + 1) * NotebookLayout.lineHeight + 8
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    var replyButtons: some View {
        HStack(spacing: 10) {
            Text("Want a hand?")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Button("Yes") { replyTask = Task { await answer(.yes) } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.pink)

            Button("No") { replyTask = Task { await answer(.no) } }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .brutalBorder(radius: 24)
    }

    func tutorPanelBatch(_ batch: TutorBatch) -> some View {
        // Lines are broken to fit the page they were written on, and the page
        // is wider than this panel. Breaking them again here would rewrite the
        // sentence from scratch halfway through it, so instead the longest line
        // in the batch picks a size that fits and the batch is written at that.
        let widest = batch.lines
            .map { StrokeFont.width(of: $0.text, height: tutorHeight) }
            .max() ?? 0

        let height = widest > tutorWidth ? tutorHeight * tutorWidth / widest : tutorHeight

        return Group {
            if collapsedBatches.contains(batch.id) {
                Text(batch.lines.map(\.text).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(paper.tutorInkFaded)
                    .lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(batch.lines) { line in
                        // The pen rests on the baseline, so a line drawn from
                        // y = 0 is drawn entirely above its own frame — which
                        // is nothing, as far as the stack above is concerned,
                        // so every line was being given the same no space and
                        // they piled up on one another.
                        HandwrittenLine(
                            text: line.text,
                            origin: CGPoint(x: 0, y: height),
                            height: height,
                            color: paper.tutorInk,
                            delay: line.delay,
                            alreadyWritten: line.written
                        )
                        .frame(height: height * 1.35, alignment: .leading)
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
    ///
    /// Folded has to read as folded. Set in caption it came out as a thin grey
    /// ribbon of unreadable print across the page, which looks like the tutor
    /// wrote something and the app failed to draw it — so the student's own
    /// page appears broken to anybody looking at it. A fold is a choice, and it
    /// should look like one: legible, plainly cut short, and obviously openable
    /// again.
    func collapsedBatch(_ batch: TutorBatch) -> some View {
        let summary = batch.lines.map(\.text).joined(separator: " ")
        let originX = batch.lines.first?.originX ?? NotebookLayout.marginWidth + 16
        let line = drawnLine(batch.firstLine)
        let (offset, _) = placement(of: batch)

        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))

            Text(summary)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(paper.tutorInkFaded)
        .frame(maxWidth: min(pageWidth - originX - 24, 420), alignment: .leading)
        .padding(.leading, originX + offset.width)
        .padding(.top, NotebookLayout.penStart(onLine: line).y - tutorHeight + offset.height)
    }

    /// The patch of page a batch of writing covers, for a finger to catch.
    ///
    /// Built from where each line is actually drawn rather than from the first
    /// line and a width. Lines no longer share a starting point — the first one
    /// tucks in beside the student's working while the ones under it run from
    /// the margin — so measuring the whole batch from the first line's corner
    /// puts the catchable patch somewhere the writing mostly is not.
    func batchBounds(_ batch: TutorBatch) -> CGRect {
        let (offset, scale) = placement(of: batch)

        if collapsedBatches.contains(batch.id) {
            // Folded, it is one line of small print however long it was open.
            let originX = batch.lines.first?.originX ?? NotebookLayout.marginWidth + 16
            let top = NotebookLayout.penStart(onLine: drawnLine(batch.firstLine)).y

            return CGRect(
                x: originX + offset.width - 10,
                y: top + offset.height - tutorHeight - 6,
                width: min(pageWidth - originX - 24, 460),
                height: tutorHeight * 1.8
            )
        }

        var box = CGRect.null

        for line in batch.lines {
            let pen = penFor(line, in: batch)
            let width = StrokeFont.width(of: line.text, height: pen.height)

            // The pen touches down on the line the writing stands on, and the
            // letters are above it.
            box = box.union(
                CGRect(
                    x: pen.origin.x,
                    y: pen.origin.y - pen.height,
                    width: max(60, width),
                    height: pen.height * 1.3
                )
            )
        }

        guard !box.isNull else { return .zero }

        // Grown a little all round. A finger is blunter than the thin line of a
        // pen stroke, and having to land exactly on the ink is how something
        // draggable comes to feel like it cannot be picked up.
        return box.insetBy(dx: -14, dy: -12)
    }

    func toggleBatchCollapsed(_ batch: TutorBatch) {
        if collapsedBatches.contains(batch.id) {
            collapsedBatches.remove(batch.id)
        } else {
            markWritten(batch.id)
            collapsedBatches.insert(batch.id)
        }
    }

    /// Take the tutor's earlier passing remarks off the page.
    ///
    /// Everything a batch carries goes with it — where it was folded to, where
    /// it was dragged, how big it was pinched — because leaving any of that
    /// behind would hand a stranger's placement to whatever batch happens to
    /// be created with the same identity later.
    func forgetRemarks() {
        let stale = Set(tutorLines.filter { $0.kind == .remark }.map(\.batch))

        guard !stale.isEmpty else { return }

        for id in stale {
            collapsedBatches.remove(id)
            batchOffsets.removeValue(forKey: id)
            batchScales.removeValue(forKey: id)
        }

        tutorLines.removeAll { stale.contains($0.batch) }
    }

    func removeBatch(_ batch: TutorBatch) {
        collapsedBatches.remove(batch.id)
        batchOffsets.removeValue(forKey: batch.id)
        batchScales.removeValue(forKey: batch.id)
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

    // MARK: - Pages

    /// Turn to a page, putting the open one away first.
    ///
    /// Everything on a page travels together: the ink, the tutor's writing,
    /// and what the student has since done to it. Saving only the strokes
    /// would turn every page change into a small loss.
    func open(_ page: Page) {
        guard page.id != currentPageID else { return }

        putAway()

        checkTask?.cancel()
        writingTask?.cancel()
        stopListening()
        hideFeedback()

        currentPageID = page.id

        let saved = library.work[page.id] ?? PageWork()
        canvas.drawing = saved.strokes

        // Counted after the page is laid down, so that opening old work is not
        // mistaken for writing it and marked the moment it appears.
        stopWatching()
        sheet = saved.sheet
        tutorLines = saved.tutorLines
        collapsedBatches = saved.collapsed
        batchOffsets = saved.offsets
        batchScales = saved.scales

        // Marks are the last check's opinion of another page, so they go. The
        // next check puts them back where they belong.
        errorLine = nil
        solvedLine = nil
        errorInk = nil
        solvedInk = nil
        lastWrongLine = nil
        lastSaid = []
        writingSince = nil
        writingBatch = nil

        canvas.setContentOffset(.zero, animated: false)
        growPage()

        keep()
    }

    /// Remember what is on the open page.
    func putAway() {
        guard let currentPageID else { return }

        library.work[currentPageID] = PageWork(
            drawing: canvas.drawing.dataRepresentation(),
            sheet: sheet,
            tutorLines: tutorLines,
            collapsed: collapsedBatches,
            offsets: batchOffsets,
            scales: batchScales
        )
    }

    /// Put the open page away and write the library to disk.
    ///
    /// Called at the few moments where losing work would actually hurt: after
    /// a check, after a lesson arrives, when a page is added or turned to, and
    /// when the app stops being the thing on screen. Saving on every stroke
    /// would mean serialising the whole drawing while the student is still
    /// mid-word, for no gain — nothing between those moments is at risk.
    func keep() {
        putAway()

        library.change { $0.openPage = currentPageID }
    }

    /// Turn to the page this session was left on.
    ///
    /// Once only. onAppear can fire again when the view comes back, and
    /// turning the page a second time would put the student back at the top
    /// of work they had already moved on from.
    func restore() {
        guard !restored else { return }
        restored = true

        // A photograph chosen on the dashboard: this session exists because
        // of it, so read it now that there is a page to put it on.
        if let arriving {
            picture = ChosenPhoto(image: arriving)
            self.arriving = nil
        }

        guard
            let wanted = library.current?.openPage ?? pages.first?.id,
            let page = pages.first(where: { $0.id == wanted })
        else {
            return
        }

        // open() returns early on the page that is already open, and on
        // arrival none is.
        open(page)
    }

    func add(_ page: Page) {
        library.change { $0.pages.append(page) }
        open(page)
        showQuestions = false
    }

    func remove(_ page: Page) {
        library.work.removeValue(forKey: page.id)
        library.change { $0.pages.removeAll { $0.id == page.id } }

        guard page.id == currentPageID else {
            keep()
            return
        }

        currentPageID = nil

        if let next = pages.first {
            open(next)
        } else {
            clearPage()
        }

        keep()
    }

    func rename(_ page: Page, to name: String) {
        let wanted = name.trimmingCharacters(in: .whitespaces)

        guard !wanted.isEmpty else { return }

        library.change {
            guard let at = $0.pages.firstIndex(where: { $0.id == page.id }) else { return }

            $0.pages[at].name = wanted
        }

        keep()
    }

    /// "Notes", then "Notes 2", and so on. Naming a page is a chore nobody
    /// asked for, so the app does it and renaming stays available.
    func nextNotesName() -> String {
        let taken = pages.filter { !$0.isQuestion }.count

        return taken == 0 ? "Notes" : "Notes \(taken + 1)"
    }

    /// Tick the open page in the drawer.
    func markSolved() {
        library.change {
            guard let at = $0.pages.firstIndex(where: { $0.id == currentPageID }) else { return }

            $0.pages[at].solved = true
        }
    }

    // MARK: - Actions

    /// Read a photographed page and do with it what was asked.
    ///
    /// Two things can come back, and each becomes pages in the notebook.
    /// Questions become a page apiece, so they can be worked in any order and
    /// left half-finished. Notes get a page of their own, written out in the
    /// tutor's hand, which stays there to be turned back to while the
    /// questions are being done.
    ///
    /// Both are added rather than replacing anything, so a bad photograph
    /// costs nothing but the pages it made.
    func readPage(_ image: UIImage, asking instruction: String) async {
        readingPhoto = true
        thinking = true
        defer {
            readingPhoto = false
            thinking = false
        }

        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            show(Feedback(text: "Could not open that photo.", tone: .bad))
            return
        }

        do {
            let reading = try await readPhoto(jpeg, asking: instruction)

            guard reading.sheet != nil || !reading.problems.isEmpty else {
                // Empty for two very different reasons. Told apart by the
                // server, because only it knows whether it got as far as
                // looking at the photograph — and being told to take a better
                // picture of a page that was fine is how you end up taking six
                // of them before finding out the Mac was offline.
                show(Feedback(
                    text: reading.trouble ?? "Nothing on that page I could teach from.",
                    tone: reading.trouble == nil ? .plain : .bad
                ))
                return
            }

            let questions = reading.problems.map { Page.question($0.equation) }
            let notes = reading.sheet.map { Page.notes($0.title) }

            library.change { $0.pages += [notes].compactMap { $0 } + questions }

            // Open the notes if there are any, since that is what you read
            // first, and otherwise the first question. Either way this is a
            // fresh page, so there is no work to lose by turning to it.
            if let opening = notes ?? questions.first {
                open(opening)
            }

            // Printed onto the page rather than written out line by line. A
            // sheet is something to look things up in later, and watching one
            // appear a stroke at a time was what kept it to twelve lines.
            if let notes, notes.id == currentPageID {
                sheet = reading.sheet
                growPage()
                keep()
            }

            show(Feedback(text: summary(of: reading), tone: .good))
        } catch is CancellationError {
            return
        } catch {
            // The student is told one thing because there is only one thing
            // they can do about it. The log gets the actual reason, because
            // "could not read that photo" covers a lost connection and a reply
            // this app failed to understand, and those are not the same bug.
            print("photo: \(error)")

            if !Task.isCancelled {
                show(Feedback(text: "Could not read that photo.", tone: .bad))
            }
        }
    }

    func summary(of reading: PageReading) -> String {
        let cards = reading.sheet?.cards.count ?? 0
        let questions = reading.problems.count

        switch (cards, questions) {
        case (0, let asked):
            return "Added \(asked) question\(asked == 1 ? "" : "s")."
        case (_, 0):
            return "Made you a sheet of notes."
        default:
            return "Notes made, and \(questions) question\(questions == 1 ? "" : "s") to try."
        }
    }

    func clearPage() {
        // A check already on its way would come back and mark writing that is
        // about to be wiped, so call it off first.
        checkTask?.cancel()

        canvas.erasePage()
        stopWatching()
        errorLine = nil
        solvedLine = nil
        errorInk = nil
        solvedInk = nil
        stopListening()
        writingTask?.cancel()
        writingSince = nil
        writingBatch = nil
        tutorLines = []
        lastWrongLine = nil
        lastSaid = []
        collapsedBatches = []
        batchOffsets = [:]
        batchScales = [:]
        hideFeedback()

        canvas.setContentOffset(.zero, animated: false)
        growPage()

        // Clearing has to reach the saved copy too, or the page comes back
        // from the dead the next time the app opens.
        keep()
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
        // Already said, and still on the page. Rechecking work that has not
        // changed reaches the same verdict, and writing it out a second time
        // underneath the first reads as a stutter rather than an answer.
        guard sentences != lastSaid else { return }
        lastSaid = sentences

        // A verdict replaces the verdict before it. Checking a page four times
        // used to leave four remarks scattered around the same few lines, each
        // one written into whatever gap the last had not taken — so the page
        // ended up carrying "correct so far. keep going." beside a later note
        // saying no equations were found, with no way to tell which was still
        // true. Only one of them ever is.
        //
        // Lessons stay. Those were asked for and are worth keeping to look
        // back at, which is the whole difference between the two kinds.
        if kind == .remark {
            forgetRemarks()
        }

        let edges = canvas.inkEdges()
        var spot = nextTutorAnchor(nearLine: nearLine, beside: bounds, pastInk: edges)

        var delay = 0.0
        let batch = UUID()

        for sentence in sentences {
            var words = sentence.split(separator: " ").map(String.init)

            // Filled a line at a time against the room that line actually has,
            // rather than cut to one width decided by the first line. Writing
            // that starts beside a student's working has only the end of that
            // line; the empty lines under it have the whole page, and should
            // use it.
            while !words.isEmpty {
                let taken = StrokeFont.fit(words, height: tutorHeight, into: spot.width)

                tutorLines.append(
                    TutorLine(
                        batch: batch,
                        kind: kind,
                        text: taken.line,
                        line: spot.line,
                        originX: spot.originX,
                        delay: delay
                    )
                )

                delay += HandwrittenLine.writingTime(for: taken.line) + 0.05
                words = taken.rest

                spot = nextRoom(from: spot.line + 1, pastInk: edges)
            }
        }

        growPage()
        scrollIntoView(line: spot.line)

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
                writingBatch = nil
                markWritten(batch)
                freeToCheck()
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
        writingBatch = nil
        markWritten(batch)
        freeToCheck()

        // A lesson still on its way would otherwise arrive and start writing
        // itself moments after being told to stop.
        replyTask?.cancel()
    }

    /// A place on the page for the tutor to start writing.
    ///
    /// Beside the student's ink on the line being discussed — not at the top of
    /// the page, and not forced into a column down the right.
    func nextTutorAnchor(
        nearLine: Int? = nil,
        beside bounds: CGRect? = nil,
        pastInk edges: [Int: CGFloat]
    ) -> Spot {
        var targetLine = nearLine ?? errorLine ?? 2

        if nearLine == nil, let bounds {
            targetLine = max(0, Int(bounds.midY / NotebookLayout.lineHeight))
        } else if nearLine == nil, bounds == nil {
            targetLine = canvas.workingLines(pageWidth: pageWidth).last?.lineNumber ?? targetLine
        }

        return nextRoom(from: targetLine, pastInk: edges)
    }

    /// Somewhere the tutor's pen can touch down, and how far it can run.
    struct Spot {
        let line: Int
        let originX: CGFloat
        let width: CGFloat
    }

    /// The first line from `line` down with room worth writing on.
    ///
    /// Usually the line asked for. A line already full to the right-hand edge
    /// gets skipped rather than written on in a sliver, which is how text ends
    /// up in a narrow ribbon marching down the page.
    func nextRoom(from line: Int, pastInk edges: [Int: CGFloat]) -> Spot {
        for candidate in line...(line + 4) {
            let spot = room(onLine: candidate, pastInk: edges)

            if spot.width >= leastUsefulWidth { return spot }
        }

        // Nothing free nearby — drop below it all and start at the margin.
        let below = line + 5
        let margin = NotebookLayout.penStart(onLine: below).x

        return Spot(line: below, originX: margin, width: pageWidth - rightMargin - margin)
    }

    /// Where writing can start on one ruled line, and how much room it has.
    func room(onLine line: Int, pastInk edges: [Int: CGFloat]) -> Spot {
        let margin = NotebookLayout.penStart(onLine: line).x
        var edge = margin
        var taken = false

        if let ink = edges[line], ink > margin {
            edge = ink
            taken = true
        }

        for written in tutorLines where written.line == line {
            edge = max(
                edge,
                written.originX + StrokeFont.width(of: written.text, height: tutorHeight)
            )
            taken = true
        }

        // An empty line is started from the margin, like any other line of the
        // page. Only a line with something already on it needs a gap first.
        let originX = taken ? edge + NotebookLayout.columnGap : margin

        return Spot(line: line, originX: originX, width: pageWidth - rightMargin - originX)
    }

    /// How much paper to leave down the right-hand side.
    private var rightMargin: CGFloat { 20 }

    /// The narrowest gap worth writing in.
    ///
    /// At 150 a sliver at the right-hand edge counted as room, so a second
    /// remark squeezed in after the first and broke across the page three
    /// words at a time: "no equations" on one line, "found yet write a full
    /// line like 2x = 8." on the next. Wide enough for a few words is not the
    /// same as wide enough to read, and there is a whole empty page below.
    private var leastUsefulWidth: CGFloat { 280 }

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

        // Writing dragged down the page needs paper under it, and the line it
        // was written on says nothing about where it ended up.
        let dragged = batchOffsets.values.map(\.height).max() ?? 0

        // A sheet of notes sets its own length, and there has to be paper
        // under all of it plus room to work underneath.
        sheetBottom = sheet.map { SheetLayout.lay($0, into: pageWidth).height } ?? 0

        let printed = sheetBottom > 0 ? sheetBottom + visibleHeight / 2 : 0

        pageHeight = max(
            max(max(visibleHeight, leastPage), wanted + max(0, dragged)),
            printed
        )
    }

    /// Start waiting for an answer to a question on the page.
    func markOffer(_ newOffer: Offer) {
        offer = newOffer
        strokesWhenOffered = canvas.drawing.strokes.count
        offerLine = tutorLines.last?.line
        offerX = tutorLines.last?.originX ?? NotebookLayout.marginWidth + 16
        answered = nil
        answerSeen = nil
    }

    /// Scroll down far enough to see a given line, if it is below the fold.
    ///
    /// Only ever scrolls down. Being dragged back up while reading something
    /// further up the page would be worse than not following at all.
    func scrollIntoView(line: Int) {
        // Never while the student is writing. They know where their pencil is,
        // and moving the paper under it to show them something they did not ask
        // to see spoils the line they were part-way through.
        guard !writingQuietly else { return }

        // The line is a place on the paper; scrolling happens in what is on
        // screen. Pinched larger, the same line is further down.
        let bottom = CGFloat(line + 2) * NotebookLayout.lineHeight * zoom
        let target = max(0, bottom - visibleHeight)

        guard target > scrolledTo.y + 1 else { return }

        // The paper was made taller a moment ago, but the canvas is not told
        // until SwiftUI next updates it. Going now would scroll against the
        // old, shorter page and be clamped short of the writing.
        Task { @MainActor in
            canvas.setContentOffset(CGPoint(x: scrolledTo.x, y: target), animated: true)
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
    ///
    /// Deliberately does nothing at all the rest of the time. This runs on
    /// every change to the drawing, which while a stroke is being laid down is
    /// many times a second, and touching any state here redraws the page under
    /// the pencil. Whether a step is finished is worked out in the canvas's own
    /// coordinator instead, which can watch the pencil without redrawing
    /// anything.
    func noticeWriting() {
        guard offer != nil else { return }

        replyTask?.cancel()

        replyTask = Task {
            try? await Task.sleep(for: .seconds(0.8))

            guard !Task.isCancelled else { return }

            await readReply()

            // Still nothing answered, so that was not a reply: they have gone
            // back to working rather than saying yes or no. The work has to be
            // picked back up, or one unanswered offer would silence the tutor
            // for the rest of the page.
            if !Task.isCancelled, offer != nil {
                penStopped()
            }
        }
    }

    /// The pen has been put down for long enough to read the page.
    func penStopped() {
        guard marking == .watching else { return }

        // Anywhere except over a printed sheet of notes. There the writing is
        // being copied out rather than worked out, and marking someone's notes
        // wrong as they take them is worse than saying nothing. Rough working
        // on a blank page still gets read: each line has to follow from the
        // one above it even when there is no question at the top.
        guard question != nil || sheet == nil else { return }

        checkUnasked()
    }

    /// Send the page over, unless something is in the way.
    func checkUnasked() {
        guard marking == .watching else { return }

        let strokes = canvas.drawing.strokes.count

        // Nothing written since the last check — a pause on an already-marked
        // page, or the page being put down. Rubbing out counts as a change,
        // because a step taken back changes the verdict on the ones under it.
        guard strokes > 0, strokes != strokesWhenChecked else { return }

        // The tutor's pen is still moving, or a check is already on its way.
        // Noted rather than retried: whichever of them is in the way will say
        // when it is done, so there is nothing to keep asking about.
        guard writingSince == nil, !isChecking else {
            checkWhenFree = true
            return
        }

        checkWhenFree = false
        checkTask = Task { await runCheck(quietly: true) }
    }

    /// Something that was in the way has finished.
    func freeToCheck() {
        guard checkWhenFree else { return }

        checkWhenFree = false
        checkUnasked()
    }

    /// Forget what the last check saw, so the next change reads the page afresh.
    func stopWatching() {
        checkWhenFree = false
        strokesWhenChecked = canvas.drawing.strokes.count
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
            await write {
                try await fetchLesson(
                    for: help,
                    style: voice.rawValue,
                    history: record.chart.forTheTutor
                )
            }

        case (.yes, .example(let question)):
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
            let lesson = try await fetch()
            record.update { $0.learned(lesson.concept) }
            tutorWrites(lesson.lines, kind: .lesson)
            keep()
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
                problem: question,
                work: lastRead.isEmpty ? nil : lastRead,
                style: voice.rawValue,
                history: record.chart.forTheTutor
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
        strokes.asCoordinates()
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

    /// Read the page and mark it.
    ///
    /// A quiet check is one nobody asked for, and it holds its tongue where a
    /// tapped one would speak up.
    func runCheck(quietly: Bool = false) async {
        isChecking = true
        writingQuietly = quietly

        // Registered first so it runs last: anything waiting on this check is
        // let go only once `isChecking` is back down, or it would find the way
        // still blocked and settle in to wait all over again.
        defer { freeToCheck() }
        defer {
            isChecking = false
            writingQuietly = false
        }

        // Noted before the check rather than after, so that anything written
        // while waiting on the server still counts as new when it returns.
        strokesWhenChecked = canvas.drawing.strokes.count

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

        // Nothing finished to read yet. Said nothing about, because nobody
        // asked — the student is mid-thought and does not need telling that
        // they have not written anything yet.
        if quietly, lines.isEmpty { return }

        let rows = lines.map { RowData(strokes: $0.strokes) }

        do {
            let result = try await checkHandwriting(
                rows,
                problemText: question,
                style: voice.rawValue,
                history: record.chart.forTheTutor
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
                    // No algebra on the page yet. Worth saying if they tapped
                    // Check and are waiting to hear something back; not worth
                    // saying to someone who is midway through writing and never
                    // asked. A tutor reading over your shoulder that announces
                    // it cannot see an equation yet is only ever in the way.
                    if !quietly, let nudge = result.message {
                        tutorWrites([nudge.lowercased()], nearLine: near, beside: ink)
                    }
                } else if result.solved == true {
                    // The answer's own row, not the last row on the page. They
                    // are often different: a note in the margin, or the "yes"
                    // that asked for help, is written after the answer and
                    // would otherwise collect the tick.
                    var answered = lines.last

                    if let row = result.answerSteps?.last, row >= 1, row <= lines.count {
                        answered = lines[row - 1]
                    }

                    solvedLine = answered?.lineNumber
                    solvedInk = answered?.bounds
                    markSolved()
                    record.update { $0.solvedOne() }
                    tutorWrites(
                        ["solved. \(result.answer ?? "")".lowercased()],
                        nearLine: answered?.lineNumber,
                        beside: answered?.bounds
                    )
                } else {
                    tutorWrites([(result.message ?? "correct so far. keep going.").lowercased()], nearLine: near, beside: ink)
                }
            } else {
                if let step = result.errorStep, step - 1 < lines.count {
                    errorLine = lines[step - 1].lineNumber
                    errorInk = lines[step - 1].bounds
                }

                // The checker's own words for what went wrong, not the
                // tutor's sentence about it. Two students told "watch the
                // signs" may have done quite different things; the reason is
                // the same string every time it is the same mistake, which is
                // what makes it worth counting.
                record.update { $0.slipped(result.help?.reason) }

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

            keep()
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
    Home()
}
