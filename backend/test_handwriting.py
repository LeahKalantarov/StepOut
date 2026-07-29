"""
Checks that MyScript accepts our keys and reads strokes.

Run it with:  python test_handwriting.py

The strokes below are drawn by hand in code, not written on an iPad, so the
recognized text may be imperfect. What matters is that the request is
accepted — that proves our keys and HMAC signature are correct.
"""

from checker.handwriting import read_handwriting


def straight_line(x_start, y_start, x_end, y_end, points=12):
    """Make one pen stroke that goes in a straight line."""
    xs = []
    ys = []
    for i in range(points):
        fraction = i / (points - 1)
        xs.append(x_start + (x_end - x_start) * fraction)
        ys.append(y_start + (y_end - y_start) * fraction)
    return {"x": xs, "y": ys}


# A rough attempt at writing "1=1"
strokes = [
    straight_line(10, 10, 10, 40),  # the first 1
    straight_line(25, 20, 45, 20),  # top bar of the equals sign
    straight_line(25, 30, 45, 30),  # bottom bar of the equals sign
    straight_line(60, 10, 60, 40),  # the second 1
]

print("Sending 4 strokes to MyScript...")
result = read_handwriting(strokes)
print("MyScript read it as:", repr(result))
