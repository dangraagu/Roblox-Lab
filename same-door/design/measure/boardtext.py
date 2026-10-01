"""How big the hub board's text renders (REVIEW-1, reviewer 2, finding 2). Not game code.

Run:  py -3 design/measure/boardtext.py

The board and plaque labels (src/client/Board.client.luau) either shrink to fit (TextScaled, capped by
a UITextSizeConstraint) or truncate (names). check_samedoor proves every box lies on its Part and every
label is guarded; this script measures what that means for legibility: the size Roblox's TextScaled
would pick for the worst texts, and how much of a long name survives truncation.

Font: this install ships no Gotham file, so Montserrat-Bold (Roblox's own copy, in its content/fonts) is
the stand-in for GothamBold, as reviewer 2 used it. Assumed, NOT verified: that GothamBold renders in
Montserrat here. Two readings of TextSize are reported: as the font's em size (wider, the worst case)
and as the line height. The real look is needs-Studio (EYECANDY.md section 7).
"""
import glob
import os
from PIL import ImageFont

fonts = glob.glob(os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\content\fonts\Montserrat-Bold.ttf"))
assert fonts, "no Montserrat-Bold.ttf in the Roblox install"
FONT = fonts[0]


def em_for(size, reading):
    if reading == "em":
        return size
    f = ImageFont.truetype(FONT, 100)
    asc, desc = f.getmetrics()
    return size * 100 / (asc + desc)  # TextSize is the line height


def width(text, size, reading):
    return ImageFont.truetype(FONT, max(1, round(em_for(size, reading)))).getlength(text)


def wrap(text, size, w, reading):
    lines, cur = [], ""
    for word in text.split():
        cand = (cur + " " + word).strip()
        if width(cand, size, reading) <= w:
            cur = cand
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def scaled(text, maxsize, w, h, wrapped, reading):
    """The largest integer size <= maxsize at which the text fits the box (TextScaled)."""
    for size in range(maxsize, 7, -1):
        if wrapped:
            lines = wrap(text, size, w, reading)
            if all(width(l, size, reading) <= w for l in lines) and len(lines) * size <= h:
                return size, len(lines)
        elif width(text, size, reading) <= w and size <= h:
            return size, 1
    return 8, None


def truncated(text, size, w, reading):
    if width(text, size, reading) <= w:
        return text
    for n in range(len(text), 0, -1):
        if width(text[:n] + "...", size, reading) <= w:
            return text[:n] + "..."
    return "..."


EMPTY_FRIENDS = "None of your friends have opened today's Door yet. They get the exact same dungeon: tell them your time."
EMPTY_PUBLIC = "Nobody has opened today's Door yet. Be the first name on it."
# (label, text, max size, box w, box h, wrapped)
SCALED = [
    ("board title", "Today's board - Door #365", 36, 448, 42, False),
    ("board sub (public)", "Public (the board's prompt shows friends)", 22, 448, 28, False),
    ("board sub (friends)", "Friends (the board's prompt flips it back)", 22, 448, 28, False),
    ("row time", "14:59.99", 22, 92, 28, False),
    ("row medal", "Silver", 20, 82, 24, False),
    ("row SEALED plate", "SEALED", 20, 82, 24, False),
    ("foot: empty friends", EMPTY_FRIENDS, 22, 448, 80, True),
    ("foot: empty public", EMPTY_PUBLIC, 22, 448, 80, True),
    ("foot: partial", "Some friends could not be read just now; the rest are shown.", 22, 448, 80, True),
    ("plaque title", "Yesterday's Keepers", 24, 296, 32, False),
    ("plaque time", "14:59.99", 20, 96, 28, False),
]
NAMES = [("8 chars", "Player12"), ("13 chars", "CoolGamer2012"), ("18 chars", "ABCDEFGHIJKLMNOPQR"), ("20 chars", "ABCDEFGHIJKLMNOPQRST"),
         ("20 lower", "abcdefghijklmnopqrst")]

for reading in ("em", "line"):
    print(f"--- TextSize read as the {reading} size")
    for name, text, mx, w, h, wr in SCALED:
        size, lines = scaled(text, mx, w, h, wr, reading)
        print(f"  {name:22s} max {mx:2d} in {w:3d}x{h:2d}: renders at {size:2d} px" + (f" on {lines} line(s)" if wr else ""))
    for name, text in NAMES:
        print(f"  board name {name:9s} 22 px in 214: {truncated(text, 22, 214, reading)!r}")
        print(f"  plaque name {name:8s} 20 px in 196: {truncated('1. ' + text, 20, 196, reading)!r}")
