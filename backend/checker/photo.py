"""
Reads a photograph of a page, and does with it whatever the student asked.

The page might be a worksheet of questions to copy down, or it might be a
revision sheet covered in formulas, in which case copying it down would be
useless — what is wanted there is the ideas written out and some questions set
to practise on.

So the student says what they want, in their own handwriting or typed, and that
comes in alongside the picture. Left unsaid, we judge it from the page.

Two things come back. `sheet` is a page of notes, laid out in titled boxes the
way a good revision sheet is. `questions` are algebra, and algebra is held to
the rule that holds everywhere else here: every one is parsed before it is
offered, and anything we could not mark is dropped. A question copied down
wrongly is worse than one not copied at all — the student would work faithfully
through a problem that was never set, and be marked against it.

The sheet is structured rather than prose because the model is not allowed to
design anything. It chooses what to say and which box to file it under; the
iPad decides what a box of that kind looks like. Left to lay out its own page a
model produces something different every time, and a set of notes whose formula
box is somewhere new on every sheet is a set of notes you cannot skim.
"""

import os
from typing import Literal

from dotenv import load_dotenv
from openai import OpenAI
from pydantic import BaseModel
from sympy import solve

from checker.graphs import plot
from checker.handwriting import as_written
from checker.parser import parse_equation, plain_symbols
from checker.voice import PUNCTUATION

load_dotenv()

MODEL = "gpt-5.6-luna"

# How much of a page one upload can turn into.
#
# Bigger than it used to be. Notes were written out stroke by stroke in front of
# the student, so twelve lines was already a minute of watching; a laid-out
# sheet arrives at once, and can afford to be a sheet.
MOST_CARDS = 12
MOST_LINES = 6
MOST_QUESTIONS = 8

# What a box can be. The model picks one of these and nothing else — no colours,
# no sizes, no positions. That single word is what the iPad turns into a look.
KINDS = (
    "definition",
    "formula",
    "method",
    "example",
    "keypoints",
    "tip",
    "graph",
)

INSTRUCTIONS = """
You are a patient maths tutor. A student has photographed a page and told you
what they want done with it. The page might be homework, a textbook, or their
own revision notes.

Answer with a sheet of notes and a list of questions. Either may be empty; be
led by what they asked for.

The sheet is a revision sheet: a title, and boxes. Give it a title naming the
topic, like "Quadratic Equations". Then at most twelve boxes, each with a short
heading, a kind, and at most six lines.

The sheet scrolls, so it is not limited to what fits on one screen. A topic
that genuinely needs a dozen boxes should have a dozen.

The kinds, and what belongs in each:

definition - what the thing is. Nearly every sheet wants one, and it goes
             first, because the rest means nothing without it.
formula    - a rule worth remembering exactly, written out as it is used.
method     - how to do it. One step per line, in order.
example    - one worked case, a line per step, ending at the answer. Pick a
             case that shows the method rather than the easiest one.
keypoints  - the things that are true and worth knowing, that fit nowhere else.
tip        - one thing they will get wrong if nobody says it. At most one box
             of these per sheet, and only when there is a real trap.
graph      - one curve, drawn properly with its roots marked. Each one is
             drawn small, so several of them side by side is the normal way to
             use these rather than the exception.

             Put the function in `graph` on its own, with no "y =" in front:
             x**2 - 4x + 3, not y = x**2 - 4x + 3. One unknown only, and a
             function rather than an equation, nothing with an equals sign.
             Add a line or two saying what to look at.

             Draw one whenever the topic has a shape to it. Anything about
             quadratics, parabolas, roots, the discriminant, lines, gradients,
             or where a graph cuts an axis is better with the picture than
             without it, and a student revising from this sheet will look at
             the curve before they read a word of it. Pick a case that shows
             the point being made: for roots, one that plainly crosses twice.

             Draw several when the topic is about how a shape changes.
             Transformations, shifts, stretches and reflections are the clear
             case: give the plain curve a box of its own and then one box for
             each change, so the student can hold them side by side. x**2,
             then x**2 + 2, then (x - 3)**2, then -(x - 2)**2 + 3 teaches more
             than any sentence about it, and the heading on each box should
             name the change rather than repeat the function.

             Every graph has to earn its box by showing the thing that box is
             about. Never draw one to fill the sheet out, and never draw the
             same curve twice.

How to write a box:

- Every line is handwritten onto paper, so keep to about ten words. A line that
  runs on gets broken across the box and stops looking like a note.
- One thought per line. Say why a rule holds, not just what it is.
- Plain words wherever a plain word will do: "square both sides last" beats a
  symbol they have to decode.
- Do not repeat yourself between boxes. Each earns its place.

Prefer four good boxes to twelve thin ones. A sheet is for looking things up
later, not for proving the page was read. Length is worth having only when
every box in it is worth reading.

questions - equations for them to solve. Copy them off the page when the page
            is a worksheet. Set fresh ones when the page is notes and they want
            practice: make them fit what the page covers, and build up from
            straightforward to harder. At most eight.

            Leave empty if they only asked to have the page explained.

If they did not say what they wanted: a page of questions gets copied into
`questions`, and a page of notes or formulas becomes a sheet with a few
questions set to practise on.

How to write the maths:
- Plain text, no LaTeX, no backslashes, no dollar signs.
- Powers use two stars: x**2.
- Multiplication can be implied: 2x, not 2*x.
- Divide with a slash: x/2.
- Every question is one equation with exactly one equals sign and exactly one
  unknown to solve for, and that unknown is always called x. If the sheet names
  it something else, rename it to x when you write the question out. Nothing
  that is not an equation belongs in `questions`.

If the picture is too blurred or dark to read with confidence, answer with an
empty sheet and no questions. Guessing at a question is worse than admitting
you cannot read it.
""".strip()


class Card(BaseModel):
    heading: str
    kind: Literal[KINDS]
    lines: list[str]

    # A function of one unknown to draw, on a graph card. Everything about the
    # curve — where it goes, where it crosses, where it turns — is worked out
    # from this by SymPy rather than taken from the model.
    graph: str | None = None


class PageReading(BaseModel):
    title: str
    cards: list[Card]
    questions: list[str]


def trouble_with(error):
    """
    Say what went wrong in a way that tells the student what to do about it.

    An empty page has two quite different causes, and they ask for opposite
    things. A photograph of a blurred desk means take another one. A server
    that could not be reached means no photograph will ever help, and taking
    six more is a waste of somebody's evening.
    """
    name = type(error).__name__

    if name in ("APIConnectionError", "APITimeoutError"):
        return "Couldn't reach the tutor. Check the Mac is online, then try again."

    if name == "RateLimitError":
        return "The tutor is busy right now. Try that again in a moment."

    if name in ("AuthenticationError", "PermissionDeniedError"):
        return "The server's OpenAI key was refused."

    return "Something went wrong reading that photo."


def read_page(image_base64, instruction=None):
    """
    Read the page, and return what to write on it and what to set.

    Never raises. A photograph that cannot be read is an ordinary outcome, and
    the app treats empty lists as "nothing came of that one" — but `trouble`
    carries the reason when the emptiness was this end's fault rather than the
    photograph's.
    """
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        print("photo: no OPENAI_API_KEY set")
        return {
            "sheet": None,
            "questions": [],
            "trouble": "The server has no OpenAI key set.",
        }

    asked = (instruction or "").strip()

    try:
        reply = OpenAI(api_key=api_key).responses.parse(
            model=MODEL,
            instructions=f"{INSTRUCTIONS}\n\n{PUNCTUATION}",
            input=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                f"They asked: {asked}"
                                if asked
                                else "They did not say what they wanted."
                            ),
                        },
                        {
                            "type": "input_image",
                            "image_url": f"data:image/jpeg;base64,{image_base64}",
                        },
                    ],
                }
            ],
            text_format=PageReading,
        )
        reading = reply.output_parsed
    except Exception as error:
        print(f"photo: could not be read ({type(error).__name__}: {error})")
        return {"sheet": None, "questions": [], "trouble": trouble_with(error)}

    if reading is None:
        return {"sheet": None, "questions": [], "trouble": None}

    # Told to keep it short, a model still sometimes empties the whole page
    # onto the student. A sheet is for looking things up later, and one with
    # forty boxes is one nobody looks anything up in.
    cards = [
        drawn for card in reading.cards[:MOST_CARDS] if (drawn := for_sheet(card))
    ]

    return {
        "sheet": {"title": for_page(reading.title), "cards": cards} if cards else None,
        # `**` is what the checker reads, but not what a page says. The question
        # is written onto the paper by hand, and a caret is what the stroke font
        # raises — and what the built-in questions already use.
        "questions": [
            question.replace("**", "^")
            for question in reading.questions[:MOST_QUESTIONS]
            if solvable(question)
        ],
        # The photograph was read. Anything empty about what came back is the
        # page's own doing, and the app already has words for that.
        "trouble": None,
    }


def for_page(note):
    """A line of notes, with anything the page cannot draw taken back out."""
    return as_written(plain_symbols(note).replace("**", "^")).strip()


def for_sheet(card):
    """
    One box, ready to be drawn, or None if there is nothing left in it.

    A graph is worked out here rather than trusted: the model names a function
    and SymPy decides everything about the curve. A function that cannot be
    drawn honestly costs the graph, not the box — the lines beside it still say
    something worth reading.
    """
    lines = [
        written for line in card.lines[:MOST_LINES] if (written := for_page(line))
    ]

    graph = plot(card.graph) if card.graph else None

    # A graph card whose graph did not survive is a heading over nothing.
    if not lines and not graph:
        return None

    return {
        "heading": for_page(card.heading),
        "kind": card.kind,
        "lines": lines,
        "graph": graph,
    }


def solvable(question):
    """
    Whether this is something the student could actually be set, and we could
    actually mark.
    """
    try:
        equation = parse_equation(question)
    except Exception:
        return False

    # Exactly one unknown. No unknowns is a statement of fact rather than a
    # question, and two describes a line rather than an answer — neither is
    # something this app knows how to walk a student through.
    if len(equation.free_symbols) != 1:
        return False

    # And an answer they could write down. Asked for practice on the
    # discriminant, a model will dutifully set one with a negative one to show
    # what that looks like — but the honest answer there is "no real
    # solutions", which is a sentence, not a line of algebra. There is nothing
    # the student could write that this app would mark as finishing it.
    try:
        answers = solve(equation)
    except Exception:
        return False

    return bool(answers) and all(answer.is_real for answer in answers)
