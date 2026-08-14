"""
Checks the plotter.

Run it with:  python test_graphs.py

What matters here is that nothing gets drawn that would teach the student
something false. A curve with its roots in the wrong place, or an axis drawn
where the origin is not, is worse than no graph at all — a graph looks
authoritative in a way a sentence does not, and a student will believe it over
their own working.

So these check three things: the marked points are the real ones, the view is
wide enough to hold what it marked, and anything that cannot be drawn honestly
comes back as nothing rather than as a guess.
"""

from checker.graphs import plot

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


# What comes back at all


def test_a_constant_is_not_a_graph():
    check("a constant is not a graph", plot("7") is None, plot("7"))


def test_two_unknowns_cannot_be_drawn():
    check("two unknowns cannot be drawn", plot("x*y") is None)


def test_nonsense_is_not_drawn():
    check("nonsense is not drawn", plot("!!") is None)


def test_nothing_asked_for_is_nothing_drawn():
    check("nothing asked for is nothing drawn", plot("") is None)


# The points that get marked


def test_roots_of_a_quadratic():
    graph = plot("x**2 - 4x + 3")

    check("roots of a quadratic", graph["roots"] == [1.0, 3.0], graph["roots"])


def test_a_caret_means_the_same_as_two_stars():
    check(
        "a caret means the same as two stars",
        plot("x^2 - 4x + 3")["roots"] == plot("x**2 - 4x + 3")["roots"],
    )


def test_a_named_curve_is_still_a_curve():
    """Told to send the function alone, a model still writes it the way a book
    does. Both name the same curve."""
    check(
        "y = ... names the same curve",
        plot("y = x**2 - 4x + 3")["roots"] == [1.0, 3.0],
    )
    check(
        "f(x) = ... names the same curve",
        plot("f(x) = x^2 - 4x + 3")["roots"] == [1.0, 3.0],
    )


def test_an_equation_is_a_question_not_a_curve():
    """"x**2 = 4" asks where two things meet. Drawing it as a curve would put
    a graph on the page that answers something nobody asked."""
    check("an equation is not drawn", plot("x**2 = 4") is None)


def test_repeated_root_is_marked_once():
    graph = plot("x**2 + 6x + 9")

    check("a repeated root is marked once", graph["roots"] == [-3.0], graph["roots"])


def test_complex_roots_are_not_places_on_the_paper():
    graph = plot("x**2 + 1")

    check(
        "complex roots are not places on the paper",
        graph["roots"] == [],
        graph["roots"],
    )


def test_vertex_of_a_quadratic():
    graph = plot("x**2 - 4x + 3")

    check(
        "vertex of a quadratic",
        graph["turningPoint"] == [2.0, -1.0],
        graph["turningPoint"],
    )


def test_a_line_has_no_vertex():
    graph = plot("2x + 3")

    check("a line has no vertex", graph["turningPoint"] is None)
    check("a line still has its root", graph["roots"] == [-1.5], graph["roots"])


def test_y_intercept_is_the_constant_term():
    graph = plot("x**2 - 4x + 3")

    check(
        "y intercept is the constant term",
        graph["yIntercept"] == 3.0,
        graph["yIntercept"],
    )


# The view


def test_the_curve_is_sampled_not_sketched():
    graph = plot("x**2 - 4x + 3")

    check(
        "the curve is sampled, not sketched",
        len(graph["points"]) > 20,
        len(graph["points"]),
    )


def test_points_lie_on_the_curve():
    """
    Loosely, on purpose. Both numbers are rounded to four places before being
    sent, so working the height out again from the rounded x cannot match to
    the last decimal — and does not need to, on a curve a few hundred points
    wide. What this is watching for is a curve that is the wrong shape.
    """
    graph = plot("x**2 - 4x + 3")

    off = [
        (x, y) for x, y in graph["points"] if abs(y - (x**2 - 4 * x + 3)) > 1e-3
    ]

    check("every point lies on the curve", not off, off[:3])


def test_the_view_holds_every_marked_point():
    graph = plot("x**2 - 4x + 3")

    low, high = graph["xRange"]
    marked = graph["roots"] + [graph["turningPoint"][0]]

    check(
        "the view holds every marked point",
        all(low < at < high for at in marked),
        graph["xRange"],
    )


def test_the_view_holds_the_curve_it_drew():
    graph = plot("x**2 - 4x + 3")

    low, high = graph["yRange"]

    check(
        "the view holds the curve it drew",
        all(low <= y <= high for _, y in graph["points"]),
        graph["yRange"],
    )


def test_roots_are_not_drawn_against_the_edge():
    """A parabola cropped to exactly its own roots reads as a mistake."""
    graph = plot("x**2 - 4x + 3")

    low, high = graph["xRange"]

    check(
        "roots are not drawn against the edge",
        low < 1.0 - 0.3 and high > 3.0 + 0.3,
        graph["xRange"],
    )


def test_the_axis_is_always_in_view():
    """A curve sitting entirely above the axis, drawn without it, is just a
    curve. The range always reaches zero so there is something to sit on."""
    graph = plot("x**2 + 1")

    low, high = graph["yRange"]

    check("the axis is always in view", low <= 0 <= high, graph["yRange"])


def test_a_curve_that_shoots_off_is_cut_rather_than_flattened():
    """1/x has no value at zero. That gap belongs in the points, rather than
    being filled in with a straight line across the middle of the graph."""
    graph = plot("1/x")

    check(
        "a curve that shoots off is cut rather than flattened",
        all(abs(y) < 100 for _, y in graph["points"]),
    )


if __name__ == "__main__":
    test_a_constant_is_not_a_graph()
    test_two_unknowns_cannot_be_drawn()
    test_nonsense_is_not_drawn()
    test_nothing_asked_for_is_nothing_drawn()
    test_roots_of_a_quadratic()
    test_a_caret_means_the_same_as_two_stars()
    test_a_named_curve_is_still_a_curve()
    test_an_equation_is_a_question_not_a_curve()
    test_repeated_root_is_marked_once()
    test_complex_roots_are_not_places_on_the_paper()
    test_vertex_of_a_quadratic()
    test_a_line_has_no_vertex()
    test_y_intercept_is_the_constant_term()
    test_the_curve_is_sampled_not_sketched()
    test_points_lie_on_the_curve()
    test_the_view_holds_every_marked_point()
    test_the_view_holds_the_curve_it_drew()
    test_roots_are_not_drawn_against_the_edge()
    test_the_axis_is_always_in_view()
    test_a_curve_that_shoots_off_is_cut_rather_than_flattened()

    print()
    print(f"{passed} passed, {failed} failed")

    if failed > 0:
        raise SystemExit(1)
