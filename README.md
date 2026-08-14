# StepOut

An iPad tutor for handwritten algebra. You photograph your homework, work
through it in your own handwriting with an Apple Pencil, and it marks each step
as you go — stopping you at the line where you went wrong rather than at the
answer, and teaching the idea you were missing.

Written by hand, on paper, is how algebra is actually done. StepOut tries not to
change that. There is no equation editor and nothing to type: the tutor writes
back onto the same page you are working on, stroke by stroke, in the margin
beside your working.

## What it does

- **Reads a photo of any page** — a worksheet, a textbook, your own revision
  notes — and asks what you want done with it. Copy the questions out, explain
  the page, or set fresh practice on what it covers. You answer in handwriting
  or typed, whichever is nearer.
- **Marks your working line by line**, in your own handwriting, and rings the
  step that went wrong.
- **Offers help in writing.** It asks "want a hand?" on the page; you write
  "yes" (or "yeah", or a tick) and it teaches the concept with a worked example.
- **Answers questions you write down.** Mark a line with a `*` or a `?` and it
  replies underneath.
- **Follows how people actually write** — crooked lines, arrows between steps,
  crossings-out, a second attempt in the space to the right.

## How it works

An iPadOS app in SwiftUI and PencilKit, talking to a Python service that does
the reading, the checking and the teaching.

```
Apple Pencil strokes
   → grouped into lines and columns          (StrokeReader.swift)
   → MyScript, which reads them as LaTeX     (checker/handwriting.py)
   → SymPy, which checks each step           (checker/step_checker.py)
   → an LLM, which explains a wrong step     (checker/tutor.py, lesson.py)
   → written back onto the page by hand      (StrokeFont.swift)
```

Four decisions did most of the work:

**Steps are compared by their solutions, not by their equations.** The obvious
way to check a step is to ask whether it is equivalent to the one above it. That
works until it doesn't: factorising `x² − 9 = 0` into `(x − 3)(x + 3) = 0` and
then writing `x = 3` is not an equivalent equation, but it is exactly right, and
marking it wrong teaches a student to distrust the thing that is meant to be
teaching them. So each line is turned into the set of values that satisfy it,
and consecutive sets are compared. That distinguishes narrowing to one case
(fine, and incomplete — "you've found 1 of the 2 answers") from quietly losing a
root (wrong), and it catches invented solutions from squaring both sides.

**Nothing unverified is ever written on the page.** The model that explains
mistakes also invents a worked example to teach from, and models get arithmetic
wrong. Every example it produces is solved back through the same SymPy checker
before a single stroke is drawn, and one that doesn't hold up is thrown away and
asked for again. Questions set from a photo get the same treatment: anything
that won't parse, has no unknown, or has no real answer is dropped rather than
shown — asked to teach the discriminant, a model will dutifully set a question
with a negative one, and "no real solutions" is a sentence rather than something
you can write on a line and have marked. Half a worksheet you can trust beats
all of one you can't.

**Handwriting is clustered, not gridded.** The first version assigned strokes to
ruled lines by their vertical position, which works only if you write like a
typesetter. Now strokes are grouped by proximity relative to their own height,
then split into columns where there's a wide horizontal gap — so a page with a
second attempt written beside the first is read as two pieces of work rather
than one confused one.

**A page is a page, not a transcript.** Students restart. When the original
question reappears further down, that's the start of a fresh attempt, so the
page is split at those points and each attempt is checked on its own. The
verdict is the best one, which is why crossing out a mess and redoing it
correctly is rewarded rather than punished.

The tutor's writing is drawn with [Hershey fonts](https://en.wikipedia.org/wiki/Hershey_fonts),
single-stroke vector letterforms from the 1960s that were designed to be drawn
by a plotter. Because each glyph is a path rather than a filled shape, it can be
animated as it's written, which is what makes the tutor look like it is writing
rather than pasting.

## Running it

### The backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env      # add your MyScript keys and OpenAI key
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

MyScript keys come from [developer.myscript.com](https://developer.myscript.com);
the OpenAI key from [platform.openai.com](https://platform.openai.com/api-keys).
Without the OpenAI key everything still works — it marks the step plainly
instead of teaching through it, and photo upload is unavailable.

### The app

Open `StepOut/StepOut.xcodeproj` in Xcode and run it on an iPad. Keep the
project out of iCloud Drive — Xcode and iCloud sync fight over the build folder
and you end up building half-synced files.

The app finds the server through `StepOutServer` in `Info.plist`. Left empty it
falls back to the Mac on the same Wi-Fi (`http://<your-mac>.local:8000`, which
you can check with `scutil --get LocalHostName`). Paste a hosted https address
there and the app works anywhere.

### Hosting

`render.yaml` deploys the backend to [Render](https://render.com) from this
repository. The three API keys are set in the dashboard rather than in the file,
since the file is public. Put the resulting address into `StepOutServer` and the
app no longer needs the Mac.

### Tests

```bash
cd backend && python test_checker.py
```

111 assertions over the checker: linear and quadratic working, invented and lost
solutions, identities and contradictions, restarts, mis-copied questions, which
questions are safe to set from a photo, and turning what the recognizer returns
into something readable.
