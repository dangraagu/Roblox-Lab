"""The ship-and-market documents, held to the game. Run from fork-tower: py -3 tests/docs_check.py

docs/complete-game-standard.md section 4 asks for things on paper, and the luau CLI cannot read a file, so this is
the one gate in Python (labyrint-spill's tests/docs_check.py is the model). It reads the game's own sources and
docs, never edits anything, and checks:
  1. README.md "## Store description": one fenced block, at most 1000 characters (UTF-16 units too, as Roblox
     counts), no coloured square or circle emoji (Roblox rejected them, docs/publishing.md), it says the game is in
     Norwegian (every sign and the inscription are), and every number it states is the number in the game's source
     (CLAIMS below: a claim that is no longer in the text fails too, so the text and this list move together);
  2. MARKETING.md "## Clip list": 5-10 clips, each 7-15 s, vertical 1080x1920, each with its own staging entry,
     and each marked `exists` only if tools/film_game.py has that scenario for Fork Tower (and `new` otherwise);
  3. EYECANDY.md: the thumbnail shot list says 1920x1080, and the needs-Studio list covers what pass 2 built (the
     board, the lane spawn, the brag crown);
  4. CLAUDE.md names every gate: each tests/*.spec.luau, tests/world.check.luau, each robloxemu/check_forktower*
     check, and this file.
Prints "docs: N passed, M failed" like the luau gates, and exits 1 on any failure.
"""

from __future__ import annotations

import os
import re
import sys

GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(GAME)
EMU = os.path.join(ROOT, "robloxemu")

passed, failed = 0, 0


def ok(cond: bool, msg: str) -> None:
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL:", msg)


def read(*parts: str) -> str:
    path = os.path.join(*parts)
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def section(md: str, heading: str) -> str:
    """The text under `heading` (a full line) up to the next heading of the same or a higher level."""
    level = len(heading) - len(heading.lstrip("#"))
    out, inside = [], False
    for ln in md.splitlines():
        if ln.strip() == heading:
            inside = True
            continue
        if inside and re.match(r"^#{1,%d} " % level, ln):
            break
        if inside:
            out.append(ln)
    return "\n".join(out) if inside else ""


def num(src: str, pattern: str) -> float:
    m = re.search(pattern, src, flags=re.S)
    if not m:
        raise SystemExit("docs_check: source pattern not found: " + pattern)
    return float(m.group(1))


CONFIG = read(GAME, "src", "shared", "Config.luau")
ok(CONFIG != "", "read src/shared/Config.luau")

# --------------------------------------------------------------------------- 1. README store description

readme = read(GAME, "README.md")
store_sec = section(readme, "## Store description")
ok(store_sec != "", 'README.md has a "## Store description" section')
blocks = re.findall(r"```[a-z]*\n(.*?)\n```", store_sec, flags=re.S)
ok(len(blocks) == 1, "the store description is one fenced block (got %d)" % len(blocks))
store = blocks[0] if blocks else ""
utf16 = len(store.encode("utf-16-le")) // 2
print("  store description: %d characters, %d UTF-16 units" % (len(store), utf16))
ok(0 < len(store) <= 1000 and utf16 <= 1000, "at most 1000 characters (got %d, %d UTF-16 units)" % (len(store), utf16))
squares = [c for c in store if 0x1F7E0 <= ord(c) <= 0x1F7EB or ord(c) in (0x2B1B, 0x2B1C, 0x25A0, 0x25A1)]
ok(not squares, "no coloured square or circle emoji (found %r)" % squares)
ok("norwegian" in store.lower(), "the store text says the game's text is in Norwegian (the inscription is)")

crown_block = CONFIG[CONFIG.find("CrownTiers = {"):CONFIG.find("BragCrown =")]
crowns = [int(x) for x in re.findall(r"summits = (\d+)", crown_block)]
ok(len(crowns) >= 4 and crowns[0] == 0, "parsed Config.Env.CrownTiers (%s)" % crowns)
env_block = CONFIG[CONFIG.find("Bands = {"):CONFIG.find("Layers = {")]
bands = re.findall(r'^\s+name = "([^"]+)", emoji = ', env_block, flags=re.M)
ok(len(bands) >= 5, "parsed the environment bands (%d)" % len(bands))

# (regex with ONE number group, the source's number, what it is). Each must match the store text exactly once.
CLAIMS = [
    (r"(\d+) floors", num(CONFIG, r"Config\.Tower = \{.*?Floors = (\d+)"), "the floors in a run (Config.Tower.Floors)"),
    (r"(\d+(?:\.\d+)?) seconds to read", num(CONFIG, r"ReadSeconds = ([\d.]+)"), "the read's price (Config.Fork.ReadSeconds)"),
    (r"from floor (\d+)", num(CONFIG, r"LiarFromFloor = (\d+)"), "where the warden may start to lie (Config.Fork.LiarFromFloor)"),
    (r"(\d+) worlds", len(bands), "the number of environment bands (Config.Env.Bands)"),
    (r"at least (\d+) seconds of warning", num(CONFIG, r"MinTelegraphSeconds = ([\d.]+)"), "a hazard's least warning (Config.Hazards.MinTelegraphSeconds)"),
    (r"rarer crowns at (\d+),", crowns[1] if len(crowns) > 1 else None, "the first rarer crown (Config.Env.CrownTiers)"),
    (r"rarer crowns at \d+, (\d+) and", crowns[2] if len(crowns) > 2 else None, "the second rarer crown, the brag"),
    (r"and (\d+) summits", crowns[3] if len(crowns) > 3 else None, "the rarest crown, the long-term goal"),
    (r"top (\d+)", num(CONFIG, r"PublicRows = (\d+)"), "the public board's rows (Config.Board.PublicRows)"),
]
for pattern, want, what in CLAIMS:
    found = re.findall(pattern, store)
    ok(len(found) == 1, "the store text states %s once (/%s/: %d matches)" % (what, pattern, len(found)))
    if len(found) == 1:
        ok(want is not None and abs(float(found[0]) - float(want)) < 1e-9,
           "%s: the text says %s, the game says %s" % (what, found[0], want))

codes_block = CONFIG[CONFIG.find("Config.Codes = {"):]
codes_block = codes_block[:codes_block.find("\n}")]
codes = set(re.findall(r'\["([A-Z0-9]+)"\]', codes_block))
ok(len(codes) >= 3, "parsed Config.Codes (%s)" % sorted(codes))
named = set(re.findall(r"\b[A-Z][A-Z0-9]{3,}\b", store)) - {"BUILD", "REVEAL", "TOPPLISTE"}
ok(len(named & codes) >= 2, "the store text names some of the public codes (%s)" % sorted(named & codes))
ok(not (named - codes - {"FORK", "TOWER"}), "every code it names is a real, public one (%s)" % sorted(named - codes))
ok("costs robux" in store.lower(), "the store text says nothing costs Robux")
ok("Config.Passes" not in CONFIG and "Passes = {" not in CONFIG, "...which is true: Config has no gamepasses")

# --------------------------------------------------------------------------- 2. MARKETING clip list

marketing = read(GAME, "MARKETING.md")
ok(marketing != "", "MARKETING.md exists")
clips_sec = section(marketing, "## Clip list")
ok(clips_sec != "", 'MARKETING.md has a "## Clip list" section')
ok("1080x1920" in clips_sec and "vertical" in clips_sec.lower(), "it says the clips are vertical 1080x1920")
ok("tools/film_game.py" in clips_sec, "it names tools/film_game.py")
rows = re.findall(r"^\| (\d+) \| `(\w+)` \| (exists|new) \| (\d+)-(\d+) s \|", clips_sec, flags=re.M)
ok(5 <= len(rows) <= 10, "5-10 clips (got %d)" % len(rows))
film = read(ROOT, "tools", "film_game.py")
games = re.search(r"^GAMES = \{(.*?)\}", film, flags=re.M)
fork_key = None
if games:
    for k, v in re.findall(r'"(\w+)": (\w+)', games.group(1)):
        if "fork" in k.lower():
            fork_key = v
existing = set()
if fork_key:
    block = film[film.find(fork_key + " = {"):]
    block = block[:block.find("\n}")]
    existing = set(re.findall(r'^\s+"(\w+)": ', block, flags=re.M))
print("  tools/film_game.py: Fork Tower scenarios %s" % (sorted(existing) if fork_key else "none (no Fork Tower entry in GAMES)"))
staging = section(clips_sec, "### Staging, clip by clip")
ids = [r[1] for r in rows]
ok(len(set(ids)) == len(ids), "every clip has its own name")
for n, cid, status, lo, hi in rows:
    ok(7 <= int(lo) <= int(hi) <= 15, "clip %s (%s) is 7-15 s (%s-%s)" % (n, cid, lo, hi))
    ok((status == "exists") == (cid in existing),
       "clip %s is marked %s, and tools/film_game.py %s it" % (cid, status, "has" if cid in existing else "does not have"))
    ok(re.search(r"^%s\. \*\*`%s`\*\*" % (n, cid), staging, flags=re.M) is not None, "clip %s has its staging entry" % cid)

# --------------------------------------------------------------------------- 3. EYECANDY lists

eye = read(GAME, "EYECANDY.md")
shots = section(eye, "## 11. Thumbnail shot list (for the night Studio session)")
ok(shots != "", "EYECANDY.md has the thumbnail shot list (section 11)")
ok("1920x1080" in shots, "the shot list says the thumbnails are 1920x1080")
needs = section(eye, "## 10. Needs Studio (only real rendering and a real device can judge)")
items = re.findall(r"^(\d+)\. ", needs, flags=re.M)
ok(len(items) >= 1, "the needs-Studio list has items (%d)" % len(items))
for word in ("TopBoard", "LaneSpawn", "Iskronen"):
    ok(word.lower() in needs.lower(), "the needs-Studio list covers %s" % word)

# --------------------------------------------------------------------------- 4. CLAUDE.md names every gate

claude = read(GAME, "CLAUDE.md")
gates = [f for f in os.listdir(os.path.join(GAME, "tests")) if f.endswith(".spec.luau") or f.endswith(".check.luau")]
gates += [f for f in os.listdir(EMU) if f.startswith("check_forktower") and f.endswith(".luau")]
gates += ["docs_check.py"]
for g in sorted(gates):
    stem = g[: -len(".luau")] if g.endswith(".luau") else g
    ok(stem in claude, "CLAUDE.md names the gate %s" % g)

print("docs: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
