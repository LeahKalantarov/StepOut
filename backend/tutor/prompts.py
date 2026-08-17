"""
Build the tutor's view of a check — what happened, what the student said,
and any notes or photos they attached.
"""

PUSHBACK_PHRASES = (
    "you are wrong",
    "you're wrong",
    "thats wrong",
    "that's wrong",
    "not wrong",
    "i did divide",
    "i divided",
    "thats right",
    "that's right",
    "misread",
    "didnt divide",
    "didn't divide",
    "wrong number",
)


def looks_like_pushback(text: str) -> bool:
    lowered = text.lower().strip()
    if not lowered:
        return False
    return any(phrase in lowered for phrase in PUSHBACK_PHRASES)


def build_tutor_prompt(
    *,
    recognized: list[str],
    check_result: dict,
    student_message: str | None = None,
    notes: str | None = None,
    photo_descriptions: list[str] | None = None,
) -> str:
    lines = [
        "You are a patient math tutor reviewing a student's handwritten algebra.",
        "Be concise, specific, and kind. Reference their actual steps.",
        "If they push back, take them seriously — consider misread handwriting.",
        "",
        "Steps as we read them:",
    ]

    for index, step in enumerate(recognized, start=1):
        lines.append(f"  {index}. {step}")

    if check_result.get("ok"):
        lines.append("")
        lines.append("Checker verdict: steps are valid so far.")
        if check_result.get("solved"):
            lines.append(f"Solved: {check_result.get('answer')}")
    else:
        lines.append("")
        lines.append(f"Checker verdict: step {check_result.get('error_step')} failed.")
        lines.append(f"Reason: {check_result.get('reason', 'unknown')}")
        lines.append(f"Message shown: {check_result.get('message')}")
        if check_result.get("expected_answer"):
            lines.append(f"Expected answer from prior step: {check_result['expected_answer']}")

    if notes:
        lines.extend(["", "Student notes:", notes])

    if photo_descriptions:
        lines.extend(["", "Attached photos:"])
        for description in photo_descriptions:
            lines.append(f"  - {description}")

    if student_message:
        lines.extend(["", "Student just wrote:", student_message])

    lines.extend(
        [
            "",
            "Write 2-4 short sentences. If they disputed the verdict, explain what you see",
            "in their steps and what would make the step valid. Offer one concrete next move.",
        ]
    )

    return "\n".join(lines)


def template_response(
    *,
    check_result: dict,
    student_message: str | None = None,
    notes: str | None = None,
) -> str:
    """Fallback tutor voice when no LLM key is configured."""
    if student_message and looks_like_pushback(student_message):
        if check_result.get("reason") == "wrong_divisor":
            return (
                "I hear you — let me look again. From your previous line, the number you divide "
                "both sides by has to match the coefficient on x. Check the 'Read as' lines above "
                "to make sure we copied your handwriting correctly."
            )
        if check_result.get("reason") == "wrong_answer":
            expected = check_result.get("expected_answer", "the value from the line above")
            return (
                f"Thanks for pushing back. From the step before, I get {expected}. "
                "If your work matches that, we may have misread a digit — compare each "
                "'Read as' line to what you actually wrote."
            )
        if check_result.get("reason") == "divided_one_side":
            return (
                "Fair point. When you divide, the same number has to hit both sides — "
                "otherwise the equation stops being true. Want to try dividing both sides again?"
            )
        return (
            "I hear you. Walk me through what you did on that line — and check whether "
            "what we read matches your handwriting in the list above."
        )

    if not check_result.get("ok"):
        return check_result.get("message") or "That step doesn't follow yet. Want to try once more?"

    if check_result.get("solved"):
        return f"Nice — {check_result.get('answer', 'that works')}."

    return "Looks good so far. Keep going."
