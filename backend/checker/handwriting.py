"""
Turns Apple Pencil strokes into math text by asking MyScript to read them.

The iPad sends us raw pen coordinates. We forward them to MyScript's
recognition service, which sends back the equation written in LaTeX.
"""

import hashlib
import hmac
import json
import os
import re

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


def build_request_body(strokes, content_type="Math"):
    """
    Package one row of pen strokes the way MyScript expects.

    'strokes' looks like: [{"x": [1, 2, 3], "y": [4, 5, 6]}, ...]
    where each dict is one continuous pen line.

    'content_type' decides which alphabet MyScript reads the row against.
    The same three shapes are "yes" to a reader expecting words and y times e
    times s to one expecting algebra, so we have to say which we want.
    """
    return {
        "contentType": content_type,
        "scaleX": SCALE,
        "scaleY": SCALE,
        "configuration": {
            "lang": "en_US",
            # Critical: we do NOT want MyScript to solve or tidy up the math.
            # Our whole job is catching the student's mistakes, so we need
            # the equation exactly as it was written.
            "math": {"solver": {"enable": False}},
        },
        "strokes": strokes,
    }


def settle_letter_case(latex_text):
    """
    Make a lone capital letter lowercase, so "X" and "x" mean one variable.

    Handwritten x and X are the same shape, so the recognizer picks one at
    random from row to row. SymPy would then treat "X = 4" as introducing a
    brand new variable and call a correct step wrong. In school algebra the
    two never mean different things, so we settle on lowercase.

    Only single standalone letters change. LaTeX commands like \\frac keep
    their spelling because the backslash protects them.
    """
    return re.sub(r"(?<!\\)\b([A-Z])\b", lambda match: match.group(1).lower(), latex_text)


def tidy_spacing(latex_text):
    """
    Close up the gaps the recognizer leaves between characters.

    MyScript hands back "2 x + 5 = 1 3" because it reports one symbol at a
    time. Joining neighbouring digits and pulling a number against its
    variable gives "2x + 5 = 13", which is what the student actually wrote.
    Spaces around + - = are left alone since they aid reading.
    """
    text = re.sub(r"(?<=\d) +(?=\d)", "", latex_text)  # "1 3"  -> "13"
    text = re.sub(r"(?<=\d) +(?=[a-z])", "", text)  # "2 x"  -> "2x"
    return text


# The ways a student might draw "and then". MyScript reads all of these back
# as LaTeX arrow commands.
ARROWS = re.compile(r"\\(?:longrightarrow|rightarrow|Rightarrow|implies|to)\b")


def split_on_arrows(latex_text):
    """
    Break one written line into the steps it holds.

    Not everyone works down the page. Plenty of people write straight across
    it instead — "2x + 5 = 13 -> 2x = 8 -> x = 4" — and that comes back as a
    single string with three equals signs in it. That is not an equation, so
    without this the whole line would fail to parse and be quietly dropped,
    which looks to the student like their work simply vanished.

    Returns a list, usually of one, so a line written the ordinary way passes
    through untouched.
    """
    return [piece.strip() for piece in ARROWS.split(latex_text) if piece.strip()]


def heal_crossed_out_terms(latex_text):
    """
    Undo the fraction bar the recognizer invents from a cross-out.

    When a student strikes through a term, MyScript sees a horizontal line and
    reads it as a division bar with nothing on the other side: crossing out the
    5 in "2x + 5 = 13" comes back as "2x + \\frac{5}{} = 13". Left alone that is
    worse than useless, because SymPy quietly reads the half-empty fraction as
    zero and the line becomes "2x = 13" — a wrong equation we would then judge
    the student against.

    So we put the struck term back. The cross-out is the student's bookkeeping;
    what they are actually claiming shows up on the next line.

    A real fraction always has both halves filled in, so this only ever fires
    on a stray bar.
    """
    text = re.sub(r"\\frac\{([^{}]+)\}\{\}", r"\1", latex_text)  # \frac{5}{} -> 5
    text = re.sub(r"\\frac\{\}\{([^{}]+)\}", r"\1", text)  # \frac{}{3} -> 3
    return re.sub(r"\\frac\{\}\{\}", "", text)  # a bar and nothing else


def ask_myscript(strokes, content_type, accept):
    """
    Send one row of strokes off to be read, and hand back what came home.
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
    body_text = json.dumps(build_request_body(strokes, content_type))

    response = httpx.post(
        MYSCRIPT_URL,
        content=body_text,
        headers={
            "Content-Type": "application/json",
            "Accept": accept,
            "applicationKey": application_key,
            "hmac": sign_request(body_text, application_key, hmac_key),
        },
        timeout=20,
    )

    if response.status_code != 200:
        raise ValueError(f"MyScript could not read that row: {response.text}")

    return response.text.strip()


def read_handwriting(strokes):
    """
    Read one row as algebra, and return the LaTeX for it.

    Example return value: "2x+5=13"
    """
    recognized = ask_myscript(strokes, "Math", "application/x-latex,application/json")
    return tidy_spacing(settle_letter_case(heal_crossed_out_terms(recognized)))


def read_words(strokes):
    """
    Read one row as ordinary writing, and return the words.

    Used when the tutor has asked something and is waiting to be answered.
    Reading that row as algebra would turn "yes" into y times e times s, so
    for those moments we ask MyScript for English instead.
    """
    return ask_myscript(strokes, "Text", "text/plain").strip().lower()
