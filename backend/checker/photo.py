"""
Reads a photograph of handwritten working into lines of maths.

This is the same job MyScript does for Apple Pencil strokes, for the times
there are no strokes to read: work done on real paper before the app was open,
a worksheet, a whiteboard, a friend's page.

The rule from the rest of the app holds here. The model is asked to *read*,
never to judge. It transcribes what is on the paper, mistakes and all, and
SymPy decides whether any of it follows. A reader that quietly corrected
2x = 8 -> x = 5 into x = 4 would hide the very thing the student needs to see,
so the instructions below spend most of their words forbidding exactly that.
"""

import base64
import binascii
import os
import re

from dotenv import load_dotenv
from openai import OpenAI

from checker.handwriting import as_written

load_dotenv()

# Reading a photograph is harder than writing one sentence about two equations,
# so this is deliberately not tied to the model the tutor's voice uses.
MODEL = os.getenv("PHOTO_MODEL", "gpt-5.6-luna")

WORKING_INSTRUCTIONS = """
You transcribe photographs of handwritten maths. You are a pair of eyes, not a
tutor and not a solver.

Write out every line of working you can see, in the order it appears down the
page, one line per line of output.

Rules, in order of importance:
- Copy what is actually written, including mistakes. If the page says x = 5 and
  that is wrong, write x = 5. Never correct, never simplify, never solve.
- Plain maths as it is written on paper: 2x + 5 = 13. No LaTeX, no backslashes,
  no dollar signs, no markdown.
- One step per line. No numbering, no bullets, no commentary.
- Skip anything crossed out, and skip annotations that are not equations, such
  as "-5" written under both sides.
- If a character is genuinely unreadable, leave that whole line out rather than
  guessing at it.
- If there is no handwritten maths in the photograph at all, output nothing.
""".strip()

ASSIGNMENT_INSTRUCTIONS = """
You transcribe photographs of maths worksheets and assignments. You are a pair
of eyes, not a tutor and not a solver.

Write out the questions the student has been asked to solve, one per line, in
the order they appear.

Rules, in order of importance:
- Only the questions. If someone has started working on them, ignore the
  working and write out the question it started from.
- Never solve anything. "3x = 21" stays "3x = 21". Never write the answer.
- Just the equation, with the wording around it dropped. "1. Solve for x:
  3x = 21" becomes "3x = 21".
- Plain maths as it is written on paper. No LaTeX, no backslashes, no dollar
  signs, no markdown.
- Skip anything that is not an equation to solve: headings, names, dates,
  instructions, page numbers.
- If a question is unreadable, leave it out rather than guessing at it.
- If there are no questions in the photograph at all, output nothing.
""".strip()

# A line of transcription we can use has a variable in it or an equals sign.
# Anything else is the model talking to us despite being asked not to.
LOOKS_LIKE_MATHS = re.compile(r"[=<>]")

# Numbering the model was told not to add, but sometimes does anyway:
# "1.", "2)", "step 3:", "- ".
LEADING_LABEL = re.compile(r"^\s*(?:step\s*)?\d+\s*[.):]\s*|^\s*[-*•]\s*", re.IGNORECASE)


def tidy_lines(text):
    """
    Turn whatever the model replied with into clean lines of maths.

    Kept apart from the request itself so it can be tested without a network
    or a key, which matters because this is where the surprises live: fenced
    code blocks, numbering, and the occasional sentence of commentary.
    """
    lines = []

    for raw in (text or "").splitlines():
        line = raw.strip()

        # Markdown fences around the answer, which no instruction reliably stops.
        if line.startswith("```"):
            continue

        line = LEADING_LABEL.sub("", line).strip()

        if not line:
            continue

        # Written the way the page is written, in case a backslash slipped in.
        line = as_written(line).strip()

        if not line or not LOOKS_LIKE_MATHS.search(line):
            continue

        lines.append(line)

    return lines


def looks_like_an_image(image_base64):
    """
    Whether this is base64 we can hand to the model.

    Checked here rather than at the endpoint so a truncated upload fails with
    something a person can act on, instead of a billing line and a shrug.
    """
    if not image_base64:
        return False

    try:
        base64.b64decode(image_base64, validate=True)
    except (binascii.Error, ValueError):
        return False

    return True


def read_lines(image_base64, instructions, asking, media_type="image/jpeg"):
    """
    Show the photograph to the model, and tidy whatever it says back.

    Returns an empty list when there is no API key, when the photograph holds
    nothing to read, or when the request fails. The caller treats all three the
    same way — as a picture it could not read — because from the student's side
    they are the same thing, and a photograph nobody can read is not an error
    worth a stack trace.
    """
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        print("photo: no OPENAI_API_KEY set, so there is nothing to read it with")
        return []

    if not looks_like_an_image(image_base64):
        print("photo: the upload was not usable base64")
        return []

    try:
        reply = OpenAI(api_key=api_key).responses.create(
            model=MODEL,
            instructions=instructions,
            input=[
                {
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": asking},
                        {
                            "type": "input_image",
                            "image_url": f"data:{media_type};base64,{image_base64}",
                        },
                    ],
                }
            ],
            max_output_tokens=600,
        )
    except Exception as error:
        # Said out loud rather than swallowed. The likeliest cause is a model
        # that cannot see images, and that is a one-line fix in .env — but only
        # if you can tell it apart from a photograph of an empty page.
        print(f"photo: {MODEL} could not read it: {error}")
        return []

    return tidy_lines(reply.output_text)


def read_photo(image_base64, media_type="image/jpeg"):
    """
    Read a photograph of someone's working, line by line.
    """
    return read_lines(
        image_base64,
        WORKING_INSTRUCTIONS,
        "Transcribe the handwritten maths in this photograph.",
        media_type,
    )


def read_assignment(image_base64, media_type="image/jpeg"):
    """
    Read a photograph of a worksheet, and return the questions on it.

    The questions only, never the answers. A sheet somebody has already started
    is the normal case, and the point is to be given the same questions they
    were given, not their attempt at them.
    """
    return read_lines(
        image_base64,
        ASSIGNMENT_INSTRUCTIONS,
        "List the equations this worksheet asks the student to solve.",
        media_type,
    )
