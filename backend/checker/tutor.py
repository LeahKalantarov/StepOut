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
from checker.handwriting import as_written
from checker.chart import recalled, with_chart
from checker.voice import spoken
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

Say what is wrong and what to look at next. Rules:
- At most two short sentences. This appears in a small note on their page.
- Speak to them as "you", warmly and plainly.
- Write maths the way it is written on paper: 2x = 8. No LaTeX, no
  backslashes, no dollar signs. The note has no way to render them.
- Do not give away the answer, and do not write out the corrected step.

About naming what they did wrong. Only say they did a particular thing if the
numbers actually show it. You are not watching them work — you have the line
before, the line after, and whatever they jotted in the margin, and that is
all. Before writing "you subtracted 5 from one side only", do that yourself and
check it gives their line exactly. If it does not, it is not what happened.

When nothing you try reproduces their line, do not invent a reason. Say plainly
what does not add up — which number changed, and what it would have to be —
and send them back to that step. A student told confidently that they did
something they did not do stops trusting you, and starts hunting for a mistake
that is not there.
""".strip()


def explain(
    question, previous_line, wrong_line, reason=None, notes=None, style=None, history=None
):
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
            # The "-5" and "/2" people write under an equation are not steps
            # and never reach the checker, but they are the clearest evidence
            # there is of what the student meant to do. Without them the model
            # is reduced to guessing at intent from the numbers alone, and it
            # guesses confidently and wrongly.
            "What they jotted in the margin: " + ", ".join(notes) if notes else "",
            recalled(history),
        ]
    ).strip()

    try:
        reply = OpenAI(api_key=api_key).responses.create(
            model=MODEL,
            instructions=spoken(with_chart(INSTRUCTIONS, history), style),
            input=student_work,
            # Two sentences need a fraction of this. The rest is thinking room:
            # checking a guess against the numbers before writing it down costs
            # tokens, and a budget that only covers the answer buys silence —
            # the whole allowance goes on reasoning and nothing comes back.
            max_output_tokens=500,
        )
        # This sentence is written onto the page in a stroke font, which has no
        # way to draw a backslash. The model is told to keep away from LaTeX,
        # but being told is not the same as being stopped.
        return as_written(reply.output_text.strip()) or None
    except Exception:
        return None
