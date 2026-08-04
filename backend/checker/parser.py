from sympy import Eq
from sympy.parsing.latex import parse_latex
from sympy.parsing.sympy_parser import (
    convert_xor,
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)

# Lets SymPy read "2x" as "2 * x", and "x^2" as x squared. A caret is Python's
# bitwise operator rather than a power, so without convert_xor a line like
# "x^2 - 9 = 0" does not parse at all, and every quadratic would have to be
# written "x**2" — which is also how it would be handwritten onto the page in
# front of the student, since the problem is shown exactly as it is stored.
PARSER_RULES = standard_transformations + (
    convert_xor,
    implicit_multiplication_application,
)


# The symbols people write by hand, and their keyboard equivalents. A language
# model reaches for these because they are how maths is printed in a textbook,
# but SymPy only reads the ASCII forms, and the stroke font on the iPad has no
# glyph for any of them.
MATHS_SYMBOLS = {
    "\u00f7": "/",  # ÷
    "\u00d7": "*",  # ×
    "\u2212": "-",  # − proper minus, not a hyphen
    "\u2044": "/",  # ⁄ fraction slash
    "\u22c5": "*",  # ⋅
    "\u00b7": "*",  # ·
}


def plain_symbols(text):
    """
    Rewrite printed maths symbols as the ones a keyboard can type.
    """
    for printed, typed in MATHS_SYMBOLS.items():
        text = text.replace(printed, typed)

    return text


def parse_equation(text):
    """
    Turn a string like "2x + 5 = 13" into a SymPy equation object.
    """
    text = plain_symbols(text).strip()

    if text.count("=") != 1:
        raise ValueError(f"Need exactly one '=': {text}")

    left_text, right_text = text.split("=")
    left = parse_expr(left_text.strip(), transformations=PARSER_RULES)
    right = parse_expr(right_text.strip(), transformations=PARSER_RULES)

    # evaluate=False for the same reason parse_latex_equation needs it. Given
    # "x = x", SymPy would decide the statement is simply True and hand back a
    # boolean with no sides on it, and the checker would then fall over on a
    # line that is merely useless rather than unreadable.
    return Eq(left, right, evaluate=False)


def parse_latex_equation(latex_text):
    """
    Turn LaTeX from MyScript, like "\\frac{x}{2}=3", into a SymPy equation.

    Handwriting gives us LaTeX instead of plain text because LaTeX can
    describe fractions and exponents, which plain text cannot.
    """
    latex_text = latex_text.strip()

    if latex_text.count("=") != 1:
        raise ValueError(f"Need exactly one '=': {latex_text}")

    # We read each side on its own instead of handing the whole line to SymPy.
    # Given "1 = 1", SymPy would decide the statement is simply True and hand
    # back a boolean, which we cannot compare against other steps. Building the
    # equation ourselves with evaluate=False keeps both sides intact.
    left_text, right_text = latex_text.split("=")
    left = parse_latex(left_text.strip())
    right = parse_latex(right_text.strip())

    return Eq(left, right, evaluate=False)
