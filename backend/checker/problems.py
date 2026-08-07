"""
The problems StepOut asks the student to solve.

We only store the equation. The answer is worked out with SymPy when asked,
so a problem can never disagree with its own answer key.
"""

from sympy import solve

from checker.parser import parse_equation

# Roughly easiest to hardest. The linear answers are deliberately all
# different, so a passing check can't be a coincidence while testing.
#
# The quadratics come last, and each has two answers. They are here to exercise
# the part of the checker that tells "you have one of the two" apart from "this
# is wrong": a student who factors and then takes one root has done real work,
# not made a mistake. The pair that is already factored is easiest, and the ones
# needing factoring are hardest.
PROBLEMS = [
    "3x = 21",
    "2x + 5 = 13",
    "4x - 7 = 5",
    "x/2 + 3 = 7",
    "5x + 2 = 3x + 12",
    "6 - 2x = 10",
    "(x - 2)(x + 6) = 0",
    "x^2 = 25",
    "x^2 - 9 = 0",
    "x^2 - 4x = 0",
    "x^2 - 9x + 20 = 0",
    "x^2 + 2x - 15 = 0",
]


def solve_for_answer(equation):
    """
    Work out the answer to an equation, as a string like "x = 4".

    A quadratic has two answers and both of them belong in the answer key, so
    every answer is listed: "x = -3, x = 3". Reporting only the first is how an
    answer key ends up quietly disagreeing with the problem it belongs to.
    """
    variable = sorted(equation.free_symbols, key=str)[0]
    answers = solve(equation, variable)

    if len(answers) == 0:
        return "no answer"

    return ", ".join(f"{variable} = {answer}" for answer in answers)


def problems_from_lines(lines):
    """
    Turn questions read off a worksheet into problems the app can set.

    Anything that is not a solvable equation in one unknown is dropped. A
    photographed sheet brings in headings, page numbers and half-read scribbles
    along with the questions, and a list with junk in it is worse than a
    shorter list: every entry here becomes something the student can tap.

    The prompt names the unknown the question actually uses, because a sheet in
    y should not open saying "Solve for x".
    """
    problems = []

    for line in lines:
        try:
            equation = parse_equation(line)
        except Exception:
            continue

        unknowns = sorted(equation.free_symbols, key=str)

        # One unknown only. Two means it is a formula to rearrange rather than
        # an equation to solve, and the checker has nothing useful to say.
        if len(unknowns) != 1:
            continue

        try:
            answers = solve(equation, unknowns[0])
        except Exception:
            continue

        # Nothing to solve towards, so nothing to mark against.
        if not answers:
            continue

        problems.append(
            {
                "index": len(problems),
                "prompt": f"Solve for {unknowns[0]}",
                "equation": line.strip(),
            }
        )

    return problems


def list_problems():
    """
    Every problem, for the sidebar. No answers: the iPad never needs them,
    and anything sent to the app can be read by the student.
    """
    return [
        {
            "index": index,
            "prompt": "Solve for x",
            "equation": equation_text,
        }
        for index, equation_text in enumerate(PROBLEMS)
    ]


def get_problem(index):
    """
    Return one problem, or None if the index is past the end of the list.
    """
    if index < 0 or index >= len(PROBLEMS):
        return None

    equation_text = PROBLEMS[index]

    return {
        "index": index,
        "total": len(PROBLEMS),
        "prompt": "Solve for x",
        "equation": equation_text,
        "answer": solve_for_answer(parse_equation(equation_text)),
    }
