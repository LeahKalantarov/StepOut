# StepOut

Handwritten maths tutoring on iPad. The student works through algebra on ruled
paper with an Apple Pencil, and the tutor marks the work and writes back in its
own hand, on the same page.

## How a check works

```
Pencil strokes  ->  MyScript  ->  LaTeX  ->  SymPy  ->  verdict
                                                          |
                                          a model puts it into words
```

The split matters: **SymPy decides whether a step is right, and a language model
only ever explains a verdict that has already been reached.** Marking stays
exact, and the tutor's voice stays cheap and replaceable.

## Running it

The backend has to be running for checks to work.

```bash
cd backend
cp .env.example .env        # add your MyScript keys, and an OpenAI key if you want explanations
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Then open `StepOut/StepOut.xcodeproj` in Xcode and run on an iPad.

The iPad has to reach your Mac over the same Wi-Fi. It looks for the Mac by
name, which you can check with `scutil --get LocalHostName`, and set in
`StepOut/StepOut/CheckService.swift`.

## Where things live

| Path | What it does |
|------|--------------|
| `backend/main.py` | The endpoints the iPad calls |
| `backend/checker/step_checker.py` | Whether each step follows from the last |
| `backend/checker/handwriting.py` | Pen strokes to LaTeX, via MyScript |
| `backend/checker/photo.py` | A photograph of working to lines of maths |
| `backend/checker/review.py` | Lines of maths to a marked verdict |
| `backend/checker/tutor.py` | Puts a verdict into a sentence |
| `backend/checker/lesson.py` | Worked examples when help is asked for |
| `StepOut/StepOut/ContentView.swift` | The page, the marking, and the tutor |
| `StepOut/StepOut/StrokeReader.swift` | Grouping strokes into lines and columns |
| `StepOut/StepOut/StrokeFont.swift` | The tutor's handwriting |

## Tests

```bash
cd backend
python3 test_checker.py
python3 test_photo.py
```

Neither needs an API key or a network — they test the maths and the parsing,
which is the part that has to be right.
