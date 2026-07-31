from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from checker.handwriting import read_handwriting
from checker.parser import parse_equation, parse_latex_equation
from checker.problems import get_problem, list_problems
from checker.step_checker import check_equations, check_steps

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
        source_rows = []
        ignored = []

        for row_number, row in enumerate(request.rows):
            if len(row.strokes) == 0:
                continue

            strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
            latex = read_handwriting(strokes)
            print(f"row {row_number + 1}: {len(row.strokes)} strokes -> {latex!r}")

            # Students annotate their work, writing things like "-5  -5" under
            # both sides. Those lines are not equations, so we pass over them
            # instead of letting one of them fail the whole check.
            #
            # Any parse failure counts, not just a missing "=". A scribble can
            # come back as LaTeX that SymPy chokes on in its own way, and one
            # unreadable annotation must never sink the whole page.
            try:
                equation = parse_latex_equation(latex)
            except Exception:
                ignored.append(latex)
                continue

            equations.append(equation)
            recognized.append(latex)
            source_rows.append(row_number)

        if len(equations) == 0:
            return {
                "ok": True,
                "recognized": [],
                "ignored": ignored,
                "message": "No equations found yet — write a full line like 2x = 8.",
            }

        # When the student was given a problem, make sure they copied it right
        problem_equation = None
        if request.problem_index is not None:
            problem = get_problem(request.problem_index)
            if problem is not None:
                problem_equation = parse_equation(problem["equation"])

        result = check_equations(equations, recognized, problem_equation)
        result["recognized"] = recognized
        result["ignored"] = ignored

        # Translate "2nd equation" back into "the row you wrote it on"
        if not result["ok"]:
            result["error_step"] = source_rows[result["error_step"] - 1] + 1

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )
