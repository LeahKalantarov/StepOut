"""
Checks the photograph path: tidying a model's reply, and marking what it read.

Run it with:  python test_photo.py

Nothing here touches the network or needs an API key. The request to the model
is one function, `read_photo`, and it is deliberately thin; everything that can
be wrong in an interesting way lives either side of it. So the tests cover the
tidying of a reply — fenced blocks, numbering, commentary the model was asked
not to write — and the marking of the lines that come out, which is the part a
student actually sees.

Every case prints PASS or FAIL, and the script exits non-zero if anything
failed, so it can be trusted without reading the output.
"""

from checker.photo import looks_like_an_image, read_photo, tidy_lines
from checker.review import review_lines

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


# MARK: reading the reply


def test_plain_lines_survive():
    lines = tidy_lines("2x + 5 = 13\n2x = 8\nx = 4")
    check(
        "plain lines come through unchanged",
        lines == ["2x + 5 = 13", "2x = 8", "x = 4"],
        lines,
    )


def test_blank_lines_are_dropped():
    lines = tidy_lines("2x = 8\n\n\nx = 4\n")
    check("blank lines are dropped", lines == ["2x = 8", "x = 4"], lines)


def test_code_fences_are_dropped():
    lines = tidy_lines("```\n2x = 8\nx = 4\n```")
    check("markdown fences are dropped", lines == ["2x = 8", "x = 4"], lines)


def test_numbering_is_stripped():
    lines = tidy_lines("1. 2x + 5 = 13\n2) 2x = 8\nstep 3: x = 4")
    check(
        "numbering the model added is stripped",
        lines == ["2x + 5 = 13", "2x = 8", "x = 4"],
        lines,
    )


def test_bullets_are_stripped():
    lines = tidy_lines("- 2x = 8\n* x = 4")
    check("bullets are stripped", lines == ["2x = 8", "x = 4"], lines)


def test_commentary_is_ignored():
    reply = "Here is the working I can see:\n2x = 8\nx = 4\nHope that helps!"
    lines = tidy_lines(reply)
    check(
        "sentences without maths are ignored",
        lines == ["2x = 8", "x = 4"],
        lines,
    )


def test_latex_is_made_readable():
    lines = tidy_lines(r"\frac{x}{2} = 3")
    check(
        "latex that slipped through is written as it would be on paper",
        lines and "\\" not in lines[0],
        lines,
    )


def test_nothing_readable_gives_nothing():
    check("an empty reply reads as no lines", tidy_lines("") == [], tidy_lines(""))
    check("None reads as no lines", tidy_lines(None) == [], tidy_lines(None))
    check(
        "a reply with no maths in it reads as no lines",
        tidy_lines("I cannot see any handwriting in this photograph.") == [],
        tidy_lines("I cannot see any handwriting in this photograph."),
    )


# MARK: guarding the request


def test_rubbish_is_not_sent_to_the_model():
    check("empty upload is refused", not looks_like_an_image(""))
    check("None is refused", not looks_like_an_image(None))
    check("truncated base64 is refused", not looks_like_an_image("not base64!!"))
    check("real base64 is accepted", looks_like_an_image("aGVsbG8="))


def test_no_key_reads_nothing():
    # An empty list rather than an exception: a photograph nobody can read is
    # something to say to the student, not something to crash a request.
    check(
        "a bad upload reads as no lines without calling anyone",
        read_photo("not base64!!") == [],
    )


# MARK: marking what was read


def test_correct_working_passes():
    result = review_lines(["2x + 5 = 13", "2x = 8", "x = 4"], narrate=False)
    check("correct working passes", result["ok"], result)
    check("and is seen as solved", result.get("solved"), result)


def test_a_wrong_step_is_caught():
    result = review_lines(["2x + 5 = 13", "2x = 8", "x = 5"], narrate=False)
    check("a wrong step fails", not result["ok"], result)
    check("on the third line", result.get("error_step") == 3, result.get("error_step"))


def test_a_wrong_step_carries_what_a_lesson_needs():
    result = review_lines(["2x = 8", "x = 5"], narrate=False)
    help_context = result.get("help") or {}

    check("help comes back with the verdict", bool(help_context), result)
    check(
        "naming the line that does not follow",
        help_context.get("wrong_line") == "x = 5",
        help_context,
    )
    check(
        "and the line it had to follow from",
        help_context.get("previous_line") == "2x = 8",
        help_context,
    )


def test_annotations_are_set_aside_not_failed():
    # "-5" under both sides is how people work. It is not an equation, and it
    # must not sink a page that is otherwise right.
    result = review_lines(["2x + 5 = 13", "-5", "2x = 8", "x = 4"], narrate=False)

    check("a page with an annotation on it still passes", result["ok"], result)
    check("and the annotation is reported back", "-5" in result["ignored"], result)


def test_a_photo_with_no_maths_says_so():
    result = review_lines([], narrate=False)

    check("an empty read is not a failure", result["ok"], result)
    check("and says what to do", bool(result.get("message")), result)


def test_recognized_lines_come_back():
    result = review_lines(["2x = 8", "x = 4"], narrate=False)
    check(
        "what was read is handed back for the student to check",
        result["recognized"] == ["2x = 8", "x = 4"],
        result.get("recognized"),
    )


def test_working_on_the_problem_they_were_set():
    # Problem 1 is "2x + 5 = 13". Photographed work that starts from it should
    # be marked against it, the same as work written on the page.
    result = review_lines(["2x + 5 = 13", "2x = 8", "x = 4"], problem_index=1, narrate=False)

    check("work matching the set problem passes", result["ok"], result)


def test_working_on_a_different_problem_is_caught():
    # Photographing the wrong page is easy to do, and being told the answer is
    # wrong when it is the question that is wrong would be baffling.
    result = review_lines(["9x = 81", "x = 9"], problem_index=1, narrate=False)

    check(
        "work that is not the set problem is not silently passed",
        not result["ok"],
        result,
    )


def test_a_problem_index_nobody_has_does_not_crash():
    result = review_lines(["2x = 8", "x = 4"], problem_index=999, narrate=False)

    check("an unknown problem falls back to checking the steps alone", result["ok"], result)


# MARK: the endpoint the iPad calls


def endpoint_answer(reads_as, problem_index=None):
    """
    Post a photograph to the app, with the reading of it decided in advance.

    The model is stood in for rather than called. What is being tested is the
    endpoint around it — that a photograph comes back marked, in the shape the
    iPad already knows how to read.
    """
    from fastapi.testclient import TestClient

    import main

    original = main.read_photo
    main.read_photo = lambda image, media_type="image/jpeg": reads_as

    try:
        response = TestClient(main.app).post(
            "/check-photo",
            json={"image_base64": "aGVsbG8=", "problem_index": problem_index},
        )
        return response.json()
    finally:
        main.read_photo = original


def test_endpoint_passes_good_working():
    body = endpoint_answer(["2x + 5 = 13", "2x = 8", "x = 4"])
    check("the endpoint passes good working", body.get("ok"), body)


def test_endpoint_catches_a_wrong_step():
    body = endpoint_answer(["2x = 8", "x = 5"])

    check("the endpoint catches a wrong step", body.get("ok") is False, body)
    check("and names the line", body.get("error_step") == 2, body.get("error_step"))
    check("and offers what a lesson needs", bool(body.get("help")), body)


def test_endpoint_handles_an_unreadable_photo():
    body = endpoint_answer([])

    check("an unreadable photo is not an error", body.get("ok"), body)
    check("and says how to retake it", "photo" in (body.get("message") or ""), body)


if __name__ == "__main__":
    test_plain_lines_survive()
    test_blank_lines_are_dropped()
    test_code_fences_are_dropped()
    test_numbering_is_stripped()
    test_bullets_are_stripped()
    test_commentary_is_ignored()
    test_latex_is_made_readable()
    test_nothing_readable_gives_nothing()

    test_rubbish_is_not_sent_to_the_model()
    test_no_key_reads_nothing()

    test_correct_working_passes()
    test_a_wrong_step_is_caught()
    test_a_wrong_step_carries_what_a_lesson_needs()
    test_annotations_are_set_aside_not_failed()
    test_a_photo_with_no_maths_says_so()
    test_recognized_lines_come_back()
    test_working_on_the_problem_they_were_set()
    test_working_on_a_different_problem_is_caught()
    test_a_problem_index_nobody_has_does_not_crash()

    test_endpoint_passes_good_working()
    test_endpoint_catches_a_wrong_step()
    test_endpoint_handles_an_unreadable_photo()

    print()
    print(f"{passed} passed, {failed} failed")

    if failed > 0:
        raise SystemExit(1)
