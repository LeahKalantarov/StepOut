from tutor.prompts import build_tutor_prompt, looks_like_pushback, template_response


def test_pushback_detection():
    assert looks_like_pushback("You are wrong")
    assert looks_like_pushback("I divided by 3")
    assert not looks_like_pushback("2x = 8")


def test_template_wrong_answer():
    result = {
        "ok": False,
        "reason": "wrong_answer",
        "expected_answer": "x = 4",
        "message": "You wrote x = 6, but 2x = 8 gives x = 4.",
    }
    reply = template_response(check_result=result, student_message="You are wrong")
    assert "misread" in reply.lower() or "push" in reply.lower() or "look again" in reply.lower()


def test_prompt_includes_notes():
    prompt = build_tutor_prompt(
        recognized=["2x = 8", "x = 6"],
        check_result={"ok": False, "error_step": 2, "reason": "wrong_answer", "message": "oops"},
        student_message="You are wrong",
        notes="Teacher said divide both sides.",
        photo_descriptions=["worksheet page 4"],
    )
    assert "Teacher said divide both sides." in prompt
    assert "worksheet page 4" in prompt
    assert "You are wrong" in prompt


if __name__ == "__main__":
    test_pushback_detection()
    test_template_wrong_answer()
    test_prompt_includes_notes()
    print("tutor prompt tests passed")
