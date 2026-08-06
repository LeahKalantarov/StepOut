from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from checker.handwriting import read_handwriting
from checker.parser import parse_latex_equation
from checker.step_checker import check_equations, check_steps
from tutor.prompts import looks_like_pushback
from tutor.respond import tutor_respond

app = FastAPI()

# Phase 3: lets the Next.js site on port 3000 call this server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Lightweight in-memory context keyed by session id from the iPad.
SESSION_CONTEXT: dict[str, dict] = {}


class CheckRequest(BaseModel):
    steps: list[str]


class Stroke(BaseModel):
    x: list[float]
    y: list[float]


class Row(BaseModel):
    strokes: list[Stroke]


class HandwritingRequest(BaseModel):
    rows: list[Row]
    session_id: str | None = None
    notes: str | None = None


class NotesRequest(BaseModel):
    session_id: str
    notes: str


class PhotoRequest(BaseModel):
    session_id: str
    filename: str
    caption: str | None = None
    image_base64: str | None = None


class TutorRequest(BaseModel):
    session_id: str | None = None
    recognized: list[str] = Field(default_factory=list)
    check_result: dict
    student_message: str | None = None
    notes: str | None = None


def _session_context(session_id: str | None) -> dict:
    if not session_id:
        return {}
    return SESSION_CONTEXT.setdefault(
        session_id,
        {"notes": "", "photos": []},
    )


def _read_row(row_number: int, row: Row) -> tuple[int, str | None, object | None]:
    if len(row.strokes) == 0:
        return row_number, None, None

    strokes = [{"x": s.x, "y": s.y} for s in row.strokes]
    latex = read_handwriting(strokes)
    print(f"row {row_number + 1}: {len(row.strokes)} strokes -> {latex!r}")
    equation = parse_latex_equation(latex)
    return row_number, latex, equation


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

        rows_with_ink = [
            (row_number, row)
            for row_number, row in enumerate(request.rows)
            if len(row.strokes) > 0
        ]

        # Read each row in parallel — MyScript is the slow part.
        with ThreadPoolExecutor(max_workers=min(4, max(1, len(rows_with_ink)))) as pool:
            results = list(
                pool.map(
                    lambda item: _read_row(item[0], item[1]),
                    rows_with_ink,
                )
            )

        for row_number, latex, equation in sorted(results, key=lambda item: item[0]):
            equations.append(equation)
            recognized.append(latex)
            source_rows.append(row_number)

        if len(equations) == 0:
            return {"ok": True, "recognized": [], "message": "Nothing written yet."}

        result = check_equations(equations, recognized)
        result["recognized"] = recognized

        if request.notes:
            context = _session_context(request.session_id)
            context["notes"] = request.notes

        # Translate "2nd equation" back into "the row you wrote it on"
        if not result["ok"]:
            result["error_step"] = source_rows[result["error_step"] - 1] + 1

        return result
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )


@app.post("/context/notes")
def save_notes(request: NotesRequest):
    context = _session_context(request.session_id)
    context["notes"] = request.notes
    return {"ok": True, "notes": context["notes"]}


@app.post("/context/photo")
def save_photo(request: PhotoRequest):
    context = _session_context(request.session_id)
    description = request.caption or request.filename
    if request.image_base64:
        description = f"{description} (photo attached)"
    context["photos"].append(description)
    return {"ok": True, "photos": context["photos"]}


@app.post("/tutor/respond")
async def tutor_reply(request: TutorRequest):
    context = _session_context(request.session_id)
    notes = request.notes or context.get("notes") or ""
    photos = context.get("photos") or []

    try:
        payload = await tutor_respond(
            recognized=request.recognized,
            check_result=request.check_result,
            student_message=request.student_message,
            notes=notes or None,
            photo_descriptions=photos or None,
        )
        payload["is_pushback"] = bool(
            request.student_message and looks_like_pushback(request.student_message)
        )
        return payload
    except Exception as error:
        return JSONResponse(
            status_code=400,
            content={"ok": False, "message": str(error)},
        )
