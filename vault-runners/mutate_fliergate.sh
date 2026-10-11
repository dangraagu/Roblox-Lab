#!/usr/bin/env bash
# mutate_fliergate.sh — the mutation gate for the flier gate's assertions (EYECANDY.md, night shift 2026-10-11).
#
#   bash mutate_fliergate.sh
#
# ONE WRITER PER TREE. It mutates real source in place, rebuilds ../robloxemu/build/vault-runners.luau,
# runs the three suites that can see the gate, and puts every file back (checking each sha256). A parallel
# writer in the same tree would measure a mutant; run it in a worktree or scratch copy nobody else is in.
#
# For every mutant it PROVES THE BUNDLE CARRIES IT: the mutated line is found in the rebuilt bundle and the
# original line is gone. A mutation whose target text is not in the source exactly once is refused, not
# skipped. Two CONTROLS (a comment, and a diagnostic nothing reads) must SURVIVE: a sweep that kills
# everything proves the harness is broken, not that the tests are good.
set -u
cd "$(dirname "$0")"
py -3 - <<'PYEOF'
import hashlib, re, subprocess, sys
sys.stdout.reconfigure(line_buffering=True, encoding="utf-8")

GATE = "src/shared/FlierGate.luau"
MAIN = "src/server/Main.server.luau"
CONF = "src/shared/Config.luau"
BUNDLE = "../robloxemu/build/vault-runners.luau"
FILES = [GATE, MAIN, CONF]
orig = {f: open(f, "rb").read() for f in FILES}
sha = {f: hashlib.sha256(orig[f]).hexdigest() for f in FILES}

SUITES = [
    ("spec", "tests/FlierGate.spec.luau", None),
    ("emu:fliergate", "check_vaultrunners_fliergate.luau", "../robloxemu"),
    ("emu:board", "check_vaultrunners_board.luau", "../robloxemu"),
]

def rebuild():
    r = subprocess.run(["py", "-3", "wrap.py", "--game", "../vault-runners", "--out", "build/vault-runners.luau"],
                       cwd="../robloxemu", capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return hashlib.sha256(open(BUNDLE, "rb").read()).hexdigest()[:12]

def run_all():
    hits = []
    for name, path, cwd in SUITES:
        try:
            r = subprocess.run(["luau", path], cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                               errors="replace", timeout=900)
        except subprocess.TimeoutExpired:
            hits.append(name + "(TIMEOUT)")
            continue
        m = re.findall(r"(\d+) passed, (\d+) failed", r.stdout + r.stderr)
        n = int(m[-1][1]) if m else None
        if n is None or n != 0:
            hits.append("%s(%s)" % (name, "ERR" if n is None else n))
    return hits

# (name, file, original text, mutated text, expect "KILLED" | "SURVIVES")
MUTANTS = [
    ("M1 a move is priced at the straight line, not the corridor", GATE,
     "\telseif flat > gate.budgetH + 1e-9 then\n", "\telseif false then -- MUTANT M1\n", "KILLED"),
    ("M2 the bank is never capped (time alone buys the route)", GATE,
     "\t\tmaxBudgetH = flat * burst, maxBudgetUp = up * burst,\n",
     "\t\tmaxBudgetH = math.huge, maxBudgetUp = math.huge, -- MUTANT M2\n", "KILLED"),
    ("M3 floors do not exist: any column is a stairwell", GATE,
     "\treturn math.max(flat, straight), up\n", "\treturn straight, up -- MUTANT M3\n", "KILLED"),
    ("M4 walls do not exist: every cell of the grid is open", GATE,
     "\treturn row ~= nil and row[fx] == false\n", "\treturn row ~= nil and row[fx] ~= nil -- MUTANT M4\n", "KILLED"),
    ("M5 the server ignores the gate's verdict", MAIN,
     "\t\t\tlocal traced = gateOk and verdict == true\n",
     "\t\t\tlocal traced = true -- MUTANT M5\n", "KILLED"),
    ("M12 an end point on a shared edge keeps its zero-width first portal (the funnel over-prices)", GATE,
     "\twhile #cells >= 2 and onSharedEdge(from, cells[1], cells[2]) do table.remove(cells, 1) end\n",
     "\t-- MUTANT M12\n", "KILLED"),
    ("M6 the board's depth reads the floors, not the traced escapes", MAIN,
     "\treturn VaultEnv.deepestCleared(Config, p.traced)\n",
     "\treturn VaultEnv.deepestCleared(Config, p.floors) -- MUTANT M6\n", "KILLED"),
    ("M7 `traced` forgives any distance to the exit", GATE,
     "\tif flat - radius > gate.budgetH + 1e-9 then return false, \"far\" end\n",
     "\tif false then return false, \"far\" end -- MUTANT M7\n", "KILLED"),
    ("M8 a saved traced count is not held to the floors cleared", MAIN,
     "\t\t\t\t\tp.traced[i] = math.clamp(math.floor(v), 1, p.floors[i])\n",
     "\t\t\t\t\tp.traced[i] = math.max(1, math.floor(v)) -- MUTANT M8\n", "KILLED"),
    ("M9 height gained is free (the stairwell is a lift)", GATE,
     "\telseif up > gate.budgetUp + 1e-9 then\n", "\telseif false then -- MUTANT M9\n", "KILLED"),
    ("M10 the wall tolerance is a whole wall thick", CONF,
     "\tWallTolerance = 1.5,\n", "\tWallTolerance = 12, -- MUTANT M10\n", "KILLED"),
    ("M11 a traced escape is not counted (nobody is ever ranked)", MAIN,
     "\t\t\tif traced then\n\t\t\t\tp.traced[a.tierIndex] = math.min(",
     "\t\t\tif false then -- MUTANT M11\n\t\t\t\tp.traced[a.tierIndex] = math.min(", "KILLED"),
    ("C1 CONTROL: a comment is reworded", GATE,
     "-- Twice the signed area of (a, b, c) in the x-z plane.\n",
     "-- Twice the signed area of the triangle a, b, c in the x-z plane. CONTROL C1\n", "SURVIVES"),
    ("C2 CONTROL: the diagnostic nothing reads is not recorded", GATE,
     "\t\tgate.lastReason = reason\n", "\t\t-- CONTROL C2 (lastReason is diagnostics only)\n", "SURVIVES"),
]

def restore():
    for f in FILES:
        open(f, "wb").write(orig[f])
        assert hashlib.sha256(open(f, "rb").read()).hexdigest() == sha[f], f

print("baseline: bundle %s" % rebuild())
base = run_all()
print("baseline suites: %s" % ("ALL GREEN" if not base else "RED " + ", ".join(base)))
if base:
    sys.exit("the baseline is not green; a sweep on top of it means nothing")

wrong = 0
rows = []
try:
    for name, f, old, new, expect in MUTANTS:
        src = orig[f].decode("utf-8")
        nl = "\r\n" if "\r\n" in src else "\n"
        o, n = old.replace("\n", nl), new.replace("\n", nl)
        if src.count(o) != 1:
            restore()
            sys.exit("REFUSED %s: target text found %d times in %s" % (name, src.count(o), f))
        open(f, "wb").write(src.replace(o, n).encode("utf-8"))
        bsha = rebuild()
        bundle = open(BUNDLE, "rb").read().decode("utf-8").replace("\r\n", "\n")
        marker = new.strip("\n").split("\n")[0].strip()
        gone = old.strip("\n").split("\n")[0].strip()
        in_bundle = bundle.count(marker)
        still = bundle.count(old.replace("\r\n", "\n"))
        hits = run_all()
        verdict = "KILLED" if hits else "SURVIVES"
        okay = (verdict == expect) and in_bundle >= 1 and still == 0
        if not okay: wrong += 1
        rows.append((name, verdict, expect, bsha, in_bundle, still, ", ".join(hits) or "-"))
        print("%-8s %s | want %s | bundle %s carries the mutant x%d, original line x%d | %s%s" % (
            verdict, name, expect, bsha, in_bundle, still, ", ".join(hits) or "nothing noticed",
            "" if okay else "   <-- NOT AS EXPECTED"))
        _ = gone
        open(f, "wb").write(orig[f])
finally:
    restore()

final = rebuild()
after = run_all()
print("restored: every source file back to its sha256; bundle %s; suites %s" % (
    final, "ALL GREEN" if not after else "RED " + ", ".join(after)))
killed = sum(1 for r in rows if r[1] == "KILLED" and r[2] == "KILLED")
survived = sum(1 for r in rows if r[1] == "SURVIVES" and r[2] == "SURVIVES")
print("%d mutants killed of %d, %d controls survive of %d" % (
    killed, sum(1 for r in rows if r[2] == "KILLED"), survived, sum(1 for r in rows if r[2] == "SURVIVES")))
if wrong or after:
    sys.exit("mutation gate: %d not as expected" % wrong)
PYEOF
