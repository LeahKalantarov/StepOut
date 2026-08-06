"""
Turn a failed step into something a student can actually use.

The checker only knows whether two equations are equivalent. This layer tries
to say *why* they are not — wrong final answer, wrong divisor, one-sided
division, or something we cannot classify.
"""

from sympy import Rational, simplify, solve


def is_solved(equation):
    sides = [(equation.lhs, equation.rhs), (equation.rhs, equation.lhs)]

    for variable_side, number_side in sides:
        if variable_side.is_Symbol and len(number_side.free_symbols) == 0:
            return True

    return False


def _main_variable(equation):
    syms = list(equation.free_symbols)
    if len(syms) != 1:
        return None
    return syms[0]


def _expected_solution(previous_equation):
    variable = _main_variable(previous_equation)
    if variable is None:
        return None

    solutions = solve(previous_equation, variable)
    if len(solutions) != 1:
        return None

    return simplify(solutions[0])


def _student_answer(current_equation):
    if not is_solved(current_equation):
        return None

    for variable_side, number_side in [
        (current_equation.lhs, current_equation.rhs),
        (current_equation.rhs, current_equation.lhs),
    ]:
        if variable_side.is_Symbol and len(number_side.free_symbols) == 0:
            return simplify(number_side)

    return None


def _looks_like_divided_left_only(previous_equation, current_equation):
    """
    Catch steps like 3x = 18  ->  x/3 = 6 where only x was divided, not both sides.
    """
    variable = _main_variable(previous_equation)
    if variable is None:
        return False

    lhs = simplify(current_equation.lhs)
    rhs = simplify(current_equation.rhs)

    # x/3 on the left while the right stayed a plain number is the usual slip.
    if lhs.is_Mul or lhs.is_Pow:
        divided_lhs = simplify(lhs - variable)
        if variable in lhs.free_symbols and lhs != variable:
            if len(rhs.free_symbols) == 0:
                return True

    return False


def _plausible_divisor(value):
    """True when a value looks like someone divided by a small whole number."""
    try:
        number = float(Rational(value).limit_denominator(60))
    except (TypeError, ValueError):
        return False

    if number <= 1 or number > 12:
        return False

    return abs(number - round(number)) < 1e-9


def _divisor_hint(previous_equation, student_answer):
    """
    When the student reached x = n but n is wrong, infer what they may have
    divided by and compare it to the coefficient on the variable.
    """
    variable = _main_variable(previous_equation)
    expected = _expected_solution(previous_equation)
    if variable is None or expected is None or student_answer is None:
        return None

    lhs = simplify(previous_equation.lhs)
    rhs = simplify(previous_equation.rhs)

    # ax = b  ->  the divisor you want is a
    if lhs.is_Mul and variable in lhs.free_symbols:
        terms = lhs.as_coeff_mul(variable)[0], lhs.as_coeff_mul(variable)[1]
        coefficient = simplify(lhs / variable)
        if len(coefficient.free_symbols) == 0 and coefficient != 0:
            try:
                guessed_divisor = simplify(rhs / student_answer)
            except Exception:
                return None

            if len(guessed_divisor.free_symbols) == 0 and guessed_divisor != coefficient:
                if _plausible_divisor(guessed_divisor):
                    return {
                        "expected_divisor": coefficient,
                        "guessed_divisor": guessed_divisor,
                    }

    return None


def diagnose_step(previous_equation, current_equation, previous_label, current_label):
    """
    Return extra detail when a step does not follow.

    Keys: reason, message, expected_answer, student_answer, help
    """
    expected = _expected_solution(previous_equation)
    student = _student_answer(current_equation)

    if _looks_like_divided_left_only(previous_equation, current_equation):
        return {
            "reason": "divided_one_side",
            "message": (
                f"{current_label} doesn't follow from {previous_label}. "
                "It looks like you divided the x side only — divide both sides by the same number."
            ),
            "help": {
                "wrong_line": current_label,
                "previous_line": previous_label,
                "reason": "divided_one_side",
            },
        }

    if expected is not None and student is not None and simplify(student - expected) != 0:
        variable = _main_variable(previous_equation)
        var_name = str(variable)

        divisor = _divisor_hint(previous_equation, student)
        if divisor:
            expected_div = divisor["expected_divisor"]
            guessed_div = divisor["guessed_divisor"]
            return {
                "reason": "wrong_divisor",
                "message": (
                    f"You wrote {current_label}, but {previous_label} gives {var_name} = {expected}. "
                    f"It looks like you divided by {guessed_div}, not by {expected_div}."
                ),
                "expected_answer": f"{var_name} = {expected}",
                "student_answer": current_label,
                "help": {
                    "wrong_line": current_label,
                    "previous_line": previous_label,
                    "reason": "wrong_divisor",
                    "expected_divisor": str(expected_div),
                    "guessed_divisor": str(guessed_div),
                },
            }

        return {
            "reason": "wrong_answer",
            "message": (
                f"You wrote {current_label}, but {previous_label} gives {var_name} = {expected}. "
                "Your steps might be right with a wrong final number — or we may have misread your handwriting."
            ),
            "expected_answer": f"{var_name} = {expected}",
            "student_answer": current_label,
            "help": {
                "wrong_line": current_label,
                "previous_line": previous_label,
                "reason": "wrong_answer",
                "expected_answer": f"{var_name} = {expected}",
            },
        }

    return {
        "reason": "does_not_follow",
        "message": f"{current_label} doesn't follow from {previous_label}.",
        "help": {
            "wrong_line": current_label,
            "previous_line": previous_label,
            "reason": "does_not_follow",
        },
    }
