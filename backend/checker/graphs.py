"""
Turns a function into something the iPad can draw.

The same rule holds here as everywhere else in this app: the model does not do
the maths. It says which function is worth drawing, and every number that comes
back — where the curve goes, where it crosses the axis, where it turns — is
worked out by SymPy. A model asked to plot a parabola will happily report roots
that are nearly right, and a graph with the roots in the wrong place is worse
than no graph, because it looks authoritative.

So this samples the function properly and sends across a list of points. The
iPad joins them up. That keeps the drawing end simple — no expression parser on
the device — and means anything SymPy can evaluate can be plotted, not just the
quadratics this was written for.
"""

import re

from sympy import Poly, im, lambdify, solve
from sympy.parsing.sympy_parser import parse_expr

from checker.parser import PARSER_RULES, plain_symbols

# What may sit on the left of an equals sign and still be naming a curve
# rather than asking a question: y, or f(x) and its usual friends.
LABEL = re.compile(r"^\s*(y|[fgh]\s*\(\s*[a-z]\s*\))\s*$", re.IGNORECASE)

# How many points make the curve. Enough that a parabola looks smooth on a
# retina screen, few enough that the whole sheet still fits in one response.
SAMPLES = 80

# How far past the interesting part of the curve to keep drawing, as a share of
# the stretch between the outermost marked points. A parabola drawn to exactly
# its own roots looks like a bowl with the sides sawn off.
MARGIN = 0.6

# How wide to open the view when every marked point is in the same place — a
# repeated root, or a curve that never crosses. Wide enough to be a graph
# rather than a dot, narrow enough that the curve does not shoot off the top.
FLAT_SPAN = 2.5

# A drawn axis has to stop somewhere. Past this the curve is a vertical line and
# tells the student nothing.
TALLEST = 40.0


def plot(expression):
    """
    Sample a function of one variable, and find what is worth marking on it.

    Returns None for anything that cannot be drawn honestly — more than one
    unknown, a function that is not real-valued, a constant. The caller drops
    the graph and keeps the rest of the card.
    """
    curve = _read(expression)

    if curve is None:
        return None

    function, unknown = curve

    roots = _roots(function, unknown)
    turning = _turning_point(function, unknown)

    span = _span(roots, turning)

    if span is None:
        return None

    points = _sample(function, unknown, span)

    # Two points is a line segment, not a graph. Usually means the function
    # went complex or infinite across most of the range we chose.
    if len(points) < 3:
        return None

    return {
        "expression": str(expression).replace("**", "^"),
        "variable": str(unknown),
        "points": points,
        "roots": roots,
        "turningPoint": turning,
        "yIntercept": _value(function, unknown, 0),
        "xRange": list(span),
        "yRange": _height(points),
    }


def _read(expression):
    """The function and its unknown, or None if it is not one we can draw."""
    written = plain_symbols(str(expression)).strip()

    # Told to send the function on its own, a model still writes it the way a
    # book writes it. That is not worth throwing a graph away over: "y = x**2"
    # names exactly the same curve as "x**2". So a label on the left is taken
    # off, and anything else with an equals sign in it is refused — an equation
    # is a question about where two things meet, not a curve.
    if "=" in written:
        left, _, right = written.partition("=")

        if not LABEL.match(left):
            return None

        written = right.strip()

    try:
        function = parse_expr(written, transformations=PARSER_RULES)
    except Exception:
        return None

    unknowns = function.free_symbols

    # A constant has nothing to show, and two unknowns describe a surface.
    if len(unknowns) != 1:
        return None

    return function, next(iter(unknowns))


def _roots(function, unknown):
    """Where the curve crosses the axis. Real crossings only — a complex root
    is not a place on the paper."""
    try:
        answers = solve(function, unknown)
    except Exception:
        return []

    crossings = []

    for answer in answers:
        try:
            if im(answer) != 0:
                continue

            crossings.append(round(float(answer), 4))
        except (TypeError, ValueError):
            continue

    return sorted(crossings)


def _turning_point(function, unknown):
    """
    The vertex, for a quadratic.

    Only quadratics, deliberately. It is the one turning point a student is
    ever asked to mark, it has a closed form, and finding the interesting one
    on an arbitrary curve is a different problem than this app has.
    """
    try:
        coefficients = Poly(function, unknown).all_coeffs()
    except Exception:
        return None

    if len(coefficients) != 3:
        return None

    a, b, _ = coefficients

    if a == 0:
        return None

    at = -b / (2 * a)

    height = _value(function, unknown, at)

    if height is None:
        return None

    return [round(float(at), 4), height]


def _span(roots, turning):
    """
    Which stretch of the x axis to draw.

    Wide enough to hold everything worth seeing, with air around it. A graph
    cropped tight to its own roots reads as a mistake.
    """
    marked = list(roots)

    if turning:
        marked.append(turning[0])

    # Nothing to centre on: show the origin, which is where a student looks
    # first anyway.
    if not marked:
        return (-5.0, 5.0)

    low, high = min(marked), max(marked)

    if high - low < 1e-9:
        return (low - FLAT_SPAN, high + FLAT_SPAN)

    air = (high - low) * MARGIN

    return (round(low - air, 4), round(high + air, 4))


def _sample(function, unknown, span):
    """The curve, as points. Anything that is not a real number is left out
    rather than guessed at, which is what puts the break in a hyperbola."""
    try:
        evaluate = lambdify(unknown, function, "math")
    except Exception:
        return []

    low, high = span
    step = (high - low) / (SAMPLES - 1)

    points = []

    for index in range(SAMPLES):
        at = low + step * index

        try:
            height = float(evaluate(at))
        except Exception:
            continue

        if height != height or abs(height) > TALLEST:
            continue

        points.append([round(at, 4), round(height, 4)])

    return points


def _height(points):
    """How tall to draw the axes, with a little air top and bottom."""
    heights = [height for _, height in points]

    low, high = min(heights), max(heights)

    # Always show the axis itself. A parabola sitting entirely above it, drawn
    # without it, is just a curve.
    low, high = min(low, 0.0), max(high, 0.0)

    air = max((high - low) * 0.15, 0.5)

    return [round(low - air, 4), round(high + air, 4)]


def _value(function, unknown, at):
    """What the function is worth at a point, as a plain number, or None."""
    try:
        height = function.subs(unknown, at)

        if im(height) != 0:
            return None

        return round(float(height), 4)
    except (TypeError, ValueError):
        return None
