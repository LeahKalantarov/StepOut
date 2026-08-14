"""
Answers a question the student has written on their page.

Kept apart from lesson.py, which teaches the idea behind a mistake the checker
found. Here there is no mistake and nothing to verify — the student has simply
asked something, and wants an answer rather than a worked example.

Nothing written here is checked by SymPy, because a sentence about method is
not an equation. So the model is told to keep to the idea and leave the working
to `work_through`, where every line does get checked.
"""

import os

from dotenv import load_dotenv
from openai import OpenAI

from checker.handwriting import as_written
from checker.parser import plain_symbols
from checker.chart import recalled, with_chart
from checker.voice import spoken

load_dotenv()

MODEL = "gpt-5.6-luna"

INSTRUCTIONS = """
You are a patient maths tutor sitting beside a student who is working through
algebra by hand, on paper. They have stopped and written you a question.

Answer that question, and only that question.

- Three short sentences at most. Your answer is written onto their page by
  hand, and a long one fills the paper they still need.
- Answer what they asked, not the larger thing behind it.
- Talk about the idea and the method. Do not solve their problem for them.
- If they have only said that they are stuck, or that they do not understand,
  rather than asking anything in particular, look at the lines they have
  written and name the one next thing to do. That is a real question and the
  page in front of you is the answer to it, so never send that student away to
  write it out again.
- If a question you cannot make out is genuinely unreadable, say so plainly and
  ask them to write it again. Do not guess at what they meant.
- Write maths the way it goes on paper: 2x = 8, x^2. No LaTeX, no backslashes,
  no dollar signs, and never the printed signs for times or divide.
- Plain lowercase prose, the way you would say it out loud.
""".strip()


def answer(asked, problem=None, work=None, style=None, history=None):
    """
    Answer the question, or return None if we have nothing worth writing.
    """
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        return None

    # The question alone is often not enough: "why does that not work" only
    # means something next to the problem and the lines they have written.
    context = "\n".join(
        [
            f"They asked: {asked}",
            f"The problem they are working on: {problem}" if problem else "",
            "What they have written so far:" if work else "",
            *(f"  {line}" for line in work or []),
            recalled(history),
        ]
    ).strip()

    try:
        reply = OpenAI(api_key=api_key).responses.create(
            model=MODEL,
            instructions=spoken(with_chart(INSTRUCTIONS, history), style),
            input=context,
            # Mostly thinking room. A budget sized to the answer alone gets
            # spent on reasoning before a word is written, and the student's
            # question comes back unanswered.
            max_output_tokens=500,
        )
    except Exception:
        return None

    # Goes onto the page in a stroke font, which cannot draw a backslash, so
    # any LaTeX the model reached for is taken back out here.
    written = as_written(plain_symbols(reply.output_text.strip()))

    return written or None
