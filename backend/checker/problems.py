"""
The problems StepOut asks the student to solve.

We only store the equation. The answer is worked out with SymPy when asked,
so a problem can never disagree with its own answer key.
"""

from sympy import solve

from checker.parser import parse_equation

# Roughly easiest to hardest. The answers are deliberately all different, so
# a passing check can't be a coincidence while testing.
PROBLEMS = [
    "3x = 21",
    "2x + 5 = 13",
    "4x - 7 = 5",
    "x/2 + 3 = 7",
    "5x + 2 = 3x + 12",
    "6 - 2x = 10",
]


def solve_for_answer(equation):
    """
    Work out the answer to an equation, as a string like "x = 4".
    """
    variable = sorted(equation.free_symbols, key=str)[0]
    answers = solve(equation, variable)
    return f"{variable} = {answers[0]}"


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
