"""
Decides whether each line of a student's working follows from the line above.

The question this file answers is about solution sets, not about whether two
lines look alike: two lines agree when the same values of the variable make
both of them true.

An earlier version compared the equations themselves for equivalence. That is
exactly right while a student does the same thing to both sides of a linear
equation, and it goes wrong the moment they factor. Given x^2 - 9 = 0,
factoring to (x-3)(x+3) = 0 and then writing x = 3 is a real step, but x = 3 is
not the same equation — it has one solution where the line above has two. The
old rule called that a mistake, and because the verdict is handed on to a
language model that treats it as fact, the student was told off for something
they had not done. Reasoning about solutions lets us say the true thing
instead: you have found one of the two answers.
"""

import threading

from sympy import cancel, degree, simplify, solve

from checker.parser import parse_equation

# How long SymPy gets to work on one line before we give up on it. solve() and
# simplify() can take a very long time on an awkward equation, and this runs
# inside a web request that a student is sitting waiting on, so an answer we
# cannot get quickly is treated the same as one we cannot get at all.
TIME_LIMIT_SECONDS = 2

# What we know about the values that make one line true.
EVERY_VALUE = "every value"  # true whatever the variable is, like x = x
NO_VALUE = "no value"  # true for nothing at all, like 0 = 1
LISTED_VALUES = "listed values"  # a definite list of values, like [-3, 3]
CANNOT_TELL = "cannot tell"  # we could not work it out

# How one line stands next to the solutions it is supposed to have. These
# strings travel to the app in the "reason" key of a failed check, so they are
# written to be read by a person.
SAME = "same solutions"
FEWER = "keeps only some of the solutions"
EXTRA = "introduces a solution"
NONE_LEFT = "loses every solution"
LOST = "drops an answer while rewriting the equation"
DOES_NOT_FOLLOW = "is not the same equation"

# The verdicts that mean the student has actually made a mistake. FEWER is
# absent on purpose: dropping solutions is unfinished work, not an error.
MISTAKES = (EXTRA, NONE_LEFT, LOST, DOES_NOT_FOLLOW)


class SolutionSet:
    """
    The values of the variable that make one line true.

    'kind' is one of the four above, and 'values' is only filled in for
    LISTED_VALUES. EVERY_VALUE and NO_VALUE have to be kinds of their own
    because sympy.solve() answers [] for both an identity like x = x and a
    contradiction like 0 = 1, and those two are opposites: everything satisfies
    the first and nothing satisfies the second. An empty list on its own cannot
    tell them apart, so we never let one reach the comparison.
    """

    def __init__(self, kind, values=None):
        self.kind = kind
        self.values = values if values is not None else []


def with_time_limit(work):
    """
    Run work() and give up on it if it takes too long, answering None.

    None means "we do not know", never "the answer is no". The caller has to
    decide what to do without SymPy's help. Anything work() raises is treated
    the same way, since a failure and a timeout leave us equally ignorant.

    A running thread cannot be stopped from outside in Python, so a runaway
    simplify() carries on in the background after we have walked away from it.
    It is a daemon thread, so it cannot hold the server open, and it finishes
    on its own eventually. Letting it burn a little CPU is much better than
    making the student wait, or than guessing at a verdict.
    """
    outcome = {}

    def run():
        try:
            outcome["value"] = work()
        except Exception:
            pass

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(TIME_LIMIT_SECONDS)

    return outcome.get("value")


def move_everything_to_one_side(equation):
    """
    Rewrite an equation as one expression equal to zero.

    Example: 2x + 5 = 13  ->  2x + 5 - 13  ->  2x - 8
    """
    return simplify(equation.lhs - equation.rhs)


def work_out_solutions(equation):
    """
    Which values of the variable make this line true.

    Two cases are settled before solve() is called at all, because solve()
    answers [] for both of them. With everything moved to one side, a line that
    is always true has simplified to 0 and a line that is never true to some
    other plain number, so here the two are easy to tell apart, and after
    solve() they are impossible to tell apart.

    Can be slow, and can raise. Call solutions_of() instead.
    """
    difference = move_everything_to_one_side(equation)

    if difference == 0:
        return SolutionSet(EVERY_VALUE)

    if len(difference.free_symbols) == 0:
        return SolutionSet(NO_VALUE)

    # Two unknowns describe a whole line of the graph rather than a point, so
    # there is no list of values to compare. The older equation-equivalence
    # rule handles those perfectly well, so we say we don't know and let the
    # caller fall back to it rather than guessing.
    if len(difference.free_symbols) > 1:
        return SolutionSet(CANNOT_TELL)

    variable = list(difference.free_symbols)[0]
    values = solve(difference, variable)

    # solve() sometimes hands back a solution with a symbol still in it when it
    # could not finish the job. There is no way to compare that against another
    # line's solutions, and half a list would be worse than none, so we drop
    # the whole answer.
    for value in values:
        if len(value.free_symbols) > 0:
            return SolutionSet(CANNOT_TELL)

    return SolutionSet(LISTED_VALUES, values)


def solutions_of(equation):
    """
    work_out_solutions(), but it always answers instead of hanging or raising.
    """
    found = with_time_limit(lambda: work_out_solutions(equation))

    if found is None:
        return SolutionSet(CANNOT_TELL)

    return found


def same_value(first, second):
    """
    Whether two solutions are the same number.

    One number can be written more than one way — solve() may hand back sqrt(8)
    where the student wrote 2*sqrt(2) — so == is not enough on its own.
    simplify() settles nearly everything. .equals() is a slower second opinion
    that we only pay for once simplify() has said no, because calling a correct
    step wrong is the one outcome worth spending time to avoid.
    """
    try:
        if simplify(first - second) == 0:
            return True

        return first.equals(second) is True
    except Exception:
        return False


def is_one_of(values, value):
    """
    Whether 'value' is already somewhere in 'values'.
    """
    for other in values:
        if same_value(other, value):
            return True

    return False


def compare_solutions(expected, step):
    """
    How the solutions of one line stand against the solutions it should have.

    The rules in full:

      - Either set is unknown: CANNOT_TELL, and the caller falls back to the
        older equation-equivalence rule.
      - The two sets match: SAME. An ordinary correct step, and what every line
        of a linear solution does.
      - The step keeps some solutions and drops the rest: FEWER. Not a mistake.
        This is what factoring and then taking one root looks like, and the
        student is owed "you have one of the two", not "this is wrong".
      - The step is true for a value that was not a solution before: EXTRA, a
        real mistake. Squaring both sides, or multiplying by something that can
        be zero, both invent solutions this way.
      - The step has no solutions where there were some: NONE_LEFT, a mistake.

    A step that both drops a solution and gains one — x = 5 under a line that
    says x = 4 — counts as EXTRA. Gaining a solution is the more serious of the
    two, and that student needs to hear that the line is wrong rather than that
    it is merely incomplete.

    Can be slow. Call it through with_time_limit().
    """
    if expected.kind == CANNOT_TELL or step.kind == CANNOT_TELL:
        return CANNOT_TELL

    if expected.kind == EVERY_VALUE and step.kind == EVERY_VALUE:
        return SAME

    if expected.kind == NO_VALUE and step.kind == NO_VALUE:
        return SAME

    if step.kind == NO_VALUE:
        return NONE_LEFT

    if expected.kind == NO_VALUE:
        # Nothing at all satisfied what came before, so whatever satisfies this
        # line is something the student has brought into being.
        return EXTRA

    if step.kind == EVERY_VALUE:
        # What came before was true for particular values; this line is true for
        # all of them, so it has picked up solutions on the way.
        return EXTRA

    if expected.kind == EVERY_VALUE:
        # Narrowing an always-true line down to particular values invents
        # nothing, so it is unfinished rather than wrong. Nobody solves algebra
        # this way, but a stray "x = x" puts us here, and that is no reason to
        # accuse the student of anything.
        return FEWER

    for value in step.values:
        if not is_one_of(expected.values, value):
            return EXTRA

    for value in expected.values:
        if not is_one_of(step.values, value):
            return FEWER

    return SAME


def same_equation(equation_a, equation_b):
    """
    Two steps are valid if they represent the same equation.

    This is the older and narrower rule. It is kept for the lines whose
    solutions we could not work out — two unknowns, or something solve() choked
    on — where it is the best we have. It is exactly right for a linear
    equation, where the student does the same thing to both sides and nothing
    is gained or lost.

    We compare the "everything on one side" form of each line. For linear
    equations, that means one side is a nonzero multiple of the other.

    Can be slow. Call it through with_time_limit().
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


def is_case_branch(equation):
    """
    Whether this line reads as taking one case, rather than as rewriting the
    whole equation.

    This is what separates the two ways of ending up with fewer solutions than
    you started with, which otherwise look identical to the checker.

        (x-3)(x+3) = 0  ->  x - 3 = 0        one case of two. Fine.
        x^2 - 9 = 0     ->  (x-3)(x-3) = 0   a botched factorisation. Not fine.

    Both narrow two answers down to one, and neither states anything false, so
    nothing about the solutions alone can tell them apart. What differs is what
    the student is claiming. A line that still carries the squared term is
    offered as the same equation written another way, and had better keep every
    answer. A line that has come down to something linear is one branch of a
    split, and is expected to hold only part of the truth.

    Degree is a stand-in for that intent, so it is a judgement call rather than
    a proof. It errs towards calling a line a branch — being unsure and staying
    quiet is much better than accusing a student who has done nothing wrong.
    """
    try:
        difference = equation.lhs - equation.rhs
        variables = list(difference.free_symbols)

        if len(variables) != 1:
            return True

        return degree(difference, variables[0]) <= 1
    except Exception:
        # Not a polynomial, or something SymPy would not measure. We have no
        # grounds to call it a mistake.
        return True


def judge_step(previous_equation, step_equation, expected, step_solutions):
    """
    Decide what one line has done to the solutions it is supposed to have.

    'expected' is the solution set the student is accountable for: the
    question's, or their own first line's. 'previous_equation' is only needed
    for the fallback, which is the old equation-equivalence rule and compares
    one line against the one immediately above it.

    When neither rule reaches a verdict we answer SAME, letting the step
    through. That is deliberate. A mistake we are unsure about is passed to the
    tutor, which then writes a confident explanation of something that may
    never have happened, so a missed mistake is far cheaper than an invented
    one.
    """
    verdict = with_time_limit(lambda: compare_solutions(expected, step_solutions))

    if verdict == FEWER and not is_case_branch(step_equation):
        return LOST

    if verdict is not None and verdict != CANNOT_TELL:
        return verdict

    agrees = with_time_limit(lambda: same_equation(previous_equation, step_equation))

    if agrees is False:
        return DOES_NOT_FOLLOW

    return SAME


def failure_message(verdict, label, came_from):
    """
    What to say about a bad step when there is no tutor to say it better.

    A dropped answer needs naming for what it is. Told only that the line
    "doesn't follow", a student stares at working that is perfectly sound as
    far as it goes, and the real fault — a root that quietly went missing —
    is nowhere in the sentence.

    "Answers" was the wrong word for it. A student who has not written an
    answer down yet reads "has fewer answers" as being about their working
    rather than about what the equation is true for, and the sentence lands as
    nonsense. "Solution" is what is actually meant.
    """
    if verdict == LOST:
        return f"{label} doesn't keep every solution of {came_from}"

    return f"{label} doesn't follow from {came_from}"


def is_solved(equation):
    """
    True when a step is a finished answer, like "x = 4".

    That means one side is a lone variable and the other is just a number.
    We accept either order, since "4 = x" is equally solved.

    This is only about the shape of one line. A quadratic has two answers, so a
    line can be in this shape and still leave the problem unfinished. Whether
    the student is actually done is worked out in check_equations, which knows
    how many answers the question has.
    """
    sides = [(equation.lhs, equation.rhs), (equation.rhs, equation.lhs)]

    for variable_side, number_side in sides:
        if variable_side.is_Symbol and len(number_side.free_symbols) == 0:
            return True

    return False


def answer_lines(equations):
    """
    Which lines state a finished answer, in the order they were written.
    """
    return [i for i, equation in enumerate(equations) if is_solved(equation)]


def gather_answers(lines, solution_sets):
    """
    Pick out the distinct answers the student has actually given.

    Returns the values found, and the lines that each added one. Both halves
    matter: a student who factors and takes both roots writes two answer lines
    that each add something, while a student who writes "x = 4" twice writes
    two that do not, and the second is wasted work worth mentioning.

    Can be slow. Call it through with_time_limit().
    """
    values = []
    lines_that_added = []

    for i in lines:
        step = solution_sets[i]

        if step.kind != LISTED_VALUES:
            # We could not work out which value this line pins down, so we
            # cannot tell whether it repeats an earlier answer. Count the line,
            # since a line in answer shape is the student's answer either way,
            # and leave the list of values alone.
            lines_that_added.append(i)
            continue

        new_values = [value for value in step.values if not is_one_of(values, value)]

        if len(new_values) > 0:
            values.extend(new_values)
            lines_that_added.append(i)

    return values, lines_that_added


def branch_lines(solution_sets, expected):
    """
    Which lines have narrowed the question down to a case.

    Lines that still carry the whole question are not here — copying it down
    again is not progress through it.
    """
    if expected.kind != LISTED_VALUES:
        return set()

    return {
        i
        for i, step in enumerate(solution_sets)
        if step.kind == LISTED_VALUES and len(step.values) < len(expected.values)
    }


def branch_values(solution_sets, expected, lines):
    """
    Every answer the page has pinned down by narrowing, answer-shaped or not.

    Writing "(x - 3) = 0" and stopping is half of a difference of two squares,
    but it is not shaped like an answer, so counting only lines that read
    "x = something" sees nothing there and calls the page correct so far. It
    isn't: a root has been left behind.

    Returns the answers found and the lines that each brought a new one. The
    second half matters as much as the first: a branch that repeats one already
    taken has added nothing, and should still count as wasted work.

    Can be slow. Call it through with_time_limit().
    """
    values = []
    lines_that_added = []

    for i in sorted(lines):
        new_values = [
            value
            for value in solution_sets[i].values
            if is_one_of(expected.values, value) and not is_one_of(values, value)
        ]

        if len(new_values) > 0:
            values.extend(new_values)
            lines_that_added.append(i)

    return values, lines_that_added


def describe_answers(equations, labels, solution_sets, expected):
    """
    Say how far the student has got, once every step has held up.
    """
    lines = answer_lines(equations)
    gathered = with_time_limit(lambda: gather_answers(lines, solution_sets))

    if gathered is None:
        # Comparing the answers to one another took too long. The steps still
        # hold up, so we fall back on what this checker did before it counted
        # anything: the first line in answer shape is the answer, and we make
        # no claim about how many answers there are.
        values = []
        lines_that_added = lines[:1]
    else:
        values, lines_that_added = gathered

    expected_count = None
    if expected.kind == LISTED_VALUES:
        expected_count = len(expected.values)

    # Count everything the page accounts for, not only the lines that happen to
    # be shaped like an answer. A half-done factorisation is real progress and
    # a real omission, and both deserve saying.
    gathered_branches = with_time_limit(
        lambda: branch_values(solution_sets, expected, branch_lines(solution_sets, expected))
    )
    branches, useful_branches = gathered_branches or ([], [])

    for value in branches:
        if not is_one_of(values, value):
            values.append(value)

    found_count = len(values)

    if len(lines) == 0:
        solved = False
    elif expected.kind == EVERY_VALUE:
        # What the student is working from is true for every value, so no one
        # answer can be all of them. Only reachable from a stray line like
        # x = x, but "solved" would be a plain lie.
        solved = False
    elif expected_count is None or found_count == 0:
        # We do not know how many answers the question has, or could not read
        # the values off the answer lines. Fall back to what this checker did
        # before it counted anything: a line in answer shape means finished.
        # Linear equations never land here, and this is what keeps a page with
        # two unknowns on it behaving as it always did.
        solved = True
    else:
        solved = found_count >= expected_count

    result = {
        "ok": True,
        "solved": solved,
        # Not finished, but far enough along that saying so is useful. Reached
        # either by writing an answer or by narrowing to a branch, because
        # stopping half way through a factorisation is exactly the case that
        # used to pass in silence.
        "partly_solved": (len(lines) > 0 or found_count > 0) and not solved,
        # Both counts are the best we could manage rather than a promise.
        # 'answers_expected' is None when the question has infinitely many
        # answers, or none, or when we could not work them out.
        "answers_found": found_count,
        "answers_expected": expected_count,
    }

    if solved:
        # Every answer the student actually gave, so a quadratic reads
        # "x = 3, x = -3" instead of only the root they happened to write first.
        result["answer"] = ", ".join(labels[i] for i in lines_that_added)

    if result["partly_solved"]:
        if expected_count is None:
            result["message"] = "That is an answer, but it is not the only one."
        else:
            result["message"] = (
                f"You've found {found_count} of the {expected_count} answers. Keep going."
            )

    # Writing more lines after the answer isn't wrong, but it is wasted work,
    # so say so rather than staying silent. Two kinds of line below the first
    # answer are not wasted at all, and calling them wasted would be telling a
    # student off for doing the question properly: a second root, and the
    # branch line that leads to it — "x + 3 = 0" written under "x = 3" is the
    # next case, not an afterthought.
    if len(lines) > 0:
        wasted = [
            i
            for i in range(lines[0] + 1, len(equations))
            if i not in lines_that_added and i not in useful_branches
        ]

        if len(wasted) > 0:
            result["extra_steps"] = True

    return result


def check_equations(equations, labels, problem_equation=None):
    """
    Compare each line to the solutions it should have and report the first bad one.

    'equations' are SymPy objects. 'labels' are what to call each line in the
    error message — the typed text, or the handwriting we recognized.
    'problem_equation' is the question the student was asked, when there is
    one, so we can catch a mis-copied first line.

    Returns a dict like:
      {"ok": True, "solved": True, "answer": "x = 4", ...}
    or
      {"ok": False, "error_step": 3, "message": "x = 5 doesn't follow from 2x = 8"}

    'error_step' counts the equations we were given from 1, and the caller maps
    it back to the row of the page it was written on.
    """
    if len(equations) == 0:
        return {"ok": True, "solved": False}

    solution_sets = [solutions_of(equation) for equation in equations]

    if problem_equation is None:
        expected = solution_sets[0]
    else:
        # What the student owes us is every value that answers the question, so
        # when we have the question we take it from there rather than from their
        # first line. Their first line may already be one branch of a case
        # split, and taking it as the goal would let them stop half way.
        expected = solutions_of(problem_equation)

        # The question is already on the page, so the student's first line is a
        # first move, not a copy. Checking it against the question catches a bad
        # opening step — and a wrong first line would otherwise make every line
        # after it look wrong too, sending them hunting in the wrong place.
        verdict = judge_step(problem_equation, equations[0], expected, solution_sets[0])

        if verdict in MISTAKES:
            return {
                "ok": False,
                "error_step": 1,
                # The full stop belongs to the phrase, not the sentence: a line
                # named after the one above it ends without one, and these two
                # messages have always read that way on the page.
                "message": failure_message(verdict, labels[0], "the question."),
                "reason": verdict,
            }

    # Step 1 is the starting equation, so we start comparing at step 2. Each
    # line is measured against the whole question rather than only against the
    # line above it: once the student has split into cases, the line above is
    # one branch, and the other root would look like an invented solution
    # standing next to it even though it was there the whole time.
    for i in range(1, len(equations)):
        verdict = judge_step(equations[i - 1], equations[i], expected, solution_sets[i])

        if verdict in MISTAKES:
            return {
                "ok": False,
                "error_step": i + 1,
                "message": failure_message(verdict, labels[i], labels[i - 1]),
                "reason": verdict,
            }

    return describe_answers(equations, labels, solution_sets, expected)


def check_steps(steps):
    """
    Check a list of typed steps like ["2x + 5 = 13", "2x = 8"].
    """
    if len(steps) == 0:
        return {"ok": True}

    equations = [parse_equation(step) for step in steps]
    return check_equations(equations, steps)


def restates(equation, problem_equation):
    """
    Whether this line is the question itself, written out again.

    Deliberately stricter than same_equation(). Almost every line of a correct
    solution has the same solutions as the question, and most of them are the
    same equation by the "one side is a multiple of the other" rule too —
    2x + 5 = 13 and 2x = 8 both come down to 2x - 8. Either of those tests
    would call every step a fresh start.

    Writing the question out again means writing the same two sides, so that
    is what we look for.
    """
    if problem_equation is None:
        return False

    def compare():
        return (
            simplify(equation.lhs - problem_equation.lhs) == 0
            and simplify(equation.rhs - problem_equation.rhs) == 0
        )

    return with_time_limit(compare) is True


def attempt_starts(equations, problem_equation):
    """
    Where each run at the question begins.

    A student who gets stuck does not rub out what they have done. They copy
    the question down again lower on the page, or in the space beside it, and
    start over. Read as one long chain, the good second attempt is buried
    under a mistake in the first, and the page is reported as wrong however
    well the student finished.
    """
    starts = [0]

    for i in range(1, len(equations)):
        if restates(equations[i], problem_equation):
            starts.append(i)

    return starts


def how_far_it_got(result):
    """
    Rank one attempt, so the page can be judged on the best of them.
    """
    if not result["ok"]:
        return 0

    if result.get("solved"):
        return 2

    return 1


def check_page(equations, labels, problem_equation=None):
    """
    Check everything on the page, allowing for more than one go at it.

    Splits the lines into attempts, checks each on its own, and reports the
    one that got furthest — later attempts winning ties, since that is the one
    the student is looking at.

    Reporting the best rather than the last is what makes a page of crossings
    out safe to leave alone. A student who solved it, then started idly
    writing again underneath, has still solved it; a student whose first go
    was a mess and whose second was right is told they were right.
    """
    starts = attempt_starts(equations, problem_equation)

    if len(starts) < 2:
        return check_equations(equations, labels, problem_equation)

    attempts = []

    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(equations)
        result = check_equations(equations[start:end], labels[start:end], problem_equation)

        # error_step counts within the attempt. The caller knows only about
        # the page, so put it back into the page's numbering.
        if not result["ok"]:
            result["error_step"] += start

        attempts.append(result)

    best = max(range(len(attempts)), key=lambda i: (how_far_it_got(attempts[i]), i))

    chosen = dict(attempts[best])
    chosen["attempts"] = len(attempts)
    chosen["attempt_read"] = best + 1

    return chosen
