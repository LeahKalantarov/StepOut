"""
How the tutor talks.

The maths is the same whoever is being taught — it is checked by SymPy and does
not have a mood. What changes is the wrapping around it, and that matters more
than it sounds. A student who has been stuck for twenty minutes and a student
who wants the answer and nothing else are both badly served by the same voice,
and the wrong one reads as either patronising or cold.

So this is only ever added to the end of an instruction. It can change the
warmth, the length, and how much is spelled out. It cannot change what counts
as a right answer, and nothing here is allowed to loosen the rule that the
tutor never gives away the answer to the question in front of them.
"""

ENCOURAGING = """
How to say it: warmly. This student loses heart quickly, so notice what they
got right before you name what went wrong — and mean it, rather than reaching
for praise you do not have. Being wrong is the ordinary way of learning
something, and your tone should take that for granted. Never sound
disappointed.
""".strip()

DIRECT = """
How to say it: briefly. This student wants the mistake named and nothing else.
No preamble, no reassurance, no "nice try" — go straight to what is wrong. One
sentence is usually enough. Being brief is not the same as being cold: say it
plainly, the way you would to someone you respect who is in a hurry.
""".strip()

THOROUGH = """
How to say it: fully. This student wants to understand why, not just what. Give
the reason behind the rule as well as the rule, and say what would have gone
wrong if they had carried on. Take an extra sentence where an extra sentence
earns its place — but do not pad, and do not explain what they have already
shown they know.
""".strip()

VOICES = {
    "encouraging": ENCOURAGING,
    "direct": DIRECT,
    "thorough": THOROUGH,
}

DEFAULT = "encouraging"


def spoken(instructions, style):
    """
    The instruction, with how to say it added on the end.

    An unknown style is not an error. It arrives from the app, and an app one
    version ahead of the server asking for a voice this server has never heard
    of should still get taught — in the ordinary voice, not a 500.
    """
    voice = VOICES.get((style or DEFAULT).strip().lower())

    if voice is None:
        return instructions

    return f"{instructions}\n\n{voice}"
