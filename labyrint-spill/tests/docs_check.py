"""The ship-and-market documents, held to the game. Run from labyrint-spill: py -3 tests/docs_check.py

docs/complete-game-standard.md section 4 asks for four things on paper. The luau CLI cannot read a file, so this is
the one gate in Python. It reads the game's own sources (never edits anything) and checks:
  1. README.md "## Store description": one fenced block, at most 1000 characters (UTF-16 units too, as Roblox
     counts), no coloured square or circle emoji (Roblox rejected them, docs/publishing.md), and every number it
     states is the number in the game's source (CLAIMS below: a claim that is no longer in the text fails too, so
     the text and this list move together);
  2. MARKETING.md "## Clip list": 5-10 clips, each 7-15 s, vertical 1080x1920, each with its own staging entry, and
     each marked `exists` only if tools/film_game.py has that scenario for the game (and `new` only if it has not);
  3. EYECANDY.md: the thumbnail shot list says 1920x1080, and the needs-Studio list exists and covers what pass 2
     built (the board, the critters, the session lock, the walk guard);
  4. CLAUDE.md names every gate: each tests/*.spec.luau, each robloxemu check this game owns, and this file.
Prints "docs: N passed, M failed" like the luau gates, and exits 1 on any failure.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
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
    with open(os.path.join(*parts), encoding="utf-8") as fh:
        return fh.read()


def section(md: str, heading: str) -> str:
    """The text under `heading` (a full line) up to the next heading of the same or a higher level."""
    level = len(heading) - len(heading.lstrip("#"))
    lines = md.splitlines()
    out, inside = [], False
    for ln in lines:
        if ln.strip() == heading:
            inside = True
            continue
        if inside and re.match(r"^#{1,%d} " % level, ln):
            break
        if inside:
            out.append(ln)
    return "\n".join(out) if inside else ""


def num(src: str, pattern: str) -> float:
    m = re.search(pattern, src)
    if not m:
        raise SystemExit("docs_check: source pattern not found: " + pattern)
    return float(m.group(1))


SERVER = read(GAME, "src", "server", "MazeGame.server.luau")
BIOMES = read(GAME, "src", "shared", "Biomes.luau")
THEMES = read(GAME, "src", "shared", "Themes.luau")
PERKS = read(GAME, "src", "shared", "PerkDefs.luau")
BOARDCFG = read(GAME, "src", "shared", "BoardConfig.luau")

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
squares = [c for c in store if 0x1F7E0 <= ord(c) <= 0x1F7EB or ord(c) in (0x2B1B, 0x2B1C)]
ok(not squares, "no coloured square or circle emoji (found %r)" % squares)

bands = re.findall(r'id = "(\w+)", from = (\d+), fade = \d+, name = "([^"]+)"', BIOMES)
ok(len(bands) >= 5, "parsed the biome bands from Biomes.luau (%d)" % len(bands))
NUMBER_WORDS = {5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}

# what the pacing model says (tests/Pacing.spec.luau prints "from L51  normal   40.6 ...")
LUAU = os.environ.get("LUAU") or shutil.which("luau") or "luau"  # set LUAU=<path to luau.exe> when it is not on PATH
pacing = {}
try:
    p = subprocess.run([LUAU, "tests/Pacing.spec.luau"], cwd=GAME, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=300)
    for m in re.finditer(r"from L(\d+)\s+normal\s+([\d.]+)", p.stdout):
        pacing[int(m.group(1))] = float(m.group(2))
except (OSError, subprocess.SubprocessError) as e:
    print("  (could not run the pacing model: %s; set LUAU to the luau CLI)" % e)
ok(len(pacing) == len(bands), "the pacing model ran and gave a start minute for every biome (%d of %d)" % (len(pacing), len(bands)))

band_from = {name: int(frm) for _, frm, name in bands}
forge = band_from.get("Lava Forge", -1)

# (regex with ONE number group, the source's number, what it is). Each must match the store text exactly once.
CLAIMS = [
    (r"(\d+) biomes", len(bands), "the number of biomes"),
    (r"Jungle Ruins at level (\d+)", band_from.get("Jungle Ruins"), "where the Jungle Ruins start"),
    (r"Ice Cellar at (\d+)", band_from.get("Ice Cellar"), "where the Ice Cellar starts"),
    (r"Lava Forge at (\d+)", forge, "where the Lava Forge starts"),
    (r"Crystal Caverns at (\d+)", band_from.get("Crystal Caverns"), "where the Crystal Caverns start"),
    (r"Haunted Crypt at (\d+)", band_from.get("Haunted Crypt"), "where the Haunted Crypt starts"),
    (r"Sky Ruins at (\d+)", band_from.get("Sky Ruins"), "where the Sky Ruins start"),
    (r"Astral Labyrinth at (\d+)", band_from.get("Astral Labyrinth"), "where the Astral Labyrinth starts"),
    (r"about (\d+) minutes", round(pacing.get(forge, -100)), "the pacing model's minutes to the Lava Forge (normal player)"),
    (r"(\d+(?:\.\d+)?) s off", num(SERVER, r"OffTime = ([\d.]+)"), "the lava trap's safe window (CONFIG.Traps.OffTime)"),
    (r"last (\d+(?:\.\d+)?) flashing yellow", num(SERVER, r"WarnTime = ([\d.]+)"), "the trap's yellow warning (WarnTime)"),
    (r"then (\d+(?:\.\d+)?) s that kill", num(SERVER, r"OnTime = ([\d.]+)"), "the trap's deadly phase (OnTime)"),
    (r"top speed is (\d+)", num(SERVER, r"MonsterSpeedMax = ([\d.]+)"), "the monsters' top speed (Curve.MonsterSpeedMax)"),
    (r"you walk (\d+)", num(SERVER, r"PlayerWalkSpeed = ([\d.]+)"), "the player's walk speed"),
    (r"(\d+(?:\.\d+)?) s warning", num(BIOMES, r"WarnSeconds = ([\d.]+),"), "the falling hazards' warning (Biomes.Hazards.WarnSeconds)"),
    (r"down for (\d+(?:\.\d+)?) s", num(BIOMES, r"KnockSeconds = ([\d.]+)"), "the knock-down (Biomes.Hazards.KnockSeconds)"),
    (r"(\d+) wall themes", len(re.findall(r'^\s*\{ id = "', THEMES, flags=re.M)), "the number of wall themes"),
    (r"pays (\d+) coins", num(SERVER, r"coinReward = (\d+) \* math\.min"), "the daily reward on day 1"),
    (r"up to (\d+) on day 7", num(SERVER, r"coinReward = (\d+) \* math\.min") * 7, "the daily reward on day 7"),
    (r"torch (\d+)", num(PERKS, r'id = "torch".*?coinPrice = (\d+)'), "the Longer torch's price"),
    (r"extra life (\d+)", num(PERKS, r'id = "shield".*?coinPrice = (\d+)'), "the Extra life's price"),
    (r"speed (\d+)", num(PERKS, r'id = "speed".*?coinPrice = (\d+)'), "the Speed boost's price"),
    (r"minimap (\d+)", num(PERKS, r'id = "minimap".*?coinPrice = (\d+)'), "the Minimap's price"),
    (r"after (\d+) tries", num(SERVER, r"OfferAfterFails = (\d+)"), "when the Hjelp meg guide is offered"),
    (r"top (\d+)", num(BOARDCFG, r"PublicRows = (\d+)"), "the public board's rows"),
]
for pattern, want, what in CLAIMS:
    found = re.findall(pattern, store)
    ok(len(found) == 1, "the store text states %s once (/%s/: %d matches)" % (what, pattern, len(found)))
    if len(found) == 1:
        ok(want is not None and abs(float(found[0]) - float(want)) < 1e-9,
           "%s: the text says %s, the game says %s" % (what, found[0], want))
# the board's title is the one on the board, and the eight names are the game's
title = re.search(r'Title = "([^"]+)"', BOARDCFG).group(1)
ok(title.lower() in store.lower(), "the store text names the board as the board does (%s)" % title)
for _, _, name in bands:
    ok(name in store, "the store text names the %s" % name)
ok("robux" in store.lower() and "nothing costs robux" in store.lower(), "the store text says nothing costs Robux")
ok(re.search(r"^\s*EnableRobux = false,", SERVER, flags=re.M) is not None, "...which is true: RobuxConfig.EnableRobux = false")

# --------------------------------------------------------------------------- 2. MARKETING clip list

marketing = read(GAME, "MARKETING.md")
clips_sec = section(marketing, "## Clip list")
ok(clips_sec != "", 'MARKETING.md has a "## Clip list" section')
ok("1080x1920" in clips_sec and "vertical" in clips_sec.lower(), "it says the clips are vertical 1080x1920")
ok("tools/film_game.py" in clips_sec, "it names tools/film_game.py")
rows = re.findall(r"^\| (\d+) \| `(\w+)` \| (exists|new) \| (\d+)-(\d+) s \|", clips_sec, flags=re.M)
ok(5 <= len(rows) <= 10, "5-10 clips (got %d)" % len(rows))
film = read(ROOT, "tools", "film_game.py")
laby = film[film.find("LABY = {"):film.find("GAMES = {")]
existing = set(re.findall(r'^\s+"(\w+)": \(laby_', laby, flags=re.M))
ok(len(existing) >= 3, "parsed the Labyrinth scenarios in tools/film_game.py (%s)" % sorted(existing))
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
shots = section(eye, "## 9. Thumbnail shot list (for the night Studio session)")
ok(shots != "", "EYECANDY.md has the thumbnail shot list (section 9)")
ok("1920x1080" in shots, "the shot list says the thumbnails are 1920x1080")
needs = section(eye, "## 8. Needs Studio (only real rendering and a real device can judge)")
items = re.findall(r"^(\d+)\. \*\*", needs, flags=re.M) + re.findall(r"^(\d+)\. ", needs, flags=re.M)
ok(len(items) >= 1, "the needs-Studio list has items")
for word in ("TopBoard", "critter", "session lock", "walk guard"):
    ok(word.lower() in needs.lower(), "the needs-Studio list covers the %s" % word)

# --------------------------------------------------------------------------- 4. CLAUDE.md names every gate

claude = read(GAME, "CLAUDE.md")
gates = [f for f in os.listdir(os.path.join(GAME, "tests")) if f.endswith(".spec.luau")]
gates += [f for f in os.listdir(EMU) if (f.startswith("check_labyrint") and f.endswith(".luau") and f != "check_labyrintspill_lib.luau")]
gates += ["check_lighting.luau", "check_secretdoors.luau", "check_themes.luau", "docs_check.py"]
for g in sorted(gates):
    stem = g[: -len(".luau")] if g.endswith(".luau") else g
    short = stem.replace("check_labyrintspill_", "").replace(".spec", "")
    ok(stem in claude or ("`" + short + "`") in claude or (short + ".spec") in claude, "CLAUDE.md names the gate %s" % g)

print("docs: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
