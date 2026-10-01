"""StormGrow mutation sweep: isolated and parallel. A TEST TOOL, not game code; it produced the mutation table
in CLAUDE.md, so every row there can be reproduced:

  py -3 tests/_mutate.py                 # every mutant, the CONTROL and the BASELINE
  py -3 tests/_mutate.py M3 M25 CONTROL  # some
  set LUAU=<path to luau.exe>            # if the luau CLI is not at the default path below
  set SG_WORKERS=3                       # mutants run side by side (default 3)

Each mutant gets its OWN tree under %TEMP%/stormgrow_mut/<id>/ (a unique name: the shared scratchpad once had
a gates script overwritten by another game's agent, CLAUDE.md trap 15):
    stormgrow/                       a fresh copy of this game, with ONE patch applied
    robloxemu/emu/                   a copy of the emulator
    robloxemu/check_stormgrow*       copies of this game's checks
    robloxemu/build/stormgrow.luau   the mutant's bundle (wrap.py reads the copy and writes here)
so the real robloxemu/build/stormgrow.luau is never touched and src/ is never patched.

Verdicts:
  KILLED          a gate printed a failure, or errored without a summary (a game error)
  SURVIVED        all 32 gates ran and every one printed ", 0 failed" / PASS
  HARNESS ERROR   a gate could not run (a missing module or file): never counted as a kill
  NOT APPLIED     the patch's text did not match exactly once
A killed mutant stops at its first failing gate (its likely killers are tried first). The BASELINE (no patch) and
the CONTROL (a patch nothing reads) run all 32 gates and must both be GREEN, or the harness is broken and every
KILLED in the same run is worthless. The patched file's sha256 is recorded before and after.
"""
import hashlib, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

REAL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMU = os.path.abspath(os.path.join(REAL, "..", "robloxemu"))
MUT = os.environ.get("SG_MUT_DIR") or os.path.join(tempfile.gettempdir(), "stormgrow_mut")
LUAU = os.environ.get("LUAU") or "C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe"

SPECS = sorted(f for f in os.listdir(os.path.join(REAL, "tests")) if f.endswith(".spec.luau"))
CHECKS = ["check_stormgrow.luau", "check_stormgrow_compile.luau", "check_stormgrow_env.luau", "check_stormgrow_hazards.luau",
          "check_stormgrow_rest.luau", "check_stormgrow_hud.luau", "check_stormgrow_save.luau", "check_stormgrow_wire.luau",
          "check_stormgrow_board.luau", "check_stormgrow_firstmin.luau",
          # REVIEW-1
          "check_stormgrow_aim.luau", "check_stormgrow_slots.luau", "check_stormgrow_stream.luau"]
GATES = ([("game", "tests/" + s) for s in SPECS] + [("game", "tests/walk.luau"), ("py", "tests/project_check.py")]
         + [("emu", c) for c in CHECKS])
EXPECTED_GATES = 32
assert len(GATES) == EXPECTED_GATES, len(GATES)

MS = "src/server/Main.server.luau"
FC = "src/client/Farm.client.luau"
CF = "src/shared/Config.luau"
MUTANTS = [
    ("M1", "src/shared/Economy.luau", "at = math.floor(now * 1000 + 0.5) / 1000, m = 0", "at = now, m = 0", "planting time not rounded to the ms", ["Economy.spec", "walk"]),
    ("M2", "src/client/Sky.client.luau", "(humanoid :: any).Jump == true or acted", "(humanoid :: any).Jump == true", "a farm action no longer counts as activity", ["check_stormgrow_rest"]),
    ("M3", "src/shared/Mutation.luau", "and t >= tile.at + crop.grow and bit32.band(tile.m, bit) == 0 then", "and bit32.band(tile.m, bit) == 0 then", "strikes ignore ripeness", ["Mutation.spec"]),
    ("M4", MS, "while char.Parent == nil and frames < 300 do", "while false and frames < 300 do", "onCharacter does not wait for the engine's placement", ["check_stormgrow."]),
    ("M5", MS, "\t\tplr.RespawnLocation = pad\n", "", "RespawnLocation never set", ["check_stormgrow."]),
    ("M6", MS, "if type(old) ~= \"table\" or type(old.session) ~= \"table\" or old.session.token ~= s.token then\n\t\t\t\tlost = true", "if type(old) ~= \"table\" then\n\t\t\t\tlost = true", "saves ignore the owner token", ["check_stormgrow_save"]),
    ("M7", MS, "lockUntil = if release then 0 else serverNow() + S.LockSeconds", "lockUntil = serverNow() + S.LockSeconds", "the release on leave keeps the lock", ["check_stormgrow_save", "walk"]),
    ("M8", "src/shared/HazardGlue.luau", "return math.max(y, groundY + HazardGlue.SkimHeight)", "return y", "drawn hazards may dive underground", ["check_stormgrow_hazards", "EnvConfig.spec"]),
    ("M9", "src/shared/HazardGlue.luau", "return math.max(cameraPitch, math.rad(Hz.GroundPitchFloor))", "return cameraPitch", "no camera pitch floor", ["check_stormgrow_hazards", "EnvConfig.spec"]),
    ("M10", "src/client/Hud.client.luau", "\t\tseeds.Visible = false\n\t\ttimeline.Visible = false\n\t\talmanac.Visible = true", "\t\tseeds.Visible = false\n\t\ttimeline.Visible = true\n\t\talmanac.Visible = true", "the Almanac no longer hides the timeline", ["check_stormgrow_hud"]),
    ("M11", "src/client/Hud.client.luau", "\tif layout.controlPad <= 0 then return designPx end", "\tif true then return designPx end", "no 44 px tap targets on touch", ["check_stormgrow_hud"]),
    ("M12", "src/shared/Board.luau", "if type(old) == \"number\" and old >= value then return nil end", "if false then return nil end", "board writes may lower a score", ["Board.spec", "check_stormgrow_board"]),
    ("M13", "src/shared/Board.luau", "return now - st.lastAt >= B.WriteCoalesceSeconds", "return true", "board writes not coalesced", ["Board.spec", "check_stormgrow_board"]),
    # M14 is EQUIVALENT since REVIEW-1 A5: the board writes only `savedValue`, which a read-only session never raises
    # (it has landed no save), so the canSave guard it removes is now a second lock on the same door. Kept, and kept
    # in this list, so the sweep shows it surviving for that reason.
    ("M14", MS, "\tif not s.canSave or s.profile == nil then return end\n\tlocal value = s.savedValue", "\tif s.profile == nil then return end\n\tlocal value = s.savedValue", "a read-only session writes the board", ["check_stormgrow_board", "check_stormgrow_save"]),
    ("M15", "src/shared/Config.luau", "rainbow = { from = 90, len = 60, every = 1800 }", "rainbow = { from = 90, len = 60, every = 600 }", "a rainbow after every storm", ["Weather.spec"]),
    ("M16", MS, "if root == nil or (root.Position - hb.Position).Magnitude > F.ServerReach then", "if root == nil then", "no server distance check on taps", ["check_stormgrow."]),
    ("M17", "src/client/Sky.client.luau", "resting = resting, grounded = grounded, kinds = bands[bandIdx].hazards or {},", "resting = false, grounded = grounded, kinds = bands[bandIdx].hazards or {},", "rest does not freeze the hazard clock", ["check_stormgrow_rest"]),
    ("M18", "src/client/Farm.client.luau", "if #bolts >= B.MaxBolts then return end", "", "no cap on bolts", ["check_stormgrow_env"]),
    ("M19", "src/shared/ValleyArt.luau", "local keep = i <= self.Config.Budget.MaxLights", "local keep = true", "no cap on lights", ["check_stormgrow_env"]),
    ("M20", "src/shared/Economy.luau", "\tif field > p.fields then\n", "\tif field > 6 then\n", "tiles on unbought fields plant", ["Economy.spec", "check_stormgrow."]),
    ("M21", MS, "\tif t - s.lastAction < Config.Play.ActionMinSeconds then", "\tif false then", "no action rate limit", ["check_stormgrow.", "check_stormgrow_wire"]),
    ("M22", "src/client/Sky.client.luau", "if loaded then\n\t\tif not seeded then", "if true then\n\t\tif not seeded then", "band cards announce before the profile loaded", ["check_stormgrow_env"]),
    ("M23", MS, "fb:FindFirstChildOfClass(\"ProximityPrompt\").Triggered:Connect(onBoardPrompt)", "local _ = fb", "the porch board's prompt does nothing", ["check_stormgrow_board", "check_stormgrow."]),
    ("M24", "src/shared/Economy.luau", "p.harvested += value", "p.harvested += value * 0", "harvests do not count toward the bands", ["Economy.spec"]),
    ("M25", "src/client/Hud.client.luau", "\t\t\tpushToast(string.format(\"Unlock %s %s first\", prev.emoji, prev.name), \"info\")",
     "\t\t\ttoastLabel.Text = string.format(\"Unlock %s %s first\", prev.emoji, prev.name)\n\t\t\ttoastLabel.Visible = true",
     "a locked seed row's refusal flashes for one refresh (the 2026-10-01 resume fix)", ["check_stormgrow_firstmin"]),
    # ── REVIEW-1 (2026-10-01): one mutant per new rule, each aimed at the assertion written for it
    ("M26", FC, "local v = tv.view", "local v = nil", "B1: the tap pick ignores the drawn crops (soil plates only)", ["check_stormgrow_aim", "walk"]),
    ("M27", MS, "Name = \"Tile_\" .. key, Size = Vector3.new(F.SoilSize, F.SoilHeight * 0.6, F.SoilSize),\n\t\t\t\tCFrame = localCF(k, lx, F.GroundY + F.SoilHeight * 0.3, lz)",
     "Name = \"Tile_\" .. key, Size = Vector3.new(F.SoilSize, 6, F.SoilSize),\n\t\t\t\tCFrame = localCF(k, lx, F.GroundY + 3, lz)", "B1: the tile part is a 6-stud invisible column again", ["check_stormgrow_aim", "check_stormgrow."]),
    ("M28", MS, 'toast(plr, "Walk closer to tap this crop")', 'local _ = "Walk closer"', "B3: a tap from too far is refused silently", ["check_stormgrow_aim", "check_stormgrow."]),
    ("M29", FC, "local MAX_PICK = 600", "local MAX_PICK = 32", "B3: the client drops taps beyond 32 studs (the old detector reach)", ["check_stormgrow_aim"]),
    ("M30", FC, 'if processed or type(positions) ~= "table" then return end', 'if type(positions) ~= "table" then return end', "B1: a tap the HUD took is also a farm tap", ["check_stormgrow_aim"]),
    ("M31", CF, "IdleSeconds = 90,", "IdleSeconds = 20,", "B2: idle rest after 20 s again", ["walk"]),
    ("M32", FC, "farms.DescendantAdded:Connect(addTile)", "local _ = addTile", "B4: tiles that arrive later are never drawn", ["check_stormgrow_stream"]),
    ("M33", FC, "if not tv.hb:IsDescendantOf(workspace) then", "if false then", "B4: a tile that streamed out keeps its crop", ["check_stormgrow_stream"]),
    ("M34", "default.project.json", '"StreamingEnabled": false', '"StreamingEnabled": true', "B4: the place streams", ["project_check"]),
    ("M35", "src/shared/CropArt.luau", "view.folder:Destroy()", "local _ = view.folder", "(found in REVIEW-1) an empty crop folder per replant", ["check_stormgrow_stream"]),
    ("M36", MS, "if (seenLock.lockUntil or 0) > now then return nil end", "if true then return nil end", "A1: a dead server's lock is never taken", ["check_stormgrow_save"]),
    ("M37", MS, "or tonumber(old.session.lockUntil) ~= seenLock.lockUntil or Profile.isNewer(old) then", "or Profile.isNewer(old) then", "A1: a lock that moved on is taken anyway", ["check_stormgrow_save"]),
    ("M38", CF, "LoadRetries = 3,", "LoadRetries = 0,", "A2: one failed load call makes the session read-only", ["check_stormgrow_save"]),
    ("M39", MS, 'if s.recover == "load" then\n\t\tlocal verdict, seen = tryLoad(s)', 'if s.recover == "load" then\n\t\tdo return end\n\t\tlocal verdict, seen = tryLoad(s)', "A2: an outage's read-only farm never reloads", ["check_stormgrow_save"]),
    ("M40", "src/shared/Profile.luau", "return type(raw) == \"table\" and (tonumber(raw.v) or 1) > Profile.VERSION", "return false", "A4: a newer version's record is rewritten", ["Profile.spec", "check_stormgrow_save"]),
    ("M41", MS, "\tif slot then\n\t\tclearFarm(slot)\n\t\thandOver(slot)\n\tend\n\tif s.loaded then\n\t\tsave(s, true)\n\t\tflushBoard(s, true)\n\tend",
     "\tif s.loaded then\n\t\tsave(s, true)\n\t\tflushBoard(s, true)\n\tend\n\tif slot then\n\t\tclearFarm(slot)\n\t\thandOver(slot)\n\tend", "A3: the farm is freed only after the leave's writes", ["check_stormgrow_slots"]),
    ("M42", MS, "\t\thandOver(slot)\n", "", "A3: a freed farm is never handed to a waiting player", ["check_stormgrow_slots"]),
    ("M43", MS, "local value = s.savedValue", "local value = Board.encode(s.profile.almanacCount, s.profile.almanacAt, B)", "A5: the board writes the live count", ["check_stormgrow_board"]),
    ("M44", MS, "s.saveSoon = true -- the entry", "s.saveSoon = false -- the entry", "A5: a new entry waits for the autosave", ["check_stormgrow_board"]),
    ("M45", MS, "if not save(s, false) and s.canSave then s.saveSoon = true end", "save(s, false)", "A5: a failed entry save is not tried again", ["check_stormgrow_board"]),
    ("M46", MS, "if t - s.lastPromptAt < B.PromptCooldownSeconds then", "if false then", "A6: no prompt cooldown", ["check_stormgrow_board"]),
    ("M47", MS, "if failedAt and serverNow() - failedAt < B.NameRetrySeconds then return fallback end", "local _ = failedAt", "A6: a failed name is looked up on every view", ["check_stormgrow_board"]),
    ("M48", CF, "Porch = { X = 15", "Porch = { X = 36", "B5: the porch board back at the porch's end, 36 studs from the pad", ["check_stormgrow_board", "check_stormgrow."]),
    ("M49", CF, "PromptReach = 12,", "PromptReach = 16,", "B5: both prompts pressed from 16 studs (rows too small there)", ["check_stormgrow_board"]),
    ("M50", "src/client/Hud.client.luau", "if porch then want[porch] = Config.Board.PorchShown end", "if porch then want[porch] = Config.Board.PublicShown end", "B5: the porch board lists ten small rows", ["check_stormgrow_board"]),
    ("M51", CF, "Porch = { X = 15, Z = 4,", "Porch = { X = 5, Z = 8,", "B5: the porch board stands in front of field 1", ["check_stormgrow_board"]),
    ("M52", CF, "FaceX = 0, FaceZ = -4,", "FaceX = 15, FaceZ = 30,", "B5: the porch board turns its back on the spawn camera", ["check_stormgrow_board"]),
    ("M53", MS, "local hb = byKey and byKey[key]", "local hb = byKey and byKey[\"1_1\"]", "B1: the server acts on another tile than the one tapped", ["check_stormgrow.", "check_stormgrow_aim"]),
    ("M54", MS, "if s.leaving and not release then", "if false then", "(found in REVIEW-1) a save in flight at the leave re-locks the record", ["check_stormgrow_save"]),
    ("M55", "src/client/Sky.client.luau", "zone.y = HazardGlue.ringY(zone.x, zone.z, zone.radius, F, Farm)", "zone.y = nil", "(found in REVIEW-1) the ring drawn at ground height, under the porch, pads and soil", ["check_stormgrow_hazards"]),
    ("M56", "src/shared/HazardGlue.luau", "if math.abs(lx) <= F.PadSize / 2 and math.abs(lz - F.PadLocalZ) <= F.PadSize / 2 then return g + 1 end", "", "(found in REVIEW-1) the glue forgets the farm pads", ["EnvConfig.spec", "check_stormgrow_hazards"]),
    ("M57", MS, "Size = Vector3.new(12, 1.2, 0.4),\n\t\tCFrame = localCF(k, 0, F.GroundY + 0.4 + 0.6, 0.3, 0, -10)", "Size = Vector3.new(12, 3, 0.4),\n\t\tCFrame = localCF(k, 0, F.GroundY + 6, 0.5, 0, -10)", "(found in REVIEW-1) the owner sign back up behind the spawn pad", ["check_stormgrow_aim"]),
    ("CONTROL", MS, "Material = Enum.Material.Cobblestone", "Material = Enum.Material.Slate", "the market square's material (nothing reads it)", []),
    ("BASELINE", None, None, None, "no patch: the isolated harness on the real source", []),
]

HARNESS_MARKERS = ("Could not find", "cannot open", "No such file", "not found:", "WRAP FAILED")


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:12]


def setup(mid):
    base = os.path.join(MUT, mid)
    if os.path.isdir(base):
        shutil.rmtree(base)
    shutil.copytree(REAL, os.path.join(base, "stormgrow"), ignore=shutil.ignore_patterns("*.rbxl*", "__pycache__", "publish_*"))
    shutil.copytree(os.path.join(EMU, "emu"), os.path.join(base, "robloxemu", "emu"))
    for c in CHECKS:
        shutil.copy2(os.path.join(EMU, c), os.path.join(base, "robloxemu", c))
    os.makedirs(os.path.join(base, "robloxemu", "build"))
    return base


def run_gate(base, where, rel):
    cwd = os.path.join(base, "robloxemu") if where == "emu" else os.path.join(base, "stormgrow")
    cmd = ["py", "-3", rel] if where == "py" else [LUAU, rel]
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return "FAIL", "TIMEOUT (900 s)"
    # every gate's full output stays next to the mutant, so a RED control or a surprising kill can be read later
    with open(os.path.join(base, os.path.basename(rel) + ".out"), "w", encoding="utf-8") as fh:
        fh.write(out)
    summary = [l for l in out.splitlines() if ("passed, " in l and " failed" in l) or l.startswith("PASS —") or l.startswith("FAIL —")]
    if summary:
        line = summary[-1]
        ok = (", 0 failed" in line) or line.startswith("PASS —")
        return ("PASS" if ok else "FAIL"), line.strip()
    tail = " / ".join(l for l in out.splitlines() if l.strip())[-300:]
    if any(m in out for m in HARNESS_MARKERS):
        return "HARNESS", tail
    return "FAIL", "no summary: " + tail


def ordered(hints):
    first = []
    for hnt in hints:
        for g in GATES:
            if hnt in g[1] and g not in first:
                first.append(g)
    return first + [g for g in GATES if g not in first]


def one(m):
    mid, rel, old, new, what, hints = m
    base = setup(mid)
    before = after = "-"
    if rel is not None:
        path = os.path.join(base, "stormgrow", rel)
        before = sha(path)
        with open(path, "r", encoding="utf-8", newline="") as fh:
            src = fh.read()
        # sources may be LF or CRLF: match the patch in the file's own line endings
        crlf = "\r\n" in src
        o, nw = (old.replace("\n", "\r\n"), new.replace("\n", "\r\n")) if crlf else (old, new)
        n = src.count(o)
        if n != 1:
            return (mid, what, "NOT APPLIED (%d matches)" % n, before, before, "", 0)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(src.replace(o, nw))
        after = sha(path)
        if after == before:
            return (mid, what, "NOT APPLIED (file unchanged)", before, after, "", 0)
    w = subprocess.run(["py", "-3", "wrap.py", "--game", os.path.join(base, "stormgrow"), "--out",
                        os.path.join(base, "robloxemu", "build", "stormgrow.luau")], cwd=EMU, capture_output=True, text=True)
    if w.returncode != 0:
        return (mid, what, "HARNESS ERROR (wrap)", before, after, w.stderr[-200:], 0)
    full = mid in ("CONTROL", "BASELINE")
    ran = 0
    for where, g in (GATES if full else ordered(hints)):
        verdict, line = run_gate(base, where, g)
        ran += 1
        if verdict == "HARNESS":
            return (mid, what, "HARNESS ERROR", before, after, os.path.basename(g) + ": " + line, ran)
        if verdict == "FAIL":
            if full:
                return (mid, what, "RED (must be green)", before, after, os.path.basename(g) + ": " + line, ran)
            return (mid, what, "KILLED", before, after, os.path.basename(g) + ": " + line, ran)
    if ran != EXPECTED_GATES:
        return (mid, what, "HARNESS ERROR (%d of %d gates)" % (ran, EXPECTED_GATES), before, after, "", ran)
    return (mid, what, "GREEN" if full else "SURVIVED", before, after, "all %d gates green" % ran, ran)


def main():
    if not os.path.isfile(LUAU):
        sys.exit("luau CLI not found at %s: set LUAU" % LUAU)
    only = sys.argv[1:]
    todo = [m for m in MUTANTS if not only or m[0] in only]
    workers = int(os.environ.get("SG_WORKERS", "3"))
    rows = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for r in ex.map(one, todo):
            rows.append(r)
            print("%-9s %-22s %s -> %s  [%d gates]  %s\n           %s" % (r[0], r[2], r[3], r[4], r[6], r[1], r[5]), flush=True)
    print("\nSUMMARY")
    for r in rows:
        print("%-9s %-22s %s" % (r[0], r[2], r[1]))


if __name__ == "__main__":
    main()
