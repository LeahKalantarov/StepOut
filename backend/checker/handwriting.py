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


# What a page of school algebra is allowed to contain.
#
# The reader is willing to see anything by default — every letter of the
# alphabet, and a good deal besides — and many written symbols look alike. So
# "- 2 - 2" under both sides of an equation came back as "+ 2 + z", and a
# jotting came back as an emoji. Neither is a thing anybody writes while
# solving for x, and the reader only offered them because nothing said it
# could not.
#
# Narrowing the alphabet is MyScript's own answer to this. A 2 misread as a 6
# is a genuinely hard problem and this will not fix it, but a 2 misread as a z
# stops being possible at all.
#
# The only letter is x, and dropping y from it was worth more than it sounds. A
# handwritten 4 with an open top is a y, and the reader was taking it as one:
# "x + 4 = 11" written out again halfway down the page came back as
# "x + y = 11", which is not the question restated, so the fresh attempt was
# never recognised as one and a correct second go stayed buried under the first
# wrong one. Every question this app sets is in x, so y bought nothing and cost
# that.
#
# Anything a student writes in words belongs on a row that fails to parse as
# algebra, and those rows are re-read as text with the whole alphabet available.
ALGEBRA_GRAMMAR = """
symbol = 0 1 2 3 4 5 6 7 8 9 x + - = / . < >
leftpar = (
rightpar = )
character ::= identity(symbol)
fractionless ::= identity(character)
               | fence(fractionless, leftpar, rightpar)
               | hpair(fractionless, fractionless)
               | superscript(character, fractionless)
               | sqrt(fractionless)
fractionable ::= identity(character)
               | fence(fractionable, leftpar, rightpar)
               | hpair(fractionable, fractionable)
               | fraction(fractionless, fractionless)
               | superscript(character, fractionable)
               | sqrt(fractionable)
expression ::= identity(character)
             | fence(expression, leftpar, rightpar)
             | hpair(expression, expression)
             | fraction(fractionable, fractionable)
             | superscript(character, expression)
             | sqrt(expression)
start(expression)
""".strip()


def narrowed_alphabet():
    """
    Whether to hold the reader to school algebra.

    Behind a switch because it changes what the recognizer is capable of
    seeing, and a bad day with it should cost one line in .env rather than a
    code change: STEPOUT_WIDE_ALPHABET=1 hands the whole alphabet back.
    """
    return os.getenv("STEPOUT_WIDE_ALPHABET", "").strip() not in ("1", "true", "yes")


def build_request_body(strokes, content_type="Math"):
    """
    Package one row of pen strokes the way MyScript expects.

    'strokes' looks like: [{"x": [1, 2, 3], "y": [4, 5, 6]}, ...]
    where each dict is one continuous pen line.

    'content_type' decides which alphabet MyScript reads the row against.
    The same three shapes are "yes" to a reader expecting words and y times e
    times s to one expecting algebra, so we have to say which we want.
    """
    # Critical: we do NOT want MyScript to solve or tidy up the math.
    # Our whole job is catching the student's mistakes, so we need
    # the equation exactly as it was written.
    math = {"solver": {"enable": False}}

    # Only algebra gets the narrow alphabet. A row read as words is a row that
    # already failed to be algebra, and that is where a student writes "I need
    # help" — which needs every letter there is.
    if content_type == "Math" and narrowed_alphabet():
        math["customGrammarContent"] = ALGEBRA_GRAMMAR

    return {
        "contentType": content_type,
        "scaleX": SCALE,
        "scaleY": SCALE,
        "configuration": {"lang": "en_US", "math": math},
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

    The variable has to be a letter standing on its own. The tutor's own
    sentences come through here too, and a rule that pulls a number against
    any letter after it turns "40 by" into "40by" — which is not a word, and
    is then drawn onto the page that way for the student to puzzle over.
    """
    text = re.sub(r"(?<=\d) +(?=\d)", "", latex_text)  # "1 3"  -> "13"
    text = re.sub(r"(?<=\d) +(?=[a-z]\b)", "", text)  # "2 x"  -> "2x", "40 by" left
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


def without_arrows(latex_text):
    """
    Take the arrows out and leave the line otherwise as it was.

    Not every arrow means "and then". A student expanding two brackets draws
    loops from each term to the ones it multiplies, and those come back as
    arrows sitting in the middle of a single equation. Split on, they cut

        (x - 3)(x - 3) = 16

    into a bracket and a stray "= 16", neither of which is an equation, and a
    page with working all over it is reported as having nothing on it.
    """
    return re.sub(r"\s+", " ", ARROWS.sub(" ", latex_text)).strip()


# The environments MyScript reaches for when writing sits one line above
# another. The column spec after \begin{array} is optional and thrown away with
# the rest of the wrapper.
STACKS = r"(?:matrix|array|aligned|gathered|cases|split|[pbvBV]matrix)"

STACKED = re.compile(
    r"\\begin\{" + STACKS + r"\}(?:\{[^}]*\})?(.*?)\\end\{" + STACKS + r"\}",
    re.DOTALL,
)

# What separates one row of such an environment from the next.
STACK_BREAK = re.compile(r"\\\\")


def rows_stacked_in(latex_text):
    """
    Read a stack of writing as the separate lines it is.

    Two things written close together, one under the other, are sometimes
    returned as two rows of a matrix rather than as two lines. Restating the
    question and jotting "- 4  - 4" beneath it does it every time, and comes
    back as

        \\begin{matrix} x^2 + 4 = 20 \\\\ - 4 - 4 \\end{matrix}

    That is nobody's idea of a matrix. It parses as neither an equation nor an
    annotation, so the restated question is not recognised as restating
    anything, the fresh attempt it opens is never opened, and the page is still
    being marked against the mistake made at the top of it. Which is the exact
    opposite of what writing the question out again was for.

    Returns a list, usually of one, so an ordinary line passes through as it is.
    """
    unwrapped = STACKED.sub(lambda found: found.group(1), latex_text)

    if unwrapped == latex_text:
        return [latex_text]

    rows = [row.strip() for row in STACK_BREAK.split(unwrapped)]

    return [row for row in rows if row] or [latex_text]


# Marks the recognizer draws over a symbol. A pen stroke that strays above the
# line — the tail of a y from the row before, a comma, a wobble joining two
# brackets — comes back as one of these wrapped around perfectly ordinary work.
DECORATIONS = (
    "widearc",
    "overarc",
    "wideparen",
    "overparen",
    "widehat",
    "widetilde",
    "overline",
    "underline",
    "overrightarrow",
    "overleftarrow",
    "underbrace",
    "overbrace",
    "mathring",
    "hat",
    "tilde",
    "bar",
    "vec",
    "dot",
    "ddot",
    "acute",
    "grave",
    "check",
    "breve",
)

DECORATION = re.compile(r"\\(?:" + "|".join(DECORATIONS) + r")\s*\{")


# What the recognizer answers with when a mark on the page means nothing at
# all — a slip of the pen, a rest of the hand, the tail of a letter from the
# row above. SymPy turns every one of these into a variable and multiplies the
# line by it, exactly as it did with \widearc, so a stray dot is the difference
# between correct work and a cross in the margin.
NOISE = re.compile(
    r"\\(?:sim|backslash|prime|ldots|dots|cdots|vdots|angle|parallel|perp"
    r"|square|therefore|because|circ|degree|star|ast|bullet|dagger)\b\s*"
)


def without_noise(latex_text):
    """
    Drop the marks that stand for nothing.
    """
    return re.sub(r"\s+", " ", NOISE.sub(" ", latex_text)).strip()


def undecorate(latex_text):
    """
    Take the recognizer's decorative marks off, keeping what was underneath.

    These are the difference between a correct line and a wrong one. SymPy has
    no idea what \\widearc is, so it reads the name as a variable and multiplies
    by it: a student who wrote

        (x - 3)(x - 3) + 1 = 17

    had it read back as widearc*(x - 3)*(x - 3) + 1 = 17, which is not the
    equation they were given, and was told their working was wrong three times
    over while the line on the page was right all along.

    Nothing at this level of algebra is written with an accent over it, so a
    decoration is always a stray pen mark and never something meant.
    """
    while True:
        found = DECORATION.search(latex_text)

        if not found:
            return latex_text

        # Walk to the brace that closes this one rather than the first one
        # along, or a decoration wrapped round a fraction loses half of it.
        opened = 1
        at = found.end()

        while at < len(latex_text) and opened:
            if latex_text[at] == "{":
                opened += 1
            elif latex_text[at] == "}":
                opened -= 1
            at += 1

        # Never closed. Better to hand back what came in than to cut the line
        # off at a brace that was never there.
        if opened:
            return latex_text

        inside = latex_text[found.end() : at - 1]
        latex_text = latex_text[: found.start()] + inside + latex_text[at:]


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
    return tidy_spacing(
        settle_letter_case(heal_crossed_out_terms(undecorate(without_noise(recognized))))
    )


# A lone handwritten x, read by something expecting words, comes back as a
# printed ballot cross about as often as it comes back as the letter. None of
# these is a character anybody writes into a question by hand, and the letter
# they are standing in for is the one this whole app is about: "explain what x
# is??" reached the tutor as "explain what ✗ is??".
#
# The multiplication sign is deliberately not here. That one really is meant
# when it turns up, and "2 × 3" is not asking about a variable.
BALLOT_CROSSES = str.maketrans({"✗": "x", "✘": "x", "✕": "x", "╳": "x", "⤫": "x"})


def read_words(strokes):
    """
    Read one row as ordinary writing, and return the words.

    Used when the tutor has asked something and is waiting to be answered.
    Reading that row as algebra would turn "yes" into y times e times s, so
    for those moments we ask MyScript for English instead.
    """
    words = ask_myscript(strokes, "Text", "text/plain").strip().lower()
    return words.translate(BALLOT_CROSSES)


# LaTeX commands that stand for something a student would simply write. Longer
# spellings come first: replacing \ge before \geq would leave a stray q behind.
WRITTEN_SYMBOLS = {
    r"\geq": ">=",
    r"\leq": "<=",
    r"\neq": "!=",
    r"\ge": ">=",
    r"\le": "<=",
    r"\ne": "!=",
    r"\cdot": "*",
    r"\times": "*",
    r"\div": "/",
    r"\pm": "+/-",
    # The printed characters too, not only the LaTeX spellings of them. The
    # tutor's own sentences come through here, and a model asked about the
    # quadratic formula types a real ± — which the stroke font cannot draw,
    # so it would come out as a gap in the middle of the formula.
    "\u00b1": "+/-",  # ±
    "\u00f7": "/",  # ÷
    "\u00d7": "*",  # ×
    "\u2212": "-",  # − proper minus, not a hyphen
    "\u22c5": "*",  # ⋅
    "\u00b7": "*",  # ·
    "\u221a": "sqrt",  # √
    # Typographic characters a model reaches for without thinking. The stroke
    # font has no glyph for any of them, so each would come out as a gap in
    # the middle of a word.
    "\u2019": "'",  # ’
    "\u2018": "'",  # ‘
    "\u201c": '"',  # “
    "\u201d": '"',  # ”
    "\u2014": "-",  # —
    "\u2013": "-",  # –
    "\u2026": "...",  # …
}


def bracket(part):
    """
    Wrap a piece of a fraction in brackets, unless it is a single symbol that
    cannot be misread without them.
    """
    part = part.strip()
    return part if len(part) == 1 else f"({part})"


def as_written(latex_text):
    """
    Turn MyScript's LaTeX back into maths the way it looked on the page.

    Everything downstream of recognition is for people. The message under a
    cross is read by the student, the same text is handed to a language model
    that has been told never to write LaTeX, and it goes back onto the page in
    a stroke font that has no idea what a backslash is. LaTeX reaching any of
    those is a bug, and it did: a mis-factored line came back as

        \\left( x - 3 \\right) \\left( x - 3 \\right) = 0

    and that is what the student was shown.

    The LaTeX itself is still what we parse with — SymPy wants it, and it
    carries structure that plain text loses. This is only the reading copy.
    """
    # \left and \right are sizing hints wrapped around brackets that are
    # already in the text.
    text = re.sub(r"\\left\s*|\\right\s*", "", latex_text)

    # Innermost fractions first, so a nested one unwraps a layer at a time.
    while True:
        unwrapped = re.sub(
            r"\\frac\{([^{}]*)\}\{([^{}]*)\}",
            lambda match: f"{bracket(match.group(1))}/{bracket(match.group(2))}",
            text,
        )

        if unwrapped == text:
            break

        text = unwrapped

    text = re.sub(r"\\sqrt\{([^{}]*)\}", r"sqrt(\1)", text)

    for command, symbol in WRITTEN_SYMBOLS.items():
        text = text.replace(command, symbol)

    # A subscript here is nearly always a word that was read as algebra —
    # "yes" comes back as y_{e s} — so close it up rather than lose the word.
    text = re.sub(r"\s*_\{([^{}]*)\}", lambda match: match.group(1).replace(" ", ""), text)

    # Powers keep their braces. The stroke font raises whatever follows a ^,
    # braces and all, so x^{n+1} writes correctly; a single digit reads better
    # without them.
    text = re.sub(r"\s*\^\s*\{(\w)\}", r"^\1", text)
    text = re.sub(r"\s*\^\s*", "^", text)

    # Whatever still carries a backslash is recognizer noise. A stray pen mark
    # comes back as \sim or \backslash, and neither means anything to anyone.
    text = re.sub(r"\\[a-zA-Z]+\s*", "", text)
    text = text.replace("\\", "")

    text = tidy_spacing(re.sub(r"\s+", " ", text).strip())

    # Brackets sit against what they hold, and against each other. Dropping
    # \left and \right leaves gaps where the commands used to be, and
    # "( x - 3 ) ( x - 3 )" is not how anybody writes it down.
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    text = re.sub(r"\)\s+\(", ")(", text)

    return text.strip()
