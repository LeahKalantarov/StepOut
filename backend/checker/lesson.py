"""
Teaches the idea behind a mistake, using a question that isn't the student's.

Two rules shape everything here.

The first is that the example must not be the student's own question. Working
their problem for them ends the lesson; working one just like it leaves them
something to do.

The second is that we never write maths onto a student's page without checking
it. A model asked to solve something will occasionally slip, and a wrong worked
example in the tutor's own handwriting is far worse than no help at all —
the student has no reason to doubt it. So every example comes back through the
same checker that marks their work, and anything that fails is thrown away.
"""

import os

from dotenv import load_dotenv
from openai import OpenAI
from pydantic import BaseModel

from checker.parser import parse_equation, plain_symbols
from checker.step_checker import check_equations

load_dotenv()

MODEL = "gpt-5.6-luna"

INSTRUCTIONS = """
You are a patient maths tutor. A student is solving an equation by hand and has
just made a mistake. Teach them the idea they are missing.

Give back four things:

concept  - what this is called, in a few words. For example "dividing both
           sides" or "difference of two squares".
rule     - the rule itself, in one short line they can copy down and look back
           at. Use maths notation, not a sentence.
question - a DIFFERENT equation of the same kind, which needs the same move.
           Never their equation, and never one with their numbers. Keep it
           simple and clean, with whole-number answers.
steps    - your question solved, one line per step, starting with the question
           itself and ending with the answer. Show every step, including the
           small ones. This gets written onto their page by hand.

How to write the maths in `rule` and `steps`:
- Plain text, no LaTeX, no backslashes, no dollar signs.
- Powers use two stars: x**2, not x^2.
- Multiplication can be implied: write 2x, not 2*x.
- Divide with a slash: 42 / 6. Never the printed signs for times or divide.
- Every line in `steps` must be a full equation with exactly one equals sign.
""".strip()


class Lesson(BaseModel):
    concept: str
    rule: str
    question: str
    steps: list[str]


def teach(student_question, previous_line, wrong_line, reason=None):
    """
    Work up a short lesson, or return None if we can't stand behind one.

    Returning None is a perfectly good outcome. The student still gets the
    cross in the margin and a sentence explaining it; they just don't get the
    worked example. Silence is cheap, and a wrong example is not.
    """
    what_happened = "\n".join(
        [
            f"The question they were given: {student_question}" if student_question else "",
            f"The line before: {previous_line}",
            f"The step that does not follow: {wrong_line}",
            # The checker knows what went wrong; without being told, the model
            # has to infer it from two equations and can teach the wrong idea
            # convincingly.
            f"What the checker found: this step {reason}" if reason else "",
        ]
    ).strip()

    return write_lesson(what_happened)


def work_through(asked, problem=None):
    """
    Work an example through in answer to a question, rather than a mistake.

    The student has asked something and wants to see it done. Same safety net:
    the working is checked before it goes anywhere near their page.
    """
    context = "\n".join(
        [
            f"The student asked: {asked}",
            f"They are working on: {problem}" if problem else "",
            "Show them an example of the kind of thing they are asking about.",
        ]
    ).strip()

    return write_lesson(context)


def write_lesson(context):
    """
    Ask for a lesson about `context`, and throw it away unless it checks out.
    """
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        return None

    try:
        reply = OpenAI(api_key=api_key).responses.parse(
            model=MODEL,
            instructions=INSTRUCTIONS,
            input=context,
            text_format=Lesson,
        )
        lesson = reply.output_parsed
    except Exception:
        return None

    if lesson is None or not steps_hold_up(lesson.steps):
        return None

    return {
        "concept": lesson.concept,
        "rule": for_writing(lesson.rule),
        "question": for_writing(lesson.question),
        "steps": [for_writing(step) for step in lesson.steps],
    }


def steps_hold_up(steps):
    """
    Run the model's own working through the checker that marks the student.

    This is the whole safety net. If the example wouldn't pass on the student's
    page, it has no business being written onto it.
    """
    if len(steps) < 2:
        return False

    try:
        equations = [parse_equation(step) for step in steps]
    except Exception:
        # A step we cannot even read is a step we cannot vouch for.
        return False

    result = check_equations(equations, steps)

    # A worked example that stops before the answer teaches half a method.
    return result["ok"] and result.get("solved", False)


def for_writing(text):
    """
    Turn SymPy's spelling into the way it goes on paper.

    We ask the model for `x**2` because that is what the checker can read, but
    nobody writes two stars on a page. Printed symbols like ÷ are swapped out
    too: the stroke font has no glyph for them, so they would come out as gaps.
    """
    return plain_symbols(text).replace("**", "^")
