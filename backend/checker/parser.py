from sympy import Eq
from sympy.parsing.latex import parse_latex
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    parse_expr,
    standard_transformations,
)

# Lets SymPy read "2x" as "2 * x"
PARSER_RULES = standard_transformations + (implicit_multiplication_application,)


def parse_equation(text):
    """
    Turn a string like "2x + 5 = 13" into a SymPy equation object.
    """
    text = text.strip()

    if text.count("=") != 1:
        raise ValueError(f"Need exactly one '=': {text}")

    left_text, right_text = text.split("=")
    left = parse_expr(left_text.strip(), transformations=PARSER_RULES)
    right = parse_expr(right_text.strip(), transformations=PARSER_RULES)

    return Eq(left, right)


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
