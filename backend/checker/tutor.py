"""
Turns a wrong step into an explanation a student can learn from.

The important thing here is what this file does *not* do. SymPy has already
decided whether a step follows, exactly and unarguably, before anything below
runs. The model is only asked to put a mistake that has already been found
into plain words. It never decides whether the student is right.

That keeps the marking exact, and it means a small cheap model is enough,
because writing one sentence about two equations is a much easier job than
doing the algebra.
"""

import os

from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

# The cheapest current model. The hard part was already done by SymPy.
MODEL = "gpt-5.6-luna"

INSTRUCTIONS = """
You are a patient maths tutor sitting beside a student who is working through
algebra by hand, on paper.

A computer algebra system has already checked their work and found the step
wrong. That verdict is correct and final. Never question it, never suggest the
step might be right, and never re-derive the answer to check.

Say what they appear to have done, and what to look at next. Rules:
- At most two short sentences. This appears in a small note on their page.
- Speak to them as "you", warmly and plainly.
- Write maths the way it is written on paper: 2x = 8. No LaTeX, no
  backslashes, no dollar signs. The note has no way to render them.
- Do not give away the answer, and do not write out the corrected step.
- Point at the specific slip if you can see one, for example doing something
  to one side of the equation and not the other.
""".strip()


def explain(question, previous_line, wrong_line, reason=None):
    """
    Say in a sentence or two what went wrong, or None if we can't.

    Returns None when there is no API key, or the request fails, and the
    caller then falls back to its own plain message. A tutor that sometimes
    has nothing to add is fine. A checker that breaks because someone else's
    service is down is not.
    """
    api_key = os.getenv("OPENAI_API_KEY")

    if not api_key:
        return None

    student_work = "\n".join(
        [
            f"The question: {question}" if question else "",
            f"The line before: {previous_line}",
            f"The step that does not follow: {wrong_line}",
            # Told only that a step is wrong, the model has to guess why, and a
            # dropped root looks like sound working right up until you count
            # the answers. The checker already knows; passing it on stops the
            # explanation being about the wrong thing.
            f"What the checker found: this step {reason}" if reason else "",
        ]
    ).strip()

    try:
        reply = OpenAI(api_key=api_key).responses.create(
            model=MODEL,
            instructions=INSTRUCTIONS,
            input=student_work,
            max_output_tokens=120,
        )
        return reply.output_text.strip() or None
    except Exception:
        return None
