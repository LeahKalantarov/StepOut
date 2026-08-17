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

import sympy

from checker.parser import parse_equation, parse_latex_equation
from checker.handwriting import (
    ALGEBRA_GRAMMAR,
    BALLOT_CROSSES,
    as_written,
    build_request_body,
    rows_stacked_in,
    undecorate,
    without_noise,
)
from checker.photo import solvable
from main import asking_for_help, is_an_equation, marked_as_a_question, steps_written_on
from checker.step_checker import (
    DOES_NOT_FOLLOW,
    EXTRA,
    NONE_LEFT,
    check_equations,
    check_page,
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


def check_page_with_problem(problem_text, steps):
    """
    Check a whole page, which may hold more than one go at the question.
    """
    equations = [parse_equation(step) for step in steps]
    return check_page(equations, steps, parse_equation(problem_text))


def test_second_attempt_is_the_one_that_counts():
    # Got it wrong, left the mess on the page, copied the question out again
    # and did it properly the second time. Read as one chain this is a page
    # with a mistake near the top; read as two attempts it is a solved page.
    result = check_page_with_problem(
        "2x + 5 = 13",
        ["2x + 5 = 13", "2x = 9", "2x + 5 = 13", "2x = 8", "x = 4"],
    )

    check("second attempt: page is solved", result["ok"] and result["solved"], result)
    check("second attempt: both runs seen", result["attempts"] == 2, result)
    check("second attempt: the later one is read", result["attempt_read"] == 2, result)


def test_a_restart_without_the_question_line_first():
    # The wrong first go was a single line, straight to an answer, with no
    # question written above it. Copying the question out to start again is
    # still what marks the fresh attempt, and the page is solved.
    result = check_page_with_problem("x + 4 = 11", ["x = 11", "x + 4 = 11", "x = 7"])

    check("restart: page is solved", result["ok"] and result["solved"], result)
    check("restart: answer read off", result["answer"] == "x = 7", result)
    check("restart: both runs seen", result["attempts"] == 2, result)
    check("restart: the later one is read", result["attempt_read"] == 2, result)


def test_solving_it_then_writing_on_does_not_undo_it():
    result = check_page_with_problem(
        "2x + 5 = 13",
        ["2x + 5 = 13", "2x = 8", "x = 4", "2x + 5 = 13", "2x = 3"],
    )

    check("wandering on: still solved", result["ok"] and result["solved"], result)


def test_two_bad_attempts_report_the_later_one():
    result = check_page_with_problem(
        "2x + 5 = 13",
        ["2x + 5 = 13", "2x = 9", "2x + 5 = 13", "2x = 7"],
    )

    check("two bad runs: still wrong", not result["ok"], result)
    # Counting the whole page, not the attempt: line 4 is "2x = 7".
    check("two bad runs: fault is in the later one", result["error_step"] == 4, result)


def test_one_attempt_behaves_as_before():
    # A page with a single run at the question must come back untouched by any
    # of this, including the keys it does not set.
    result = check_page_with_problem("2x + 5 = 13", ["2x + 5 = 13", "2x = 8", "x = 4"])

    check("one run: solved", result["ok"] and result["solved"], result)
    check("one run: not reported as attempts", "attempts" not in result, result)


def test_a_repeated_step_is_not_a_fresh_attempt():
    # 2x = 8 has the same solutions as the question and is the same equation
    # by the older rule, so a looser test for "they started again" would split
    # here and read the page as three attempts of one line each.
    result = check_page_with_problem("2x + 5 = 13", ["2x + 5 = 13", "2x = 8", "x = 4"])

    check("mid-solution step is not a restart", "attempts" not in result, result)


def test_recognized_latex_is_made_readable():
    # Everything past recognition is read by a person, so none of it should
    # ever carry a backslash. This exact line was shown to a student.
    written = as_written(r"\left( x - 3 \right) \left( x - 3 \right) = 0")

    check("readable: brackets close up", written == "(x - 3)(x - 3) = 0", written)

    cases = {
        r"2x + \frac{5}{2} = 13": "2x + 5/2 = 13",
        r"\frac{x+1}{2} = 4": "(x+1)/2 = 4",
        r"x ^{2} - 9 = 0": "x^2 - 9 = 0",
        r"2 \cdot x = 8": "2 * x = 8",
        r"x = 4 \sim": "x = 4",
    }

    for latex, expected in cases.items():
        got = as_written(latex)
        check(f"readable: {latex}", got == expected, got)


def test_a_power_keeps_its_braces_when_it_needs_them():
    # The stroke font raises a braced group, so x^{n+1} must survive intact.
    written = as_written(r"x ^{n+1} = 4")

    check("readable: braced power kept", written == "x^{n+1} = 4", written)


def test_a_stray_mark_over_the_line_is_not_a_variable():
    # A student wrote (x - 3)(x - 3) + 1 = 17, which is right, and was told it
    # was wrong three times running. A pen mark straying above the line came
    # back wrapped in \widearc, and SymPy — never having heard of \widearc —
    # read the name as a variable and multiplied the whole line by it.
    raw = r"\widearc{\left( x - 3 \right) \left( x - 3 \right)} + 1 = 17"

    equation = parse_latex_equation(undecorate(raw))
    result = check_page([equation], [as_written(undecorate(raw))], parse_equation("(x-3)^2+1=17"))

    check("stray mark: correct work stays correct", result["ok"], result)
    check(
        "stray mark: nothing invented",
        "widearc" not in str(equation),
        equation,
    )

    # The line the student is shown must not keep the braces either.
    check(
        "stray mark: reads as it was written",
        as_written(undecorate(raw)) == "(x - 3)(x - 3) + 1 = 17",
        as_written(undecorate(raw)),
    )


def test_decorations_come_off_whatever_they_wrap():
    cases = {
        r"\overline{2x} + 5 = 13": "2x + 5 = 13",
        r"\widehat{x} = 4": "x = 4",
        r"\widearc{\frac{x}{2}} = 3": r"\frac{x}{2} = 3",
        r"2x + 5 = 13": "2x + 5 = 13",
        # Never closed. Handing back the line untouched beats cutting it off
        # at a brace that was never there.
        r"\widearc{x = 4": r"\widearc{x = 4",
    }

    for latex, expected in cases.items():
        got = undecorate(latex)
        check(f"undecorated: {latex}", got == expected, got)


def test_foil_loops_do_not_cut_a_line_in_half():
    # A student expanding two brackets loops each term to the ones it
    # multiplies. Read as "and then", those loops cut (x - 3)(x - 3) = 16 into
    # a bracket and a stray "= 16", neither of which is an equation — so a page
    # covered in working came back holding none, and the student was told to
    # write a full line while looking at one.
    foil = r"\left( x - 3 \right) \left( x - 3 \right) \rightarrow \rightarrow = 16"
    steps = steps_written_on(foil)

    check("foil loops: read as one equation", len(steps) == 1, steps)

    # Compared by what it means rather than how it is built: SymPy writes
    # (x - 3)(x - 3) as (x - 3)**2, which is the same equation.
    read = parse_latex_equation(steps[0])
    expected = parse_equation("(x-3)*(x-3) = 16")

    check(
        "foil loops: the equation survives",
        sympy.simplify(read.lhs - read.rhs - (expected.lhs - expected.rhs)) == 0,
        read,
    )


def test_arrows_between_equations_still_separate_them():
    # The reason splitting exists at all: work written straight across the page.
    chained = r"2x + 5 = 13 \rightarrow 2x = 8 \rightarrow x = 4"
    steps = steps_written_on(chained)

    check("chained steps: all three found", len(steps) == 3, steps)

    for step in steps:
        check(f"chained steps: {step} is an equation", is_an_equation(step), step)


def test_a_stray_pen_mark_is_not_a_variable():
    # \sim is what a slip of the pen comes back as, and SymPy reads the name as
    # a variable and multiplies the line by it — the same way \widearc turned
    # correct work into a cross in the margin.
    check("noise: sim removed", without_noise(r"2x = 8 \sim") == "2x = 8")
    check("noise: real maths untouched", without_noise(r"\frac{x}{2} = 4") == r"\frac{x}{2} = 4")

    equation = parse_latex_equation(without_noise(r"2x = 8 \sim"))
    check("noise: nothing invented", "sim" not in str(equation), equation)


def test_algebra_is_read_against_a_narrow_alphabet():
    # "- 2 - 2" written under both sides came back as "+ 2 + z", and a jotting
    # came back as an emoji. Neither belongs on a page of school algebra, and
    # the reader only offered them because every letter was on the table.
    algebra = build_request_body([{"x": [0, 1], "y": [0, 1]}], "Math")
    grammar = algebra["configuration"]["math"].get("customGrammarContent", "")

    check("alphabet: algebra is narrowed", grammar == ALGEBRA_GRAMMAR, grammar[:40])

    # y is out along with the rest. A 4 written with an open top is a y, and the
    # reader was taking it as one, so a question written out again lower down
    # came back as a different equation and the fresh attempt went unnoticed.
    for stray in ("z", "w", "q", "y"):
        check(f"alphabet: no {stray}", f" {stray} " not in grammar, grammar)
    for needed in ("x", "=", "-", "7"):
        check(f"alphabet: keeps {needed}", f" {needed} " in grammar, grammar)

    # The solver must still be off, or we would be shown the tidy answer
    # instead of what the student actually wrote.
    check(
        "alphabet: solver still off",
        algebra["configuration"]["math"]["solver"]["enable"] is False,
        algebra["configuration"],
    )

    # Words keep the whole alphabet. A row is only read as words once it has
    # failed to be algebra, and that is where "I need help" gets written.
    words = build_request_body([{"x": [0, 1], "y": [0, 1]}], "Text")
    check(
        "alphabet: words stay wide",
        "customGrammarContent" not in words["configuration"]["math"],
        words["configuration"],
    )


def test_being_stuck_counts_as_asking():
    # Two question marks are a rule the student has to remember at exactly the
    # moment they are least able to. "I need help" written on a page is asking.
    for words in (
        "i need help",
        "ineed help",
        "i don't understand this",
        "im stuck",
        "what do i do now",
        "explain this",
    ):
        check(f"stuck: {words!r} is a request", asking_for_help(words), words)

    # And ordinary working never is.
    for words in ("-7", "x = 4", "2x + 5 = 13", "divide both sides by 2", ""):
        check(f"stuck: {words!r} is not a request", not asking_for_help(words), words)


def test_a_written_x_is_not_a_tick_box():
    # Asked for words rather than algebra, a lone handwritten x comes back as a
    # printed ballot cross, and "explain what x is??" reached the tutor as
    # "explain what ✗ is??" — a question about the one letter the whole page is
    # about, with that letter taken out of it.
    check("words: ballot cross reads as x", "explain what ✗ is??".translate(BALLOT_CROSSES) == "explain what x is??")

    # The multiplication sign really is meant when it turns up.
    check("words: times sign left alone", "2 × 3".translate(BALLOT_CROSSES) == "2 × 3")


def test_losing_a_root_is_not_described_as_fewer_answers():
    # "has fewer answers" reads as being about the answers the student wrote
    # down, and a student who has written none finds the sentence meaningless.
    result = check_with_problem("x^2 - 9 = 0", ["(x - 3)(x - 3) = 0"])

    check("lost root: called wrong", not result["ok"], result)
    check(
        "lost root: phrased about solutions",
        result.get("message") == "(x - 3)(x - 3) = 0 doesn't keep every solution of the question.",
        result.get("message"),
    )


def test_a_number_before_a_word_keeps_its_space():
    # The tutor's own sentences go through the same tidying as the recognizer's
    # output, and "divide 40 by 8" arriving as "divide 40by 8" is written onto
    # the page exactly like that for the student to puzzle over.
    check("prose: 40 by", as_written("divide 40 by 8") == "divide 40 by 8")
    check("prose: 2 more", as_written("take 2 more off") == "take 2 more off")
    check("prose: 3 times", as_written("3 times x") == "3 times x")

    # And the reason the rule is there in the first place still holds: MyScript
    # reports one symbol at a time, so a variable arrives adrift of its number.
    check("maths: 2 x", as_written("2 x + 5 = 1 3") == "2x + 5 = 13")
    check("maths: 4 y", as_written("4 y = 8") == "4y = 8")


def test_the_answer_says_which_line_it_was_on():
    # The tick and the ring have to land on the answer. The iPad's only other
    # guess is the last line written, and by the time a page is checked the
    # last line is as often a jotting in the margin, or the "yes" that asked
    # for help, as it is the answer.
    question = parse_equation("2*x + 5 = 13")
    steps = ["2*x = 8", "x = 4"]
    result = check_page([parse_equation(step) for step in steps], steps, question)
    check("answer line: the second of two", result.get("answer_steps") == [2])

    # Both roots of a quadratic are answers, and both get marked.
    question = parse_equation("x**2 = 9")
    steps = ["x**2 = 9", "x = 3", "x = -3"]
    result = check_page([parse_equation(step) for step in steps], steps, question)
    check("answer line: both roots", result.get("answer_steps") == [2, 3])

    # Started again half way down. The answer is on the page's fifth line, not
    # the second line of the attempt it belongs to.
    question = parse_equation("2*x + 5 = 13")
    steps = ["2*x = 9", "x = 5", "2*x + 5 = 13", "2*x = 8", "x = 4"]
    result = check_page([parse_equation(step) for step in steps], steps, question)
    check("answer line: counted down the whole page", result.get("answer_steps") == [5])


def test_a_restart_written_under_its_own_jotting():
    # The question written out again to start afresh, with "- 4  - 4" tucked
    # under it the way anybody would. Close enough together, MyScript hands the
    # pair back as a matrix rather than as two lines.
    stacked = "\\begin{matrix} x ^{2} + 4 = 20 \\\\ - 4 - 4 \\end{matrix}"

    check(
        "stacked: taken apart",
        rows_stacked_in(stacked) == ["x ^{2} + 4 = 20", "- 4 - 4"],
        rows_stacked_in(stacked),
    )

    # Left whole it is neither an equation nor an annotation, so the restated
    # question restates nothing, the fresh attempt never opens, and the page
    # goes on being marked against the mistake at the top of it.
    steps = [as_written(step) for step in steps_written_on(stacked)]
    check("stacked: the question is back", "x^2 + 4 = 20" in steps, steps)

    # An ordinary line is not a stack and must come through untouched.
    check("stacked: plain line kept", rows_stacked_in("x = 4") == ["x = 4"])

    # The whole page it came off, marked the way the app marks it.
    question = parse_equation("x**2 + 4 = 20")
    rows = [
        "+ 4 + 4",
        "x ^{2} = 24",
        stacked,
        "x ^{2} = 16",
        "x = 4",
        "x = - 4",
    ]

    equations = []
    written = []

    for row in rows:
        for step in steps_written_on(row):
            try:
                equation = parse_latex_equation(step)
            except Exception:
                continue

            equations.append(equation)
            written.append(as_written(step))

    result = check_page(equations, written, question)

    check("stacked page: solved", result["ok"] and result["solved"], result)
    check("stacked page: both runs seen", result["attempts"] == 2, result)
    check("stacked page: the later one is read", result["attempt_read"] == 2, result)


def test_a_photo_question_has_to_be_solvable():
    # Nothing goes onto the student's page unless we could mark it. A model
    # reading a blurred worksheet will hand back headings and fragments along
    # with the questions, and a question that cannot be checked is worse than
    # one never offered — the student works faithfully and is marked on it.
    check("photo keeps: linear", solvable("2x + 5 = 13"))
    check("photo keeps: quadratic", solvable("x**2 - 9 = 0"))
    check("photo keeps: caret power", solvable("x^2 - 9 = 0"))

    check("photo drops: a heading", not solvable("Solve for x"))
    check("photo drops: no unknown", not solvable("3 + 4 = 7"))
    check("photo drops: two unknowns", not solvable("x + y = 4"))
    check("photo drops: nothing at all", not solvable(""))

    # Asked to teach the discriminant, a model sets one with a negative one to
    # show what that looks like. The honest answer is "no real solutions",
    # which is a sentence rather than a line of algebra — there is nothing the
    # student could write down that this app would mark as finishing it.
    check("photo drops: no real answer", not solvable("2x**2 + x + 7 = 0"))
    check("photo keeps: irrational roots", solvable("x**2 + 4x + 1 = 0"))


def test_a_question_has_to_be_marked_as_one():
    """
    Only the rows no algebra was found in ever reach this, which is exactly
    where a reader's guesses end up. One question mark is what it returns for a
    mark it could not read, so it takes two to mean the student meant it.
    """
    check("asked: two question marks", marked_as_a_question("why do we flip it ??"))
    check("asked: spaced apart", marked_as_a_question("why do we flip it ? ?"))
    check("asked: a star in front", marked_as_a_question("* why do we flip it"))

    check("not asked: one question mark", not marked_as_a_question("2x + 5?"))
    check("not asked: unreadable scrawl", not marked_as_a_question("?"))
    check("not asked: ordinary working", not marked_as_a_question("-5 both sides"))
    check("not asked: nothing at all", not marked_as_a_question(""))


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
    test_second_attempt_is_the_one_that_counts()
    test_a_restart_without_the_question_line_first()
    test_solving_it_then_writing_on_does_not_undo_it()
    test_two_bad_attempts_report_the_later_one()
    test_one_attempt_behaves_as_before()
    test_a_repeated_step_is_not_a_fresh_attempt()
    test_recognized_latex_is_made_readable()
    test_a_power_keeps_its_braces_when_it_needs_them()
    test_a_stray_mark_over_the_line_is_not_a_variable()
    test_decorations_come_off_whatever_they_wrap()
    test_foil_loops_do_not_cut_a_line_in_half()
    test_arrows_between_equations_still_separate_them()
    test_a_stray_pen_mark_is_not_a_variable()
    test_algebra_is_read_against_a_narrow_alphabet()
    test_being_stuck_counts_as_asking()
    test_a_written_x_is_not_a_tick_box()
    test_losing_a_root_is_not_described_as_fewer_answers()
    test_a_number_before_a_word_keeps_its_space()
    test_the_answer_says_which_line_it_was_on()
    test_a_restart_written_under_its_own_jotting()
    test_a_photo_question_has_to_be_solvable()
    test_a_question_has_to_be_marked_as_one()

    print()
    print(f"{passed} passed, {failed} failed")

    if failed > 0:
        raise SystemExit(1)
