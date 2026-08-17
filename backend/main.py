import re
import time
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from checker.answers import answer
from checker.handwriting import (
    as_written,
    read_handwriting,
    read_words,
    rows_stacked_in,
    split_on_arrows,
    without_arrows,
)
from checker.lesson import teach, work_through
from checker.parser import parse_equation, parse_latex_equation
from checker.photo import read_page
from checker.step_checker import check_page, check_steps
from checker.tutor import explain

app = FastAPI()

# A copy of everything printed, kept on disk.
#
# The terminal running the server scrolls, closes, and belongs to whoever
# started it. Working out why a page was marked the way it was means reading
# back over a whole session, and "what did it say the third time I checked?"
# is not a question anybody can answer from memory.
SESSION_LOG = Path(__file__).parent / "session.log"


def note(message):
    """
    Say something, on screen and in the log.
    """
    print(message)

    try:
        with SESSION_LOG.open("a") as log:
            log.write(f"{datetime.now():%H:%M:%S}  {message}\n")
    except OSError:
        # A log that cannot be written is not worth failing a check over.
        pass

# Phase 3: lets the Next.js site on port 3000 call this server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class CheckRequest(BaseModel):
    steps: list[str]


class Stroke(BaseModel):
    x: list[float]
    y: list[float]


class Row(BaseModel):
    strokes: list[Stroke]


class HandwritingRequest(BaseModel):
    rows: list[Row]

    # The question they are working on, or None for a page with no question
    # on it — a page of notes, or somewhere to practise. Then we only check
    # that each line follows from the one above.
    problem_text: str | None = None

    # How the student wants to be spoken to.
    style: str | None = None

    # What the tutor already knows about them, kept on their iPad and sent
    # here rather than stored. Already summarised into a few sentences.
    history: list[str] | None = None

    # Questions on this page that have been answered once already.
    #
    # A question is written in ink and the ink stays there. Without this, every
    # check for the rest of the page reads those same two question marks, sends
    # them off to be answered again, and writes the answer out a second time
    # underneath the first.
    answered: list[str] | None = None


class PhotoRequest(BaseModel):
    # A JPEG, base64 encoded.
    image: str

    # What the student wants done with the page, in their words. None means
    # they did not say, and the page itself has to suggest what it is for.
    instruction: str | None = None


class WordsRequest(BaseModel):
    rows: list[Row]


class LessonRequest(BaseModel):
    wrong_line: str
    question: str | None = None
    previous_line: str | None = None

    # What the checker decided was wrong with the step, in its own words.
    reason: str | None = None

    style: str | None = None
    history: list[str] | None = None


class AskRequest(BaseModel):
    question: str

    # The problem they are on, and the lines they have written under it. A
    # question like "why doesn't that work" means nothing without them.
    problem: str | None = None
    work: list[str] | None = None

    style: str | None = None
    history: list[str] | None = None


# A row has to have at least this many strokes before we spend a recognition
# call asking whether it was words. Annotations like "÷2" are shorter than any
# question anyone has ever written.
LEAST_STROKES_FOR_WORDS = 4

# How many unreadable rows to look at. Every one costs a call to the reader and
# possibly a second to the tutor, and a question is nearly always the last
# thing written, so we look at the end of the page and stop.
#
# Three rather than two. A page of working carries more jottings than it looks
# like it does — a "-7" under one side, an arrow, a crossed-out line all count
# as rows no algebra was found in — and at two, a question written underneath
# two of those was never even read.
MOST_ROWS_TO_REREAD = 3


# Plain English for "I am stuck".
#
# The markings below are a rule the student has to remember at exactly the
# moment they are least able to — head down, halfway through a step that is not
# working. Somebody who writes "I need help" on their page has asked as plainly
# as anybody needs to, and being ignored for leaving off two question marks is
# the app being pedantic at the worst possible moment.
#
# Only rows no algebra could be found in ever reach this, so an equation is
# never mistaken for a plea. Every phrase here is one nobody writes in the
# middle of working unless they mean it.
HELP_PHRASES = (
    "need help",
    "help me",
    "stuck",
    "understand",
    "dont get",
    "don t get",
    "not sure",
    "confused",
    "lost",
    "explain",
    "what do i do",
    "what now",
    "how do i",
    "why does",
    "why do",
    "why is",
    "what next",
)


def is_an_equation(latex):
    """
    Whether SymPy can make an equation out of this.
    """
    try:
        parse_latex_equation(latex)
        return True
    except Exception:
        return False


def steps_written_on(latex):
    """
    Read one written line as the steps it holds.

    An arrow between two equations means "and then", and splitting on it is how
    a line worked straight across the page is read as the three steps it is.

    An arrow inside one equation means nothing of the sort. Expanding a pair of
    brackets, a student loops each term to the ones it multiplies, and those
    loops come back as arrows sitting in the middle of a single line. Split on
    those, "(x - 3)(x - 3) = 16" became a bracket and a stray "= 16" — so a
    page covered in working was reported as holding no equations at all, and
    the student was told to write a full line while looking at one.

    So a split has to earn it: every piece must be an equation in its own
    right, or the arrows were never separators and the line is read whole.

    Writing stacked one line above another arrives as a matrix, and is taken
    apart first. Each line it held is then read for arrows like any other.
    """
    steps = []

    for line in rows_stacked_in(latex):
        pieces = split_on_arrows(line)

        if len(pieces) > 1 and all(is_an_equation(piece) for piece in pieces):
            steps.extend(pieces)
        else:
            steps.append(without_arrows(line))

    return steps


def asking_for_help(words):
    """
    Whether a line says, in ordinary words, that the student is stuck.

    Read loosely on purpose. The reader hands back its best guess at messy
    handwriting, so punctuation and stray marks are stripped before looking:
    "I need help ?," and "Ineed help." both have to count.
    """
    plain = re.sub(r"[^a-z ]+", " ", words.strip().lower())
    plain = re.sub(r"\s+", " ", plain).strip()

    if not plain:
        return False

    return any(phrase in plain for phrase in HELP_PHRASES)


def marked_as_a_question(words):
    """
    Whether a line of writing was meant for the tutor rather than for the page.

    Two markings. A star in front, and two question marks on the end.

    Two rather than one, which looks fussy and is not. A handwriting reader
    that cannot make out a mark returns a question mark for it, so a single one
    on the end is exactly what comes back from the messiest thing on the page —
    the rows that reach this function are the rows no algebra could be found
    in. Taking one to mean "answer this" would have the tutor interrupting a
    student's worst handwriting to answer a question they never asked.

    Nobody writes two by accident, and it is the same stroke twice.
    """
    words = words.strip()

    if words.startswith("*"):
        return True

    # Spaces taken out of the tail first: "why? ?" and "why ??" are the same
    # intention, and which one comes back is up to the reader, not the student.
    return words.replace(" ", "").endswith("??")


def as_asked(words):
    """
    A question reduced to the part of it that makes it that question.

    Used to tell a question we have answered from one we have not. The raw
    string is too brittle a thing to remember an answer by: the same ink read
    twice comes back with the spacing moved around and a question mark more or
    less, so "why both sides??" and "why both sides ? ?" have to count as one.
    """
    return re.sub(r"[^a-z0-9]+", "", words.lower())


def questions_on_the_page(unread, problem, work, answered=None):
    """
    Read the rows that were not algebra, and answer any that were questions.

    Anything else on those rows is left alone. Working out is full of lines
    that are not equations — a crossed-out term, "-5" written under both
    sides — and answering those would be worse than ignoring them.

    A question already answered is passed over. The ink does not go anywhere
    once it has been answered, so without this it is read again on every check
    for the rest of the page, and answered again each time.
    """
    already = {as_asked(one) for one in answered or []}
    replies = []

    for row, strokes in unread[-MOST_ROWS_TO_REREAD:]:
        try:
            words = read_words(strokes)
        except Exception:
            continue

        marked = marked_as_a_question(words)
        pleading = asking_for_help(words)

        note(
            f"not algebra, read as words: {words!r}"
            f"{' — marked as a question' if marked else ''}"
            f"{' — asking for help' if pleading else ''}"
        )

        if not (marked or pleading):
            continue

        asked = words.strip().lstrip("*").strip()

        if as_asked(asked) in already:
            note(f"already answered, leaving it alone: {asked!r}")
            continue

        reply = answer(asked, problem, work)

        if reply:
            # The row it was asked on goes back with it, so the answer can be
            # written beside the question rather than at the foot of the page.
            replies.append({"asked": asked, "answer": reply, "row": row})

    return replies


@app.get("/")
def home():
    return {"message": "StepOut API. Send a POST request to /check."}


@app.post("/check")
def check_work(request: CheckRequest):
    """
    Receive a list of math steps as JSON, run the checker, return the result.
    """
    try:
        return check_steps(request.steps)
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )


@app.post("/check-handwriting")
def check_handwriting(request: HandwritingRequest):
    """
    Receive Apple Pencil strokes row by row, read them, then check the math.

    Blank rows are skipped, but we remember where each equation came from so
    the iPad highlights the row the student actually wrote on.
    """
    try:
        equations = []
        recognized = []
        written = []
        source_rows = []
        ignored = []
        unread = []

        # The question they are on, needed for checking their first line against
        # it, for answering anything they asked about it, and for knowing which
        # letters are allowed to appear in their working.
        problem_text = request.problem_text
        problem_equation = None

        if problem_text is not None:
            try:
                problem_equation = parse_equation(problem_text)
            except Exception:
                problem_equation = None

        unknowns = problem_equation.free_symbols if problem_equation is not None else set()

        for row_number, row in enumerate(request.rows):
            if len(row.strokes) == 0:
                continue

            strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
            latex = read_handwriting(strokes)
            note(f"row {row_number + 1}: {len(row.strokes)} strokes -> {latex!r}")

            found_here = 0

            # One line can hold more than one step when the student chains them
            # with arrows, so ask for the steps rather than assuming there is
            # one. They all point back at the same row, which is what a mark in
            # the margin needs.
            for step in steps_written_on(latex):
                # Students annotate their work, writing things like "-5  -5"
                # under both sides. Those lines are not equations, so we pass
                # over them instead of letting one of them fail the whole check.
                #
                # Any parse failure counts, not just a missing "=". A scribble
                # can come back as LaTeX that SymPy chokes on in its own way,
                # and one unreadable annotation must never sink the whole page.
                try:
                    equation = parse_latex_equation(step)
                except Exception:
                    ignored.append(as_written(step))
                    continue

                # A line that brings in a letter the question does not have is a
                # misreading, not a step. Solving x + 4 = 11 never involves a y,
                # so when a handwritten 4 comes back as one, the line has to be
                # passed over rather than chained onto the working, where it
                # would fail every step that followed it.
                if unknowns and not equation.free_symbols <= unknowns:
                    note(f"not in the question's letters, passing over: {step!r}")
                    ignored.append(as_written(step))
                    continue

                equations.append(equation)
                recognized.append(step)

                # The reading copy. SymPy is given the LaTeX above; everything
                # from here on is for a person, whether that is the student
                # reading a message or the model writing one.
                written.append(as_written(step))
                source_rows.append(row_number)
                found_here += 1

            # No algebra on this row at all. It might not have been algebra.
            if found_here == 0 and len(row.strokes) >= LEAST_STROKES_FOR_WORDS:
                unread.append((row_number + 1, strokes))

        asked = questions_on_the_page(
            unread, problem_text, written, request.answered
        )

        if len(equations) == 0:
            return {
                "ok": True,
                "recognized": [],
                "ignored": ignored,
                "questions": asked,
                # A page holding nothing but a question has been answered, so
                # do not send them away to write algebra first.
                "message": None
                if asked
                else "No equations found yet. Write a full line like 2x = 8.",
            }

        result = check_page(equations, written, problem_equation)
        result["recognized"] = written
        result["ignored"] = ignored
        result["questions"] = asked

        if not result["ok"]:
            step = result["error_step"]

            # The very first line has no line above it, so what it had to follow
            # from was the question itself.
            question = problem_text
            came_from = written[step - 2] if step >= 2 else question

            explanation = explain(
                question,
                came_from,
                written[step - 1],
                result.get("reason"),
                notes=ignored,
                style=request.style,
                history=request.history,
            )
            if explanation:
                result["message"] = explanation

            # Everything a lesson about this mistake would need, so that if the
            # student asks for help the iPad can hand it straight back to us
            # without having to work out what went wrong all over again.
            result["help"] = {
                "question": question,
                "previous_line": came_from,
                "wrong_line": written[step - 1],
                "reason": result.get("reason"),
            }

            # Translate "2nd equation" back into "the row you wrote it on"
            result["error_step"] = source_rows[step - 1] + 1

        # The same translation for the answer, so the tick and the ring land on
        # the line that answered the question.
        if result.get("answer_steps"):
            result["answer_steps"] = [
                source_rows[step - 1] + 1
                for step in result["answer_steps"]
                if step - 1 < len(source_rows)
            ]

        verdict = "ok" if result["ok"] else f"WRONG ({result.get('reason')})"
        attempts = result.get("attempts", 1)
        note(
            f"problem={problem_text!r} {len(equations)} equation(s)"
            f" in {attempts} attempt(s), read #{result.get('attempt_read', 1)}"
            f" -> {verdict}, help={'yes' if 'help' in result else 'no'}"
        )

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )


@app.post("/read-photo")
def read_photo(request: PhotoRequest):
    """
    Read a photographed page and do with it what the student asked.

    Answers a sheet of notes for their page and questions to set them, either
    of which can be empty. That is not an error: the student points a camera at
    something, and sometimes the something is a blurred desk.
    """
    # Timed because this is the one wait a student actually sits through, and
    # "it feels slow" is not something you can act on. Whether it is twenty
    # seconds or two minutes decides whether the fix is a smaller sheet, a
    # smaller photo, or nothing at all.
    started = time.monotonic()
    reading = read_page(request.image, request.instruction)
    took = time.monotonic() - started

    sheet = reading["sheet"]
    cards = sheet["cards"] if sheet else []
    trouble = reading.get("trouble")

    # The kinds rather than the count, because "seven cards" does not say
    # whether the graph that was asked for was drawn, refused, or never
    # offered — and those want three different fixes.
    if not trouble:
        note(
            f"photo: took {took:.1f}s,"
            f" {len(request.image) * 3 // 4 // 1024}kb sent,"
            f" {[card['kind'] for card in cards]},"
            f" {sum(1 for card in cards if card['graph'])} graph(s) drawn,"
            f" {len(reading['questions'])} question(s)"
            f" — asked for: {request.instruction or 'nothing in particular'}"
        )
    else:
        note(f"photo: gave up after {took:.1f}s — {trouble}")

    return {
        "sheet": sheet,
        "problems": [
            {"index": number, "prompt": "Solve for x", "equation": question}
            for number, question in enumerate(reading["questions"])
        ],
        # Why nothing came back, when the reason was this end's fault. Null
        # when the photograph was read, whatever it turned out to hold.
        "trouble": trouble,
    }


@app.post("/read-words")
def read_written_words(request: WordsRequest):
    """
    Read rows as ordinary writing rather than as algebra.

    Used when the tutor has asked something and is waiting to be answered.
    """
    try:
        words = []

        for row in request.rows:
            if len(row.strokes) == 0:
                continue

            strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
            words.append(read_words(strokes))

        note(f"read as words: {words}")

        return {"words": words}
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"message": str(error)},
        )


@app.post("/lesson")
def write_lesson(request: LessonRequest):
    """
    Teach the idea behind a mistake, on a question that isn't the student's.

    Answers 503 when we have nothing we can stand behind — no API key, or a
    worked example that did not survive being checked. The iPad treats that as
    "no lesson this time" and leaves the page alone, which is the right
    outcome: the cross and the explanation are still there.
    """
    lesson = teach(
        request.question,
        request.previous_line,
        request.wrong_line,
        request.reason,
        request.style,
        request.history,
    )

    if lesson is None:
        return JSONResponse(
            status_code=503,
            content={"message": "No lesson this time."},
        )

    return lesson


@app.post("/ask")
def answer_question(request: AskRequest):
    """
    Answer a question the student wrote on their page.
    """
    reply = answer(
        request.question, request.problem, request.work, request.style, request.history
    )

    if reply is None:
        return JSONResponse(
            status_code=503,
            content={"message": "No answer this time."},
        )

    return {"answer": reply}


@app.post("/work-through")
def work_an_example(request: AskRequest):
    """
    Work an example through in answer to a question.

    Same 503 as /lesson, and for the same reason: an example that failed the
    checker is worse than no example, because it arrives in the tutor's own
    hand and the student has no reason to doubt it.
    """
    lesson = work_through(
        request.question, request.problem, request.style, request.history
    )

    if lesson is None:
        return JSONResponse(
            status_code=503,
            content={"message": "No example this time."},
        )

    return lesson
