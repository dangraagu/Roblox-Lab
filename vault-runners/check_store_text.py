"""Vault Runners: the store description gate (docs/complete-game-standard.md section 4).

    py -3 check_store_text.py            # checks README.md next to this file
    py -3 check_store_text.py OTHER.md   # checks another copy (the mutation test uses this)

The store text is the first fenced block under "## The store description" in README.md. Roblox shows it as
the experience's description, so it is held to what the standard asks and to what this game's own review of
the concept brief found false (README.md, the table under the block):
  * at most 1000 characters, counted both as code points and as UTF-16 units (an emoji is one code point
    and two UTF-16 units; whichever way Roblox counts, it fits);
  * no coloured-square emoji;
  * none of the brief's claims the build does not keep: hatching, eggs, levelling pets, closing walls,
    weekly content, a pure rage obby.
The luau CLI cannot read files, which is why this one gate is Python. Exit code 1 on any failure.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "README.md")
text = io.open(path, encoding="utf-8").read()

passed = failed = 0


def ok(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + msg)


m = re.search(r"^## The store description\s*$.*?^```[^\n]*\n(.*?)^```", text, re.S | re.M)
ok(m is not None, "README has a fenced store text under '## The store description'")
store = m.group(1).rstrip("\n") if m else ""

points = len(store)
units = len(store.encode("utf-16-le")) // 2
print("  store text: %d characters (%d UTF-16 units), %d lines" % (points, units, store.count("\n") + 1))
ok(0 < points <= 1000, "at most 1000 characters (%d)" % points)
ok(units <= 1000, "at most 1000 UTF-16 units (%d)" % units)

SQUARES = [chr(c) for c in range(0x1F7E5, 0x1F7EC)] + ["⬛", "⬜", "■", "□", "▪",
                                                       "▫", "◻", "◼", "◽", "◾"]
found = sorted({ch for ch in store if ch in SQUARES})
ok(not found, "no coloured-square emoji (%s)" % " ".join("U+%04X" % ord(c) for c in found))

FALSE_CLAIMS = [
    (r"\bhatch", "pets are bought, not hatched"),
    (r"\beggs?\b", "there are no eggs"),
    (r"level[ -]?up|levels? up", "pets never level"),
    (r"closing walls", "nothing closes in; the collapse rises"),
    (r"weekly", "no weekly content is promised by anybody"),
    (r"rage[ -]?obby", "the obby is the climb out of each storey; most of a run is maze"),
]
for pattern, why in FALSE_CLAIMS:
    hit = re.search(pattern, store, re.I)
    ok(hit is None, "no false claim %r (%s)%s" % (pattern, why, (": " + hit.group(0)) if hit else ""))

print("vault-runners store text: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
