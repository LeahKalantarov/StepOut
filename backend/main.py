from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from checker.handwriting import read_handwriting
from checker.parser import parse_latex_equation
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


@app.get("/")
def home():
    return {"message": "StepOut API — send a POST request to /check"}


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

        for row_number, row in enumerate(request.rows):
            if len(row.strokes) == 0:
                continue

            strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
            latex = read_handwriting(strokes)

            equations.append(parse_latex_equation(latex))
            recognized.append(latex)
            source_rows.append(row_number)

        if len(equations) == 0:
            return {"ok": True, "recognized": [], "message": "Nothing written yet."}

        result = check_equations(equations, recognized)
        result["recognized"] = recognized

        # Translate "2nd equation" back into "the row you wrote it on"
        if not result["ok"]:
            result["error_step"] = source_rows[result["error_step"] - 1] + 1

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )
