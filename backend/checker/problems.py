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
