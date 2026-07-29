"""
Turns Apple Pencil strokes into math text by asking MyScript to read them.

The iPad sends us raw pen coordinates. We forward them to MyScript's
recognition service, which sends back the equation written in LaTeX.
"""

import hashlib
import hmac
import json
import os

import httpx
from dotenv import load_dotenv

load_dotenv()

MYSCRIPT_URL = "https://cloud.myscript.com/api/v4.0/iink/recognize"

# MyScript measures the writing area in millimeters, but the iPad sends
# coordinates in screen points. This converts between the two.
# An iPad Air fits about 132 points per inch, and telling MyScript the real
# size helps it judge whether a small raised symbol is an exponent.
POINTS_PER_INCH = 132
MM_PER_INCH = 25.4
SCALE = MM_PER_INCH / POINTS_PER_INCH


def sign_request(body_text, application_key, hmac_key):
    """
    Prove to MyScript that the request really came from us.

    MyScript wants a SHA-512 fingerprint of the exact request body,
    salted with our two keys glued together.
    """
    secret = (application_key + hmac_key).encode("utf-8")
    return hmac.new(secret, body_text.encode("utf-8"), hashlib.sha512).hexdigest()


def build_request_body(strokes):
    """
    Package one row of pen strokes the way MyScript expects.

    'strokes' looks like: [{"x": [1, 2, 3], "y": [4, 5, 6]}, ...]
    where each dict is one continuous pen line.
    """
    return {
        "contentType": "Math",
        "scaleX": SCALE,
        "scaleY": SCALE,
        "configuration": {
            # Critical: we do NOT want MyScript to solve or tidy up the math.
            # Our whole job is catching the student's mistakes, so we need
            # the equation exactly as it was written.
            "math": {"solver": {"enable": False}}
        },
        "strokes": strokes,
    }


def read_handwriting(strokes):
    """
    Send one row of strokes to MyScript and return the LaTeX it recognized.

    Example return value: "2x+5=13"
    """
    application_key = os.getenv("MYSCRIPT_APPLICATION_KEY")
    hmac_key = os.getenv("MYSCRIPT_HMAC_KEY")

    if not application_key or not hmac_key:
        raise ValueError(
            "Missing MyScript keys. Copy backend/.env.example to backend/.env "
            "and paste in your keys from developer.myscript.com."
        )

    # We serialize the body ourselves because the signature must match the
    # bytes we actually send, character for character.
    body_text = json.dumps(build_request_body(strokes))

    response = httpx.post(
        MYSCRIPT_URL,
        content=body_text,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/x-latex,application/json",
            "applicationKey": application_key,
            "hmac": sign_request(body_text, application_key, hmac_key),
        },
        timeout=20,
    )

    if response.status_code != 200:
        raise ValueError(f"MyScript could not read that row: {response.text}")

    return response.text.strip()
