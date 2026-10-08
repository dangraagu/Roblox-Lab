"""Fail when a game's UI strings use a character Roblox draws as an empty box (or nearly invisible).

    py -3 tools/check_glyphs.py <game> [<game> ...]

Measured in real Studio on 2026-10-09 (labyrint-spill, GothamBold / GothamBlack / SourceSansBold, TextSize 40-48):
  U+2715 ✕  and  U+2630 ☰   render as an empty rectangle (tofu)
  U+2714 ✔  and  U+2716 ✖   render as a near-black emoji, invisible on the dark HUD panels
Every other symbol the games use (→ ▶ ◀ ▲ ▼ ★ ✓ ⬆ ⬇ … — ⚠ ❄ ☕ ⚡ ⭐ ♻ ⛏) rendered. Use "X", "≡" and "✓" instead.

Only string literals in code are checked; comments may name the characters.
"""
import pathlib
import re
import sys

BANNED = {
    0x2715: 'use "X"',
    0x2630: 'use "≡"',
    0x2714: 'use "✓"',
    0x2716: 'use "X"',
}
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')


def code_part(line: str) -> str:
    """The line without a trailing -- comment that is not inside a string."""
    out, i, quote = [], 0, None
    while i < len(line):
        ch = line[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < len(line):
                out.append(line[i + 1]); i += 2; continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch; out.append(ch)
        elif line.startswith("--", i):
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def check(game: str) -> list[str]:
    bad = []
    root = pathlib.Path(game) / "src"
    for f in sorted(root.rglob("*.luau")):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for lit in STRING.findall(code_part(line)):
                for ch in lit:
                    if ord(ch) in BANNED:
                        bad.append(f"{f.as_posix()}:{n}: U+{ord(ch):04X} {ch} ({BANNED[ord(ch)]})")
    return bad


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    bad = []
    for g in sys.argv[1:]:
        bad += check(g)
    sys.stdout.reconfigure(encoding="utf-8")
    for b in bad:
        print(b)
    print(f"check_glyphs: {len(bad)} bad glyph(s) in {', '.join(sys.argv[1:])}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
