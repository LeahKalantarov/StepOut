from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from checker.answers import answer
from checker.handwriting import (
    as_written,
    read_handwriting,
    read_words,
    split_on_arrows,
)
from checker.lesson import teach, work_through
from checker.parser import parse_equation, parse_latex_equation
from checker.photo import read_photo
from checker.problems import get_problem, list_problems
from checker.review import review_lines
from checker.step_checker import check_page, check_steps
from checker.tutor import explain

app = FastAPI()

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

    # Which problem the student is working on. None means free practice,
    # where we only check that the steps follow each other.
    problem_index: int | None = None


class WordsRequest(BaseModel):
    rows: list[Row]


class LessonRequest(BaseModel):
    wrong_line: str
    question: str | None = None
    previous_line: str | None = None

    # What the checker decided was wrong with the step, in its own words.
    reason: str | None = None


class AskRequest(BaseModel):
    question: str

    # The problem they are on, and the lines they have written under it. A
    # question like "why doesn't that work" means nothing without them.
    problem: str | None = None
    work: list[str] | None = None


class PhotoRequest(BaseModel):
    # The photograph itself, base64 encoded. Sent in the body rather than as a
    # file upload so it travels the same way every other request does, and the
    # iPad does not need a second kind of networking code for one screen.
    image_base64: str

    media_type: str = "image/jpeg"

    problem_index: int | None = None


# A row has to have at least this many strokes before we spend a recognition
# call asking whether it was words. Annotations like "÷2" are shorter than any
# question anyone has ever written.
LEAST_STROKES_FOR_WORDS = 4

# How many unreadable rows to look at. Every one costs a call to the reader and
# possibly a second to the tutor, and a question is nearly always the last
# thing written, so we look at the end of the page and stop.
MOST_ROWS_TO_REREAD = 2


def marked_as_a_question(words):
    """
    Whether a line of writing was meant for the tutor rather than for the page.

    Two markings, both of them things people already do. A star in front is the
    one to teach, because it is quick and it survives being read back. A
    question mark on the end costs nothing to accept and is what everybody
    reaches for first.
    """
    words = words.strip()

    return words.startswith("*") or words.endswith("?")


def questions_on_the_page(unread, problem, work):
    """
    Read the rows that were not algebra, and answer any that were questions.

    Anything else on those rows is left alone. Working out is full of lines
    that are not equations — a crossed-out term, "-5" written under both
    sides — and answering those would be worse than ignoring them.
    """
    replies = []

    for strokes in unread[-MOST_ROWS_TO_REREAD:]:
        try:
            words = read_words(strokes)
        except Exception:
            continue

        print(f"not algebra, read as words: {words!r}")

        if not marked_as_a_question(words):
            continue

        asked = words.strip().lstrip("*").strip()
        reply = answer(asked, problem, work)

        if reply:
            replies.append({"asked": asked, "answer": reply})

    return replies


@app.get("/")
def home():
    return {"message": "StepOut API — send a POST request to /check"}


@app.get("/problems")
def read_problems():
    """
    The whole set, so the iPad can show the student what is coming.
    """
    return {"problems": list_problems()}


@app.get("/problem/{index}")
def read_problem(index: int):
    """
    Hand the iPad one problem to show the student.
    """
    problem = get_problem(index)

    if problem is None:
        return JSONResponse(
            status_code=404,
            content={"message": "No problem at that number."},
        )

    # Deliberately leave the answer out. The iPad never needs it, and anything
    # sent to the app can be read by the student.
    return {
        "index": problem["index"],
        "total": problem["total"],
        "prompt": problem["prompt"],
        "equation": problem["equation"],
    }


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

        for row_number, row in enumerate(request.rows):
            if len(row.strokes) == 0:
                continue

            strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
            latex = read_handwriting(strokes)
            print(f"row {row_number + 1}: {len(row.strokes)} strokes -> {latex!r}")

            found_here = 0

            # One line can hold more than one step when the student chains them
            # with arrows, so ask for the steps rather than assuming there is
            # one. They all point back at the same row, which is what a mark in
            # the margin needs.
            for step in split_on_arrows(latex):
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
                unread.append(strokes)

        # Which problem they are on, needed both for checking their copy of it
        # and for answering anything they asked about it.
        problem = None
        problem_equation = None
        if request.problem_index is not None:
            problem = get_problem(request.problem_index)
            if problem is not None:
                problem_equation = parse_equation(problem["equation"])

        asked = questions_on_the_page(
            unread,
            problem["equation"] if problem else None,
            written,
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
                else "No equations found yet — write a full line like 2x = 8.",
            }

        result = check_page(equations, written, problem_equation)
        result["recognized"] = written
        result["ignored"] = ignored
        result["questions"] = asked

        if not result["ok"]:
            step = result["error_step"]

            # The very first line has no line above it, so what it had to follow
            # from was the question itself.
            question = problem["equation"] if problem else None
            came_from = written[step - 2] if step >= 2 else question

            explanation = explain(
                question, came_from, written[step - 1], result.get("reason")
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

        verdict = "ok" if result["ok"] else f"WRONG ({result.get('reason')})"
        attempts = result.get("attempts", 1)
        print(
            f"problem={request.problem_index} {len(equations)} equation(s)"
            f" in {attempts} attempt(s), read #{result.get('attempt_read', 1)}"
            f" -> {verdict}, help={'yes' if 'help' in result else 'no'}"
        )

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )


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

        print(f"read as words: {words}")

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
    reply = answer(request.question, request.problem, request.work)

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
    lesson = work_through(request.question, request.problem)

    if lesson is None:
        return JSONResponse(
            status_code=503,
            content={"message": "No example this time."},
        )

    return lesson


@app.post("/check-photo")
def check_photograph(request: PhotoRequest):
    """
    Read a photograph of working, then mark it the same way as a written page.

    The answer has the same shape as /check-handwriting, so the iPad shows a
    photographed mistake exactly as it shows one made on the page — including
    offering to teach the step, because `help` is filled in the same way.

    One difference worth knowing: `error_step` counts the lines of maths read
    off the photograph, not ruled rows on the iPad's page. There is nothing on
    the page to draw a cross beside, so the app names the line instead.
    """
    try:
        lines = read_photo(request.image_base64, request.media_type)
        print(f"photo read as {len(lines)} line(s): {lines}")

        if not lines:
            return {
                "ok": True,
                "recognized": [],
                "ignored": [],
                # Said as something to do rather than something that failed.
                # Nearly every unreadable photo is a photo of the right thing
                # taken badly, and the fix is another photo.
                "message": "I couldn't read any maths in that photo. "
                "Try again with the page flat and the writing filling the frame.",
            }

        result = review_lines(lines, request.problem_index)

        verdict = "ok" if result["ok"] else f"WRONG ({result.get('reason')})"
        print(f"photo problem={request.problem_index} -> {verdict}")

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )
