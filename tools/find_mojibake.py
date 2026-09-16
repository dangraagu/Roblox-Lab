"""Find text that was decoded as Latin-1 and re-saved as UTF-8, and offer to undo it.

Grow a Crystal's whole HUD shipped reading "🌱 SEEDS" instead of a seedling
emoji. The file is valid UTF-8 - that is what makes it quiet - but what it encodes is the
mojibake, not the character: the bytes for the emoji were once read as Latin-1, turned into
several accented characters, and those were then correctly encoded as UTF-8. Two layers, and no
tool complains.

The test is exact rather than heuristic: a double-encoded file is one whose text, encoded back
to Latin-1, is itself valid UTF-8 and different. That round-trip is precisely the inverse of the
mistake, so a file that passes it was definitely double-encoded, and a file that fails it is
definitely fine.

    py -3 tools/find_mojibake.py            report
    py -3 tools/find_mojibake.py --fix      rewrite the affected files
"""

import argparse
import os
import sys

SKIP_DIRS = {".git", "__pycache__", "node_modules"}
SKIP_PARTS = ("robloxemu/build",)
EXTS = (".luau", ".lua", ".json", ".md", ".txt", ".bat", ".ps1", ".py")

# The codec the bytes were WRONGLY read as. It is cp1252, not latin-1, and the difference is not
# academic: cp1252 maps 0x9F to U+0178 and 0x8C to U+0152, both outside the 0x80-0xFF range that
# a latin-1 assumption looks for. A latin-1 repair therefore stops at the first such character
# and leaves the emoji half-fixed, which is exactly what happened on the first pass here.
MISREAD = "cp1252"


def repair_runs(text):
    """Undo double-encoding sequence by sequence, leaving everything else untouched.

    Repairing the whole file at once does not work: these files also contain characters that
    are NOT Latin-1 (an em dash, a real emoji that survived), and one of those makes the whole
    round-trip throw, so a file full of mojibake reports clean. The first version of this tool
    did exactly that and found nothing.

    So walk maximal runs of Latin-1-encodable characters that are above ASCII, and replace a run
    only when its bytes are themselves valid UTF-8 that decodes to something different. That is
    still exact - a run either decodes or it does not - it is just applied locally.
    """
    def to_byte(ch):
        """The single byte this character came from, or None if it did not come from one.

        cp1252 leaves five byte values undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D). The decoder
        that made this mess passed them through unchanged, so 0x8F became U+008F - a character
        Python's cp1252 codec refuses to encode. Without this fallback the run containing it
        splits in two and neither half is valid UTF-8, so the mojibake survives the repair. That
        is why "TOP MINERS" still read as mojibake after the first cp1252 pass while everything
        around it came out right.
        """
        if ord(ch) < 0x80:
            return None
        try:
            b = ch.encode(MISREAD)
            return b[0] if len(b) == 1 else None
        except UnicodeEncodeError:
            return ord(ch) if 0x80 <= ord(ch) <= 0x9F else None

    def single(ch):
        return to_byte(ch) is not None

    out = []
    i = 0
    changed = False
    n = len(text)
    while i < n:
        if not single(text[i]):
            out.append(text[i])
            i += 1
            continue
        j = i
        while j < n and single(text[j]):
            j += 1
        run = text[i:j]
        try:
            decoded = bytes(to_byte(c) for c in run).decode("utf-8")
        except UnicodeDecodeError:
            decoded = None
        # Refuse a "repair" that produces control characters or replacement characters. Real text
        # never contains C1 controls, so a decode that yields one means the run was not mojibake
        # and this is about to destroy something legitimate. Without this the tool is happy to
        # keep decoding forever and will eventually eat a genuine em dash.
        if decoded is not None and any(
            0x80 <= ord(c) <= 0x9F or c == "�" for c in decoded
        ):
            decoded = None
        if decoded is not None and decoded != run:
            out.append(decoded)
            changed = True
        else:
            out.append(run)
        i = j
    return "".join(out) if changed else None


def double_encoded(path):
    """Return the repaired text if this file contains double-encoded sequences, else None."""
    try:
        text = open(path, "rb").read().decode("utf-8")
    except (UnicodeDecodeError, OSError):
        return None
    return repair_runs(text)


def sample(text, repaired, width=58):
    """The first line that actually differs, before and after."""
    for a, b in zip(text.split("\n"), repaired.split("\n")):
        if a != b:
            return a.strip()[:width], b.strip()[:width]
    return "", ""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fix", action="store_true", help="rewrite the affected files in place")
    ap.add_argument("--root", default=".", help="where to look (default: here)")
    args = ap.parse_args()

    found = []
    for root, dirs, files in os.walk(args.root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        norm = root.replace("\\", "/")
        if any(s in norm for s in SKIP_PARTS):
            continue
        for fn in files:
            if not fn.endswith(EXTS):
                continue
            p = os.path.join(root, fn)
            repaired = double_encoded(p)
            if repaired is not None:
                found.append((p, repaired))

    if not found:
        print("No double-encoded files.")
        return 0

    def show(s):
        """Print without dying on the console's own encoding.

        The repaired text contains the very emoji this tool exists to restore, and a Windows
        console is cp1252. An earlier run raised UnicodeEncodeError HERE, inside the report, and
        took the --fix with it: the diagnosis was right and nothing was written.
        """
        enc = sys.stdout.encoding or "utf-8"
        return s.encode(enc, errors="replace").decode(enc, errors="replace")

    for p, repaired in found:
        text = open(p, "rb").read().decode("utf-8")
        before, after = sample(text, repaired)
        rel = os.path.relpath(p, args.root).replace("\\", "/")
        print("\n%s" % rel)
        print("   now: %s" % show(before))
        print("   was: %s" % show(after))
        if args.fix:
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(repaired)
            print("   FIXED")

    print("\n%d file(s)%s" % (len(found), " repaired" if args.fix else
                              " - re-run with --fix to repair"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
