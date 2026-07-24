from sympy import Eq
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
