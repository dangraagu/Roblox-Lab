"""Mutation driver for Nightwatch Manor. Exact-match patcher: refuses on a miss, runs every gate,
restores every tracked source afterwards and re-checks its sha256.

This is a TEST TOOL, not game code, and it is kept rather than deleted because it is what produced
the mutation table in CLAUDE.md and REVIEW-3.md: any claim there can be reproduced with one
command. Note the baseline discipline it enforces — if the suite is red BEFORE a mutation is
applied, every mutation reports as KILLED and the sweep is worthless. That happened once during
this round; the four C* controls are what caught it.

  py -3 tests/_mutate.py            # run every mutation
  py -3 tests/_mutate.py <id> ...   # run some
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = r"C:/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe"
EMU = os.path.abspath(os.path.join(ROOT, "..", "robloxemu"))

CFG = "src/shared/Config.luau"
MANOR = "src/shared/Manor.luau"
WATCH = "src/shared/Watcher.luau"
MAIN = "src/server/Main.server.luau"

# id -> (file, from, to, expectation)  expectation: "KILL" or "SURVIVE"
MUTS = {
    # --- controls: the suites must NOT notice these ---
    "C1-room-kind-name": (CFG, '{ id = "library", name = "Library", weight = 2 }',
                          '{ id = "library", name = "Reading Room", weight = 2 }', "SURVIVE"),
    "C2-relic-tier-name": (CFG, '{ id = "reliquary", name = "Silver Reliquary"',
                           '{ id = "reliquary", name = "Tarnished Casket"', "SURVIVE"),
    "C3-upgrade-blurb": (CFG, 'blurb = "Light you can carry into the manor."',
                         'blurb = "A lamp for the dark."', "SURVIVE"),
    "C4-watcher-colour": (MAIN, 'Name = "Torso", Size = Vector3.new(2.4, 4, 1.4), Color = Color3.fromRGB(10, 10, 14)',
                          'Name = "Torso", Size = Vector3.new(2.4, 4, 1.4), Color = Color3.fromRGB(200, 10, 14)', "SURVIVE"),
    # --- the chase ---
    "M1-sight-range": (CFG, "SightRange = 55,", "SightRange = 2000,", "KILL"),
    "M2-speed-ceiling-fraction": (CFG, "MaxSpeedFraction = 0.65,", "MaxSpeedFraction = 3.0,", "KILL"),
    "M3-ceiling-deleted": (WATCH, """	local ceiling = cfg.Player.WalkSpeed * W.MaxSpeedFraction
	if s > ceiling then
		s = ceiling
	end""", """	local ceiling = cfg.Player.WalkSpeed * W.MaxSpeedFraction
	if s > ceiling and false then
		s = ceiling
	end""", "KILL"),
    "M4-hunt-speed-5x": (CFG, "HuntSpeedMul = 1.2,", "HuntSpeedMul = 5.0,", "KILL"),
    "M5-walkspeed-16": (CFG, "WalkSpeed = 20,", "WalkSpeed = 16,", "KILL"),
    # --- the layout ---
    "M6-extra-doors-off": (CFG, "ExtraDoorChance = 0.75,", "ExtraDoorChance = 0.05,", "KILL"),
    "M7-repair-budget-1": (CFG, "MaxRepairRooms = 5,", "MaxRepairRooms = 1,", "KILL"),
    "M8-cap-invariant-broken": (CFG, "MaxRepairRooms = 5,", "MaxRepairRooms = 17,", "KILL"),
    "M9-target-clamps-at-max": (MANOR, "return clamp(n, 2, math.max(M.MaxRooms - M.MaxRepairRooms, 2))",
                                "return clamp(n, 2, M.MaxRooms)", "KILL"),
    # --- the chase goes through doorways ---
    "M10-chasestep-diagonal": (MANOR, """	local clear = cfg.Manor.DoorWidth * 0.25
	if (x - (dx :: number)) ^ 2 + (z - (dz :: number)) ^ 2 <= clear * clear then
		return cx, cz
	end
	return dx, dz""", """	local clear = cfg.Manor.DoorWidth * 0.25
	if (x - (dx :: number)) ^ 2 + (z - (dz :: number)) ^ 2 <= clear * clear then
		return cx, cz
	end
	return cx, cz""", "KILL"),
    "M11-server-ignores-chasestep": (MAIN, """				local nx, nz = Manor.chaseStep(Config, plan, watcherRoom,
					run.watcher.x - origin.X, run.watcher.z - origin.Z, playerRoom)""",
                                     """				local pth = Manor.pathBetween(plan, watcherRoom, playerRoom)
				local nr = pth and pth[2] and Manor.roomById(plan, pth[2])
				local nx, nz = if nr then Manor.roomCenter(Config, nr) else nil, nil""", "KILL"),
    # --- the exit door ---
    "M12-exit-door-plus-z": (MAIN, "\t\tfx, fz = fx or 0, fz or 1", "\t\tfx, fz = 0, 1", "KILL"),
    "M13-exitface-first-dir": (MANOR, """		if nb == nil then
			return d[1], d[2] -- the outside of the manor: nothing to block, nothing to be blocked by
		end""", """		if nb == nil and false then
			return d[1], d[2]
		end""", "KILL"),
    # --- the guards ---
    "M14-boot-guard-off": (MAIN, """	local ok, why = Watcher.speedAudit(Config)
	if not ok then
		error(why, 0)
	end""", """	local ok, why = Watcher.speedAudit(Config)
	if not ok and false then
		error(why, 0)
	end""", "KILL"),
    "M15-ceiling-warning-off": (MAIN, """	local binds, note = Watcher.ceilingBinds(Config)
	if binds then
		warn(note)
	end""", """	local binds, note = Watcher.ceilingBinds(Config)
	if binds and false then
		warn(note)
	end""", "KILL"),
    "M16-night-gate-off": (MAIN, """	if not prof.loaded then
		notice(plr, "DENIED", "Still opening your safehouse — one moment.")""",
                           """	if false then
		notice(plr, "DENIED", "Still opening your safehouse — one moment.")""", "KILL"),
    "M17-buy-gate-off": (MAIN, """			if not p.loaded then
				notice(plr, "DENIED", "Still opening your safehouse — one moment.")""",
                        """			if false then
				notice(plr, "DENIED", "Still opening your safehouse — one moment.")""", "KILL"),
    "M18-origin-plate-sunk": (MAIN, "Name = \"OriginPlate\", Size = Vector3.new(48, 2, 48), CFrame = CFrame.new(0, 0, 0),",
                              "Name = \"OriginPlate\", Size = Vector3.new(48, 2, 48), CFrame = CFrame.new(0, -4000, 0),", "KILL"),
    "M19-origin-spawn-sunk": (MAIN, "sp.CFrame = CFrame.new(0, 1.5, 0)", "sp.CFrame = CFrame.new(0, -4000, 0)", "KILL"),
    "M20-spawnpad-disabled": (MAIN, "spawnPad.Enabled = true", "spawnPad.Enabled = false", "KILL"),
    # --- the built world ---
    "M21-no-doorways-built": (MAIN, "buildWall(folder, centre, dir, Manor.linked(plan, room.id, other.id), tostring(di))",
                              "buildWall(folder, centre, dir, false, tostring(di))", "KILL"),
    "M22-character-not-placed": (MAIN, "\t\tapplyWalkSpeed(char)\n\t\tplaceCharacter()",
                                 "\t\tapplyWalkSpeed(char)\n\t\t-- placeCharacter()", "KILL"),
    "M23-table-fills-room": (MAIN, 'Name = "LongTable", Size = Vector3.new(8, 3, 22)',
                             'Name = "LongTable", Size = Vector3.new(34, 3, 34)', "KILL"),
}

TRACKED = [CFG, MANOR, WATCH, MAIN]


def sha(path):
    with open(os.path.join(ROOT, path), "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:12]


def run(argv, cwd):
    """argv is a LIST — no shell, so nothing here can be reinterpreted as a shell metacharacter."""
    r = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def gates():
    """-> (ok, [names of gates that went red])"""
    red = []
    for f in sorted(os.listdir(os.path.join(ROOT, "tests"))):
        if f.endswith(".spec.luau"):
            rc, _ = run([LUAU, "tests/" + f], ROOT)
            if rc != 0:
                red.append(f.replace(".spec.luau", ".spec"))
    rc, _ = run(["py", "-3", os.path.join(EMU, "wrap.py"), "--game", ".",
                 "--out", "tests/build/nightwatch-manor.luau"], ROOT)
    if rc != 0:
        red.append("wrap.py")
        return not red, red
    tdir = os.path.join(ROOT, "tests")
    for name in ("check_world.luau", "check_walk.luau"):
        rc, _ = run([LUAU, name], tdir)
        if rc != 0:
            red.append(name.replace(".luau", ""))
    for case in ("control", "fraction", "walkspeed", "saturated"):
        rc, _ = run([LUAU, "check_boot_guard.luau", "-a", case], tdir)
        if rc != 0:
            red.append("boot_guard[%s]" % case)
    rc, _ = run(["py", "-3", "wrap.py", "--game", "../nightwatch-manor",
                 "--out", "build/nightwatch-manor.luau"], EMU)
    if rc == 0:
        rc, _ = run([LUAU, "check_nightwatch.luau"], EMU)
        if rc != 0:
            red.append("robloxemu/check_nightwatch")
    return not red, red


def main():
    ids = sys.argv[1:] or list(MUTS)
    tmp = tempfile.mkdtemp()
    for f in TRACKED:
        shutil.copy(os.path.join(ROOT, f), os.path.join(tmp, f.replace("/", "_")))
    base = {f: sha(f) for f in TRACKED}

    print("baseline sha256[:12]: " + ", ".join("%s=%s" % (os.path.basename(f), s) for f, s in base.items()))
    bad = 0
    for mid in ids:
        path, a, b, want = MUTS[mid]
        full = os.path.join(ROOT, path)
        with open(full, encoding="utf-8") as fh:
            src = fh.read()
        n = src.count(a)
        if n != 1:
            print("%-30s REFUSED: pattern occurs %d times in %s" % (mid, n, path))
            bad += 1
            continue
        with open(full, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(src.replace(a, b))
        ok, red = gates()
        got = "SURVIVE" if ok else "KILL"
        mark = "ok " if got == want else "!! "
        if got != want:
            bad += 1
        print("%s%-30s %-8s by: %s" % (mark, mid, got, ", ".join(red) if red else "-"))
        shutil.copy(os.path.join(tmp, path.replace("/", "_")), full)

    for f in TRACKED:
        if sha(f) != base[f]:
            print("!! %s did NOT restore" % f)
            bad += 1
    run(["py", "-3", os.path.join(EMU, "wrap.py"), "--game", ".",
         "--out", "tests/build/nightwatch-manor.luau"], ROOT)
    run(["py", "-3", "wrap.py", "--game", "../nightwatch-manor",
         "--out", "build/nightwatch-manor.luau"], EMU)
    print("all sources restored, sha256 match" if bad == 0 else "%d unexpected results" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
