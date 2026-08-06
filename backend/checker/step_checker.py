from sympy import cancel, simplify

from checker.diagnosis import diagnose_step
from checker.parser import parse_equation


def move_everything_to_one_side(equation):
    """
    Rewrite an equation as one expression equal to zero.

    Example: 2x + 5 = 13  ->  2x + 5 - 13  ->  2x - 8
    """
    return simplify(equation.lhs - equation.rhs)


def same_equation(equation_a, equation_b):
    """
    Two steps are valid if they represent the same equation.

    We compare the "everything on one side" form of each line.
    For linear equations, that means one side is a nonzero multiple of the other.
    """
    side_a = move_everything_to_one_side(equation_a)
    side_b = move_everything_to_one_side(equation_b)

    if side_a == side_b:
        return True

    if side_a == 0 or side_b == 0:
        return side_a == side_b

    # Example: (2x - 8) and (x - 4) are the same equation because x - 4 = (1/2)(2x - 8).
    # If dividing one by the other leaves a plain number, they match.
    ratio = cancel(side_b / side_a)
    return len(ratio.free_symbols) == 0


def is_solved(equation):
    """
    True when a step is a finished answer, like "x = 4".

    That means one side is a lone variable and the other is just a number.
    We accept either order, since "4 = x" is equally solved.
    """
    sides = [(equation.lhs, equation.rhs), (equation.rhs, equation.lhs)]

    for variable_side, number_side in sides:
        if variable_side.is_Symbol and len(number_side.free_symbols) == 0:
            return True

    return False


def check_equations(equations, labels):
    """
    Compare each equation to the one above it and report the first bad line.

    'equations' are SymPy objects. 'labels' are what to call each line in the
    error message — the typed text, or the handwriting we recognized.

    Returns a dict like:
      {"ok": True, "solved": True, "answer": "x = 4"}
    or
      {"ok": False, "error_step": 3, "message": "x = 5 doesn't follow from 2x = 8"}
    """
    # Step 1 is the starting equation, so we start comparing at step 2
    for i in range(1, len(equations)):
        previous_equation = equations[i - 1]
        current_equation = equations[i]

        if not same_equation(previous_equation, current_equation):
            detail = diagnose_step(
                previous_equation,
                current_equation,
                labels[i - 1],
                labels[i],
            )
            return {
                "ok": False,
                "error_step": i + 1,
                "message": detail["message"],
                "reason": detail.get("reason"),
                "expected_answer": detail.get("expected_answer"),
                "student_answer": detail.get("student_answer"),
                "help": detail.get("help"),
            }

    # Every step holds up. Has the student actually reached an answer yet?
    solved_at = None
    for i, equation in enumerate(equations):
        if is_solved(equation):
            solved_at = i
            break

    if solved_at is None:
        return {"ok": True, "solved": False}

    result = {"ok": True, "solved": True, "answer": labels[solved_at]}

    # Writing more lines after the answer isn't wrong, but it is wasted work,
    # so say so rather than staying silent.
    if solved_at < len(equations) - 1:
        result["extra_steps"] = True

    return result


def check_steps(steps):
    """
    Check a list of typed steps like ["2x + 5 = 13", "2x = 8"].
    """
    if len(steps) == 0:
        return {"ok": True}

    equations = [parse_equation(step) for step in steps]
    return check_equations(equations, steps)
