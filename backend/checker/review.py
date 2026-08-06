"""
Marks a page that has already been read into lines of maths.

The iPad's own pages arrive as pen strokes and are handled in main.py, where
there is a lot of care about which ruled row each step came from. Work that
arrives already in words — a photograph, or steps typed in — has none of that
to worry about, so it gets this simpler path: parse, check, and explain.

Nothing here talks to a recognizer. It takes lines and gives back a verdict,
which is what makes it the part worth testing.
"""

from checker.handwriting import as_written
from checker.parser import parse_equation
from checker.problems import get_problem
from checker.step_checker import check_page
from checker.tutor import explain


def review_lines(lines, problem_index=None, narrate=True):
    """
    Check lines of working, and say what went wrong.

    `error_step` counts the lines that parsed as equations, from 1. For a
    photograph that is the same as counting the steps down the page, because
    unreadable lines were dropped before the checker ever saw them — which is
    why they come back in `ignored` for the student to look at.

    `narrate` puts the verdict into a sentence, which costs a call to the
    model. Tests turn it off; they are here for the maths, not the wording.
    """
    equations = []
    written = []
    ignored = []

    for line in lines:
        # Annotations and half-read lines are set aside rather than allowed to
        # fail the page. One unreadable scribble must never sink a good answer.
        try:
            equation = parse_equation(line)
        except Exception:
            ignored.append(as_written(line))
            continue

        equations.append(equation)
        written.append(as_written(line))

    problem = get_problem(problem_index) if problem_index is not None else None
    problem_equation = parse_equation(problem["equation"]) if problem else None

    if not equations:
        return {
            "ok": True,
            "recognized": [],
            "ignored": ignored,
            "message": "I couldn't find any equations in that. Is the whole page in shot?",
        }

    result = check_page(equations, written, problem_equation)
    result["recognized"] = written
    result["ignored"] = ignored

    if not result["ok"]:
        step = result["error_step"]

        # The first line has no line above it, so what it had to follow from
        # was the question itself.
        question = problem["equation"] if problem else None
        came_from = written[step - 2] if step >= 2 else question
        wrong_line = written[step - 1]

        # Everything a lesson about this mistake would need, handed back so
        # that asking for help does not mean working it all out again.
        result["help"] = {
            "question": question,
            "previous_line": came_from,
            "wrong_line": wrong_line,
            "reason": result.get("reason"),
        }

        if narrate:
            explanation = explain(question, came_from, wrong_line, result.get("reason"))
            if explanation:
                result["message"] = explanation

    return result
