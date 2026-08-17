"""
What the tutor knows about a student from before today.

The idea is a doctor's chart. Nobody wants a doctor who starts from nothing
every visit, and nobody learns much from a tutor who explains the same slip
from scratch for the fourth time without ever noticing it is the fourth time.

Nothing is stored here. The record lives on the student's iPad, which is the
only place it needs to live — there are no accounts, and it is their record of
their own work. It arrives already summarised into a handful of sentences, is
used for one request, and is not written down.

Everything in it comes from the checker rather than from a model: how many
questions were finished, how many steps were marked wrong, and the checker's
own name for each mistake. So it is a record of what happened, not a language
model's impression of how someone is getting on — which is the difference
between a chart worth reading and a rumour.
"""

# Only added when there is a chart to read, so a first-time student is not
# given a tutor thinking about a history they do not have.
NAMING = """- If this is a mistake the record says they keep making, say so once, plainly,
  in a way that points at the pattern: "this is the same step that caught you
  last time". Then help with it as normal."""

HOW_TO_USE = f"""
You have a short record of how this student has got on with you before. Use it
the way a good teacher uses knowing a class: quietly, and only when it changes
what is worth saying.

{NAMING}
- If the idea behind it is one you have already taught them, do not teach it
  again from the beginning. Remind them of it in a line and move on to what is
  different this time.
- Never read the record back to them, never quote numbers from it, and never
  use it to praise or scold. "You have got 3 wrong today" is not teaching.
- The record is about the past. What is in front of you is the work on the
  page, and it wins whenever the two disagree.
""".strip()


def recalled(history):
    """
    The chart as a block of context, or "" when there is nothing to recall.
    """
    if not history:
        return ""

    notes = [str(note).strip() for note in history if str(note).strip()]

    if not notes:
        return ""

    return "\n".join(["What you know about this student from before today:", *notes])


def with_chart(instructions, history, names_the_pattern=True):
    """
    The instruction, told how to use a chart — only if one turned up.

    The note beside a step and the lesson under it are written by two separate
    requests. Told the same thing, each says it once and the page carries it
    twice, a few lines apart. So the naming belongs to whoever writes first,
    and the lesson simply does not get that line.
    """
    if not recalled(history):
        return instructions

    guidance = HOW_TO_USE if names_the_pattern else HOW_TO_USE.replace(NAMING + "\n", "")

    return f"{instructions}\n\n{guidance}"
