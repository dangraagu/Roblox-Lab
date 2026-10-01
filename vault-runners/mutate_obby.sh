#!/usr/bin/env bash
# mutate_obby.sh — the mutation gate for the obby's assertions (REVIEW-4 §7, REVIEW-5 §4).
#
#   bash mutate_obby.sh
#
# RUN IT ON A SCRATCH COPY. It mutates real source in place (and puts it back, and checks the
# sha256 of every file it touched), and a parallel writer in the same tree would measure a mutant
# (feedback: parallel mutators contaminate). So:
#
#   S=$(mktemp -d); cp -r ../vault-runners "$S/"; mkdir "$S/robloxemu"
#   cp -r ../robloxemu/emu ../robloxemu/wrap.py ../robloxemu/check_vaultrunners_*.luau "$S/robloxemu/"
#   mkdir "$S/robloxemu/build"; (cd "$S/vault-runners" && bash mutate_obby.sh)
#
# Every assertion added for the obby is only worth what it CATCHES. This applies each mutation (and
# REFUSES a mutation whose target text is not in the file exactly once — a gate whose mutations
# silently stopped applying reports every one of them as a survivor, or worse, as nothing at all),
# rebuilds the bundle, runs every suite that can see the obby, records which noticed, and puts the
# file back.
#
# Two CONTROLS are included on purpose. A sweep that kills everything proves the harness is
# broken, not that the tests are good.
set -u
cd "$(dirname "$0")"
LUAU="/c/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe"
export LUAU
py -3 - <<'PYEOF'
import hashlib, io, os, re, subprocess, sys
sys.stdout.reconfigure(line_buffering=True)

LUAU = os.environ["LUAU"]
FILES = ["src/shared/Config.luau", "src/shared/VaultPath.luau", "src/shared/VaultFloor.luau",
         "src/shared/Ascent.luau", "src/server/Main.server.luau"]
orig = {f: open(f, "rb").read() for f in FILES}
sha = {f: hashlib.sha256(orig[f]).hexdigest() for f in FILES}

def rebuild():
    subprocess.run(["py", "-3", "wrap.py", "--game", "../vault-runners", "--out", "build/vault-runners.luau"],
                   cwd="../robloxemu", capture_output=True)

SUITES = [("spec", f) for f in sorted(os.listdir("tests")) if f.endswith(".spec.luau")]
SUITES += [("game", "check_vaultrunners.luau")]
SUITES += [("emu", "check_vaultrunners_shaft.luau"), ("emu", "check_vaultrunners_static.luau")]

def failed_count(out):
    m = re.findall(r"(\d+) passed, (\d+) failed", out)
    return int(m[-1][1]) if m else None

def run_all():
    hits = []
    for kind, f in SUITES:
        path, cwd = ("tests/" + f, None) if kind == "spec" else (f, None if kind == "game" else "../robloxemu")
        try:
            r = subprocess.run([LUAU, path], cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                               errors="replace", timeout=600)
        except subprocess.TimeoutExpired:
            hits.append("%s(TIMEOUT)" % f.replace(".spec.luau", "").replace(".luau", ""))
            continue
        n = failed_count(r.stdout + r.stderr)
        if n is None or n != 0:
            hits.append("%s(%s)" % (f.replace(".spec.luau", "").replace(".luau", ""), "ERR" if n is None else n))
    return hits

def restore():
    for f in FILES:
        open(f, "wb").write(orig[f])

MUTATIONS = [
    # REVIEW-4's thirteen, retargeted at the code as it now stands
    ("v1's staircase restored (StepSize 5, StepReach 6)", "src/shared/Config.luau",
     [("\tStepSize = 3,", "\tStepSize = 5,"), ("\tStepReach = 8,", "\tStepReach = 6,")]),
    ("the pads never crumble (CrumbleSeconds 1e9)", "src/shared/Config.luau", [("\tCrumbleSeconds = 1.1,", "\tCrumbleSeconds = 1e9,")]),
    ("the pads never come back (RespawnSeconds 1e9)", "src/shared/Config.luau", [("\tRespawnSeconds = 3,", "\tRespawnSeconds = 1e9,")]),
    ("standing on a pad renews it (a rug)", "src/shared/Ascent.luau",
     [("\tif t0 == nil or now < t0 or now - t0 >= span then state.touchedAt[k] = now end", "\tstate.touchedAt[k] = now")]),
    ("the budget stops paying for the obby (ModelMissChance 0)", "src/shared/Config.luau", [("\tModelMissChance = 0.04,", "\tModelMissChance = 0,")]),
    ("the retry leaks into the walk demand", "src/shared/VaultPath.luau",
     [("\t\tif s < model.storeys - 1 then dt += climbBase end", "\t\tif s < model.storeys - 1 then dt += climb end")]),
    ("E[misses] = attempts - n (the closed form's first bug)", "src/shared/VaultPath.luau",
     [("\tlocal misses = p * missable\n", "\tlocal misses = missable - m\n")]),
    ("the falls are not charged to the storey they land on", "src/shared/VaultPath.luau",
     [("\t\tobbyBy[s + 1] = math.min(s + 1, model.storeys - 1) * climbRetry", "\t\tobbyBy[s + 1] = 0")]),
    ("...nor to the per-storey deadline", "src/shared/VaultPath.luau",
     [("\t\tlocal w, o = m.walkDemandAt[s + 1] / frac, m.obbyBy[s + 1] / frac", "\t\tlocal w, o = m.walkDemandAt[s + 1] / frac, 0")]),
    ("the SERVER never actually removes a pad", "src/server/Main.server.luau",
     [("\t\t\tpart.CanCollide = ch.solid\n", "\t\t\tpart.CanCollide = true\n")]),
    ("the server never notices a runner standing on a pad", "src/server/Main.server.luau",
     [("\t\tif onPad ~= nil then Ascent.touch(Config, a.ascent, onStorey, onPad, a.elapsed) end\n", "")]),
    ("the whole shaft reads as one platform (StandRadius 5)", "src/shared/Config.luau",
     [("\tStandRadius = Config.Vault.StepSize / 2 + Config.Movement.RunnerWidth / 2,", "\tStandRadius = 5,")]),
    ("the stand test reads the ROOT, not the feet", "src/shared/Ascent.luau",
     [("local dy = (pos.y - cfg.Run.RunnerRootHeight) - pad.y", "local dy = pos.y - pad.y")]),
    # REVIEW-5
    ("R5-1 hop 1 priced as missable again (six, not five)", "src/shared/VaultPath.luau",
     [("\treturn math.max(0, math.floor(model.storeyHeight / model.stepRise) - 1)", "\treturn math.max(0, math.floor(model.storeyHeight / model.stepRise))")]),
    ("R5-3a StandRadius back to 3 (a pad-width of tolerance)", "src/shared/Config.luau",
     [("\tStandRadius = Config.Vault.StepSize / 2 + Config.Movement.RunnerWidth / 2,", "\tStandRadius = 3,")]),
    ("R5-3b the shaft looked at 5 Hz again (SampleSeconds 0.2)", "src/shared/Config.luau", [("\tSampleSeconds = 0.05,", "\tSampleSeconds = 0.2,")]),
    ("R5-4 the top storey charged a climb it does not have", "src/shared/VaultPath.luau",
     [("\t\tobbyBy[s + 1] = math.min(s + 1, model.storeys - 1) * climbRetry", "\t\tobbyBy[s + 1] = (s + 1) * climbRetry")]),
    ("R5-6 ModelMissChance no longer range-checked", "src/shared/VaultPath.luau",
     [("\tassert(type(p) == \"number\" and p >= 0 and p < 1, string.format(", "\tassert(true, string.format(")]),
    ("R5-11 a gone pad hides a solid one again", "src/shared/Ascent.luau",
     [("\t\t\t\t\t\t\treturn s, pad.index\n\t\t\t\t\t\tend\n", "\t\t\t\t\t\t\treturn s, pad.index\n\t\t\t\t\t\tend\n\t\t\t\t\t\treturn nil, nil\n")]),
    ("R5-12 a pad registered without its part (pad 6)", "src/server/Main.server.luau",
     [("\t\tif def.group == \"step\" then padParts[def.storey][tonumber(string.match(def.name, \"_(%d+)$\"))] = part end",
       "\t\tif def.group == \"step\" and not string.find(def.name, \"_6$\") then padParts[def.storey][tonumber(string.match(def.name, \"_(%d+)$\"))] = part end")]),
    ("R5-2 the comment says 0.94 again", "src/shared/Config.luau",
     [("\t-- missed, VaultPath.failableHops) is an 18% chance of falling at least once per storey and 0.23\n",
       "\t-- missed, VaultPath.failableHops) is an 18% chance of falling at least once per storey and 0.94\n")]),
]
CONTROLS = [
    ("CONTROL: the HUD accent repainted magenta", "src/shared/Config.luau",
     [("\tAccentColor = { r = 255, g = 196, b = 92 },", "\tAccentColor = { r = 255, g = 0, b = 255 },")]),
    ("CONTROL: an unreachable nil-guard deleted from Ascent.new", "src/shared/Ascent.luau",
     [("\t\tlocal sh: any = model.shafts[s + 1]\n\t\tif sh ~= nil then\n\t\t\tfor _, p in ipairs(sh.pads :: { any }) do pads[#pads + 1] = { storey = s, index = p.index } end\n\t\tend",
       "\t\tlocal sh: any = model.shafts[s + 1]\n\t\tfor _, p in ipairs(sh.pads :: { any }) do pads[#pads + 1] = { storey = s, index = p.index } end")]),
]

def apply(path, edits):
    s = open(path, encoding="utf-8").read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            return "NOT APPLIED: target found %d times: %r" % (n, old[:70])
        s = s.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    return None

rebuild()
print("== baseline")
base = run_all()
print("%-62s %s" % ("no mutation at all (the harness itself)", "clean" if not base else "RED: " + " ".join(base)))
if base:
    sys.exit(1)
killed, survived, broken = 0, [], []
try:
    for title, group in (("== mutations", MUTATIONS), ("== CONTROLS (nothing may notice)", CONTROLS)):
        print(title)
        for name, path, edits in group:
            err = apply(path, edits)
            if err:
                print("%-62s %s" % (name, err)); broken.append(name); restore(); continue
            rebuild()
            hits = run_all()
            restore()
            print("%-62s %s" % (name, ("killed by: " + " ".join(hits)) if hits else "SURVIVED - nothing noticed"))
            if group is MUTATIONS:
                if hits: killed += 1
                else: survived.append(name)
            elif hits:
                survived.append("CONTROL NOTICED: " + name)
finally:
    restore()
    rebuild()
print("== the tree is back where it started")
ok = all(hashlib.sha256(open(f, "rb").read()).hexdigest() == sha[f] for f in FILES)
print("sha256 of every mutated file: %s" % ("identical" if ok else "CHANGED"))
print("%d mutations: %d killed, %d survived, %d not applied" % (len(MUTATIONS), killed, len([s for s in survived if not s.startswith("CONTROL")]), len(broken)))
sys.exit(0 if ok and not broken else 1)
PYEOF
