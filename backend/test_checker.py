"""
Checks the step checker against work a student might really write.

Run it with:  python test_checker.py

Linear equations are what the app is mostly used for, so they are covered first
and in detail: the solution-set rewrite must not have moved any of it. After
that come the quadratics the rewrite was for, and then the awkward lines — an
identity, a contradiction, two unknowns, a polynomial solve() struggles with —
which are here to prove the checker answers something sensible instead of
hanging or raising inside a web request.

Every case prints PASS or FAIL, and the script exits non-zero if anything
failed, so it can be trusted without reading the output.
"""

import time

from checker.parser import parse_equation
from checker.problems import PROBLEMS, get_problem, solve_for_answer
from checker.step_checker import (
    DOES_NOT_FOLLOW,
    EXTRA,
    NONE_LEFT,
    check_equations,
    check_steps,
)

passed = 0
failed = 0


def check(title, condition, detail=None):
    """
    Record one expectation and say whether it held.
    """
    global passed, failed

    if condition:
        passed += 1
        print(f"PASS  {title}")
    else:
        failed += 1
        print(f"FAIL  {title}")
        if detail is not None:
            print(f"      got: {detail}")


def check_with_problem(problem_text, steps):
    """
    Check typed steps as if the student had been given a problem to copy from.
    """
    equations = [parse_equation(step) for step in steps]
    return check_equations(equations, steps, parse_equation(problem_text))


def test_linear_correct():
    result = check_steps(["2x + 5 = 13", "2x = 8", "x = 4"])

    check("linear: every step holds up", result["ok"], result)
    check("linear: reported as solved", result["solved"] is True, result)
    check("linear: answer is the finished line", result.get("answer") == "x = 4", result)
    check("linear: one answer expected and found", result["answers_expected"] == 1, result)
    check("linear: not partly solved", result["partly_solved"] is False, result)
    check("linear: no wasted lines", "extra_steps" not in result, result)


def test_linear_answer_written_backwards():
    result = check_steps(["3x = 21", "7 = x"])

    check("linear: '7 = x' counts as solved", result["solved"] is True, result)


def test_linear_with_a_fraction():
    result = check_steps(["x/2 + 3 = 7", "x/2 = 4", "x = 8"])

    check("linear: fraction solved", result["solved"] is True, result)


def test_linear_variable_on_both_sides():
    result = check_steps(["5x + 2 = 3x + 12", "2x = 10", "x = 5"])

    check("linear: variable on both sides solved", result["solved"] is True, result)


def test_linear_wrong_last_step():
    result = check_steps(["2x + 5 = 13", "2x = 8", "x = 5"])

    check("wrong step: flagged", result["ok"] is False, result)
    check("wrong step: points at line 3", result.get("error_step") == 3, result)
    check(
        "wrong step: keeps the old message",
        result.get("message") == "x = 5 doesn't follow from 2x = 8",
        result,
    )
    check("wrong step: reason is a gained solution", result.get("reason") == EXTRA, result)


def test_linear_wrong_middle_step():
    result = check_steps(["4x - 7 = 5", "4x = 11", "x = 11/4"])

    check("wrong middle step: points at line 2", result.get("error_step") == 2, result)


def test_extra_steps_after_the_answer():
    result = check_steps(["2x + 5 = 13", "2x = 8", "x = 4", "x = 4"])

    check("extra steps: still correct", result["ok"], result)
    check("extra steps: still solved", result["solved"] is True, result)
    check("extra steps: wasted work noticed", result.get("extra_steps") is True, result)


def test_first_line_miscopied():
    result = check_with_problem("2x + 5 = 13", ["2x + 5 = 14", "2x = 9"])

    check("miscopied question: flagged", result["ok"] is False, result)
    check("miscopied question: points at line 1", result.get("error_step") == 1, result)
    check(
        "miscopied question: keeps the old message",
        result.get("message") == "2x + 5 = 14 doesn't follow from the question.",
        result,
    )


def test_first_line_copied_properly():
    result = check_with_problem("2x + 5 = 13", ["2x = 8", "x = 4"])

    check("question copied properly: solved", result["solved"] is True, result)


def test_quadratic_one_root_is_incomplete_not_wrong():
    steps = ["x^2 - 9 = 0", "(x - 3)(x + 3) = 0", "x = 3"]
    result = check_steps(steps)

    check("factoring: no step is flagged", result["ok"], result)
    check("factoring: one root is not solved", result["solved"] is False, result)
    check("factoring: reported as partly solved", result["partly_solved"] is True, result)
    check("factoring: found one answer", result["answers_found"] == 1, result)
    check("factoring: two answers expected", result["answers_expected"] == 2, result)
    check("factoring: says how many are left", "message" in result, result)
    check("factoring: nothing called a mistake", "reason" not in result, result)


def test_quadratic_both_roots():
    steps = ["x^2 - 9 = 0", "(x - 3)(x + 3) = 0", "x = 3", "x = -3"]
    result = check_steps(steps)

    check("both roots: no step is flagged", result["ok"], result)
    check("both roots: solved", result["solved"] is True, result)
    check("both roots: both listed as the answer", result.get("answer") == "x = 3, x = -3", result)
    check("both roots: found two answers", result["answers_found"] == 2, result)
    check("both roots: second root is not wasted work", "extra_steps" not in result, result)


def test_quadratic_second_root_written_first():
    result = check_steps(["x^2 = 25", "x = -5", "x = 5"])

    check("roots in either order: solved", result["solved"] is True, result)


def test_quadratic_root_repeated():
    result = check_steps(["x^2 - 9 = 0", "x = 3", "x = 3"])

    check("repeated root: still partly solved", result["partly_solved"] is True, result)
    check("repeated root: counted once", result["answers_found"] == 1, result)
    check("repeated root: wasted work noticed", result.get("extra_steps") is True, result)


def test_quadratic_one_branch_from_the_question():
    result = check_with_problem("x^2 - 9 = 0", ["x - 3 = 0", "x = 3"])

    check("one branch of the question: not flagged", result["ok"], result)
    check("one branch of the question: partly solved", result["partly_solved"] is True, result)
    check("one branch of the question: two answers expected", result["answers_expected"] == 2, result)


def test_squaring_both_sides_invents_a_solution():
    result = check_steps(["x - 1 = 2", "(x - 1)^2 = 4"])

    check("squaring both sides: flagged", result["ok"] is False, result)
    check("squaring both sides: points at line 2", result.get("error_step") == 2, result)
    check("squaring both sides: reason is a gained solution", result.get("reason") == EXTRA, result)


def test_multiplying_by_the_variable_invents_a_solution():
    result = check_steps(["x = 3", "x^2 = 3x"])

    check("multiplying by x: flagged", result["ok"] is False, result)
    check("multiplying by x: reason is a gained solution", result.get("reason") == EXTRA, result)


def test_losing_every_solution():
    result = check_steps(["2x = 8", "0 = 1"])

    check("no solutions left: flagged", result["ok"] is False, result)
    check("no solutions left: reason says so", result.get("reason") == NONE_LEFT, result)


def test_identity():
    result = check_steps(["x = x", "0 = 0"])

    check("identity: not flagged", result["ok"], result)
    check("identity: not solved", result["solved"] is False, result)


def test_identity_then_a_value():
    result = check_steps(["0 = 0", "x = 3"])

    check("identity then a value: not flagged", result["ok"], result)
    check("identity then a value: not solved", result["solved"] is False, result)
    check("identity then a value: partly solved", result["partly_solved"] is True, result)
    check(
        "identity then a value: cannot count the answers",
        result["answers_expected"] is None,
        result,
    )


def test_contradiction():
    result = check_steps(["0 = 1", "0 = 1"])

    check("contradiction: not flagged", result["ok"], result)
    check("contradiction: not solved", result["solved"] is False, result)


def test_contradiction_then_a_solution():
    result = check_steps(["0 = 1", "x = 3"])

    check("contradiction then a value: flagged", result["ok"] is False, result)
    check(
        "contradiction then a value: reason is a gained solution",
        result.get("reason") == EXTRA,
        result,
    )


def test_two_unknowns():
    result = check_steps(["2x + y = 5", "y = 5 - 2x"])

    check("two unknowns: rearranging is allowed", result["ok"], result)
    check("two unknowns: no answer claimed", result["solved"] is False, result)


def test_two_unknowns_wrong():
    result = check_steps(["2x + y = 5", "y = 5 + 2x"])

    check("two unknowns: sign slip flagged", result["ok"] is False, result)
    check("two unknowns: points at line 2", result.get("error_step") == 2, result)
    check(
        "two unknowns: reason is the older rule",
        result.get("reason") == DOES_NOT_FOLLOW,
        result,
    )


def test_something_solve_struggles_with():
    # A fifth-degree polynomial has no formula for its roots, so solve() answers
    # with placeholder root objects, and a tenth-degree one is worse. Neither
    # should hold up the request or raise.
    hard_cases = [
        ["x^5 - x + 1 = 0", "x^5 = x - 1"],
        ["x^10 - 3x^7 + x^2 - 1 = 0", "x^10 - 3x^7 + x^2 = 1"],
    ]

    for steps in hard_cases:
        started = time.time()
        result = check_steps(steps)
        seconds = time.time() - started

        check(f"hard polynomial: rearranging allowed ({steps[0]})", result["ok"], result)
        check(f"hard polynomial: answered in good time ({seconds:.1f}s)", seconds < 10, result)


def test_every_problem_has_an_answer():
    for index, equation_text in enumerate(PROBLEMS):
        problem = get_problem(index)
        answer = problem["answer"]

        check(
            f"problem {index} ({equation_text}) has an answer",
            answer != "no answer" and len(answer) > 0,
            answer,
        )


def test_answer_key_lists_both_roots():
    answer = solve_for_answer(parse_equation("x^2 - 9 = 0"))

    check("answer key: both roots listed", answer == "x = -3, x = 3", answer)


if __name__ == "__main__":
    test_linear_correct()
    test_linear_answer_written_backwards()
    test_linear_with_a_fraction()
    test_linear_variable_on_both_sides()
    test_linear_wrong_last_step()
    test_linear_wrong_middle_step()
    test_extra_steps_after_the_answer()
    test_first_line_miscopied()
    test_first_line_copied_properly()
    test_quadratic_one_root_is_incomplete_not_wrong()
    test_quadratic_both_roots()
    test_quadratic_second_root_written_first()
    test_quadratic_root_repeated()
    test_quadratic_one_branch_from_the_question()
    test_squaring_both_sides_invents_a_solution()
    test_multiplying_by_the_variable_invents_a_solution()
    test_losing_every_solution()
    test_identity()
    test_identity_then_a_value()
    test_contradiction()
    test_contradiction_then_a_solution()
    test_two_unknowns()
    test_two_unknowns_wrong()
    test_something_solve_struggles_with()
    test_every_problem_has_an_answer()
    test_answer_key_lists_both_roots()

    print()
    print(f"{passed} passed, {failed} failed")

    if failed > 0:
        raise SystemExit(1)
