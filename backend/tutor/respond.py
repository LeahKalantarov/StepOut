import os

import httpx

from tutor.prompts import build_tutor_prompt, template_response


async def tutor_respond(
    *,
    recognized: list[str],
    check_result: dict,
    student_message: str | None = None,
    notes: str | None = None,
    photo_descriptions: list[str] | None = None,
) -> dict:
    prompt = build_tutor_prompt(
        recognized=recognized,
        check_result=check_result,
        student_message=student_message,
        notes=notes,
        photo_descriptions=photo_descriptions,
    )

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return {
            "reply": template_response(
                check_result=check_result,
                student_message=student_message,
                notes=notes,
            ),
            "prompt": prompt,
            "source": "template",
        }

    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": model,
                "messages": [
                    {
                        "role": "system",
                        "content": "You are a concise, warm math tutor for middle-school algebra.",
                    },
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.4,
                "max_tokens": 220,
            },
        )
        response.raise_for_status()
        body = response.json()

    reply = body["choices"][0]["message"]["content"].strip()
    return {"reply": reply, "prompt": prompt, "source": "openai"}
