-- Ascent — THE PADS CRUMBLE. Run: luau tests/Ascent.spec.luau
--
-- The geometry half of the obby is in tests/VaultFloor.spec.luau (`climbIsFailable`): six 3x3
-- pads with five studs of open air between them, a jump that can be missed. This file is the
-- other half — the pads do not wait for you.
--
-- Every rule here is about ONE risk in two directions:
--
--   * too generous and the shaft is a staircase again. A pad that never goes away, or goes away
--     for a moment nobody notices, is v1 with extra machinery.
--   * too mean and the vault is UNWINNABLE, which is exactly the defect Collapse.spec exists to
--     stop. A pad that crumbles faster than a runner can hop off it, or one that never comes
--     back, turns "the collapse got you" into "the game did".
--
-- So: the grace has to be at least one hop, and every pad has to return. Both are asserted
-- against Config rather than against a number typed in here, so re-tuning the crumble cannot
-- quietly cross either line.
--
-- Pure, like everything in src/shared: cfg + plain tables + a number for `now`. No Roblox global,
-- no clock of its own, and no `require` inside the module — a bare `require("./X")` resolves in
-- the luau CLI and is INVALID in Roblox.

local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local VaultFloor = require("../src/shared/VaultFloor")
local VaultPath = require("../src/shared/VaultPath")
local Ascent = require("../src/shared/Ascent")
local MazeGen = require("../src/shared/MazeGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local C = Config
local A = C.Ascent

local function build(tier, floor)
	local spec = Progression.difficulty(C, tier, floor)
	spec.seed = Progression.seedFor(C, tier, floor)
	return VaultFloor.build(C, spec, MazeGen, Rng), spec
end

local model = build(3, 1)

--============================================================================ the shaft exists

do
	eq(#model.shafts, model.storeys - 1, "every storey but the top has a shaft to climb out of")
	for s = 0, model.storeys - 2 do
		local sh = model.shafts[s + 1]
		eq(sh.storey, s, "shaft " .. s .. " knows which storey it belongs to")
		eq(#sh.pads, math.floor(model.storeyHeight / model.stepRise),
			"shaft " .. s .. " has one pad per StepRise of the storey")
		-- The pad's `y` is its WALKABLE TOP, not its centre. Getting that wrong puts the stand
		-- test half a stud inside the pad and the runner is never standing on anything.
		for _, pad in ipairs(sh.pads) do
			local part = nil
			for _, p in ipairs(model.parts) do
				if p.group == "step" and p.storey == s
					and math.abs(p.position.x - pad.x) < 1e-9
					and math.abs(p.position.z - pad.z) < 1e-9
					and math.abs(p.position.y + p.size.y / 2 - pad.y) < 1e-9 then part = p end
			end
			ok(part ~= nil, string.format(
				"shaft %d pad %d matches a part the vault actually built", s, pad.index))
		end
	end
end

--============================================================================ standing on a pad

do
	local sh = model.shafts[1]
	local pad = sh.pads[3]
	local st = Ascent.new(C, model)

	local s, k = Ascent.padUnder(C, model, { x = pad.x, y = pad.y + 3, z = pad.z })
	eq(s, 0, "a runner over pad 3 of shaft 0 is on shaft 0")
	eq(k, 3, "...on pad 3")

	-- Half a pad out is still standing on it: a runner on the lip of a 3-stud pad is on the pad.
	local _, k2 = Ascent.padUnder(C, model, { x = pad.x + 1.4, y = pad.y + 3, z = pad.z })
	eq(k2, 3, "standing on the lip of the pad still counts as standing on it")

	-- THE STAND BOX IS THE PAD PLUS HALF A RUNNER, AND NOT A STUD MORE (REVIEW-5 §3). A runner whose
	-- root is within StepSize/2 + RunnerWidth/2 of the pad's centre has part of their 2-stud body over
	-- the pad; past that, all of them is over the gap. StandRadius = 3 was a full pad-width of
	-- tolerance: a runner who landed short, 1.5 studs out into the air and about to fall, was counted
	-- as standing on the pad and started its crumble.
	local edge = C.Vault.StepSize / 2 + C.Movement.RunnerWidth / 2
	eq(A.StandRadius, edge, "StandRadius is the pad's half-width plus the runner's half-width")
	local _, kEdge = Ascent.padUnder(C, model, { x = pad.x + edge, y = pad.y + 3, z = pad.z })
	eq(kEdge, 3, "a runner whose body just overlaps the pad's edge is standing on it")
	local _, kPast = Ascent.padUnder(C, model, { x = pad.x + edge + 0.1, y = pad.y + 3, z = pad.z })
	eq(kPast, nil, "a runner whose whole body is over the gap is not standing on the pad")
	local _, kShort = Ascent.padUnder(C, model, { x = pad.x - 3, y = pad.y + 3, z = pad.z })
	eq(kShort, nil, "the reviewer's point: 1.5 studs out into the gap is not on the pad")

	-- ...but the open air between two pads is not any pad. This is the assertion that says the
	-- gap is real: if StandRadius ever grew past half the reach, the whole shaft would read as
	-- one continuous platform and nothing could ever be missed.
	local mid = sh.pads[4]
	local _, kMid = Ascent.padUnder(C, model,
		{ x = (pad.x + mid.x) / 2, y = pad.y + 3, z = (pad.z + mid.z) / 2 })
	eq(kMid, nil, "the open air between two pads is not a pad")

	-- Under a pad is not on it, and neither is well above it.
	local _, kUnder = Ascent.padUnder(C, model, { x = pad.x, y = pad.y - 2, z = pad.z })
	eq(kUnder, nil, "a runner below the pad is not standing on it")
	local _, kOver = Ascent.padUnder(C, model,
		{ x = pad.x, y = pad.y + C.Run.RunnerRootHeight + A.StandHeight + 2, z = pad.z })
	eq(kOver, nil, "a runner sailing over the pad without landing is not standing on it")

	-- STANDING ON THE FLOOR IS NOT STANDING ON PAD 1, and this is the one that bites. Pad 1's top
	-- is exactly StepRise above the storey floor, so a runner walking across the stairwell cell has
	-- their ROOT at the same height as the pad's top surface. Measured from the root, that reads as
	-- standing on the pad: pad 1 starts crumbling while the runner is still walking up to it, and
	-- it is gone by the time they jump. The test is the runner's FEET, not their root.
	local sh0 = model.shafts[1]
	local floorRoot = sh0.floorY + C.Run.RunnerRootHeight
	local p1 = sh0.pads[1]
	local _, kFloor = Ascent.padUnder(C, model, { x = p1.x - 1, y = floorRoot, z = p1.z - 1 })
	eq(kFloor, nil, "walking across the stairwell floor does not crumble the pad above it")
	-- THE TOP PAD IS FLUSH WITH THE FLOOR ABOVE, 0.5 studs in from the hole's edge, so a runner
	-- arriving on the next storey registers on it while any part of their body is over it — and not
	-- once all of it is on the solid floor (obby review finding 7, REVIEW-5 §7). With StandRadius = 3
	-- a runner a full stud onto the floor above still counted, "correct" only by fiat.
	do
		local top = sh0.pads[#sh0.pads]
		local sx = if top.x > sh0.x then 1 else -1 -- the hole edge nearest the pad, away from the cell centre
		local holeEdge = sh0.x + sx * model.cellSize / 2
		local rootY = top.y + C.Run.RunnerRootHeight
		-- standing on the floor's lip, 0.8 studs past the hole's edge, body clear of the pad by 0.3
		local clear = top.x + sx * (C.Vault.StepSize / 2 + C.Movement.RunnerWidth / 2 + 0.3)
		ok(sx * (clear - holeEdge) > 0, "(the lip point is on the floor above, past the hole's edge)")
		local _, kFloorAbove = Ascent.padUnder(C, model, { x = clear, y = rootY, z = top.z })
		eq(kFloorAbove, nil, "a runner on the floor above whose body is clear of the top pad is not on it")
		local overlap = top.x + sx * (A.StandRadius - 0.05) -- half a runner over the pad's far edge
		local _, kLip = Ascent.padUnder(C, model, { x = overlap, y = rootY, z = top.z })
		eq(kLip, #sh0.pads, "...and one whose body still overlaps the top pad from the floor's lip is on it")
	end
	-- Standing on the pad still counts, feet on its top surface.
	local _, kOn = Ascent.padUnder(C, model,
		{ x = p1.x, y = p1.y + C.Run.RunnerRootHeight, z = p1.z })
	eq(kOn, 1, "and a runner whose feet are on pad 1 IS standing on pad 1")

	-- A pad that has crumbled cannot be stood on, however convincing the position is.
	Ascent.touch(C, st, 0, 3, 0)
	local _, kGone = Ascent.padUnder(C, model, { x = pad.x, y = pad.y + 3, z = pad.z }, st,
		A.CrumbleSeconds + 0.01)
	eq(kGone, nil, "a pad that has already fallen away cannot be stood on")
end

-- A GONE PAD DOES NOT HIDE A SOLID ONE (obby review finding 11, REVIEW-5 §11). padUnder used to stop
-- at the first pad whose box matched and answer "nothing" if that pad was gone, instead of looking
-- at the rest. The shipped shaft never has two pads within a stand box of one point (asserted just
-- below), so this is the rule held on a made-up shaft where it does.
do
	local fake = {
		storeys = 2, stepRise = model.stepRise,
		shafts = { { pads = {
			{ index = 1, x = 0, y = 3, z = 0 },
			{ index = 2, x = 1, y = 3, z = 0 },
		} } },
	}
	local st = Ascent.new(C, fake)
	Ascent.touch(C, st, 0, 1, 0)
	local _, k = Ascent.padUnder(C, fake, { x = 0.5, y = 3 + C.Run.RunnerRootHeight, z = 0 }, st, A.CrumbleSeconds + 0.01)
	eq(k, 2, "a runner over a gone pad AND a solid one is standing on the solid one")
	-- ...and in the vaults we ship, no point is inside two pads' stand boxes at once
	local worst = math.huge
	for _, tier in ipairs({ 1, 2, 3 }) do
		local sp = Progression.difficulty(C, tier, 1)
		sp.seed = Progression.seedFor(C, tier, 1)
		local mm = VaultFloor.build(C, sp, MazeGen, Rng)
		local all = {}
		for s = 0, mm.storeys - 2 do for _, p in ipairs(mm.shafts[s + 1].pads) do table.insert(all, p) end end
		for i = 1, #all do
			for j = i + 1, #all do
				local a, b = all[i], all[j]
				-- two boxes overlap only when BOTH axes are within 2 * StandRadius and the feet bands meet
				local apart = math.max(math.abs(a.x - b.x), math.abs(a.z - b.z))
				if math.abs(a.y - b.y) < model.stepRise / 2 + A.StandHeight then worst = math.min(worst, apart) end
			end
		end
	end
	ok(worst > 2 * A.StandRadius, string.format(
		"two pads at feet-band height are %.1f studs apart, inside two stand boxes (%.1f)", worst, 2 * A.StandRadius))
end

--============================================================================ the crumble cycle

do
	local st = Ascent.new(C, model)
	ok(Ascent.solid(C, st, 0, 1, 0), "an untouched pad is solid")
	ok(Ascent.solid(C, st, 0, 1, 10000), "...and stays solid forever if nobody stands on it")

	-- TOUCHED AT ZERO, so `now - t0` is the boundary EXACTLY. Touching at 100 and asking at
	-- 100 + CrumbleSeconds is not the same question: 101.1 - 100 is 1.0999999999999943 in
	-- doubles, so the boundary assertions would be measuring IEEE-754 rather than the rule. The
	-- run loop ticks at 0.2s and does not care; a spec that means "AT the boundary" does.
	Ascent.touch(C, st, 0, 1, 0)
	ok(Ascent.solid(C, st, 0, 1, 0), "the pad does not vanish under the foot that lands on it")
	ok(Ascent.solid(C, st, 0, 1, A.CrumbleSeconds - 1e-6),
		"...it holds for the whole grace period")
	ok(not Ascent.solid(C, st, 0, 1, A.CrumbleSeconds),
		"...and is gone AT the crumble boundary, not a tick after it")
	ok(not Ascent.solid(C, st, 0, 1, A.CrumbleSeconds + A.RespawnSeconds - 1e-6),
		"it stays gone for the whole respawn")
	ok(Ascent.solid(C, st, 0, 1, A.CrumbleSeconds + A.RespawnSeconds),
		"...and comes BACK. A shaft that eats its own route is an unwinnable vault")

	-- Touching again mid-crumble must not restart the clock: a runner cannot hold a pad up by
	-- standing on it, which is the difference between a crumbling platform and a rug.
	local st2 = Ascent.new(C, model)
	Ascent.touch(C, st2, 0, 2, 0)
	Ascent.touch(C, st2, 0, 2, A.CrumbleSeconds * 0.9)
	ok(not Ascent.solid(C, st2, 0, 2, A.CrumbleSeconds),
		"standing on a crumbling pad does not renew it")

	-- ...but once it is back, it is a fresh pad with a fresh grace period.
	local back = A.CrumbleSeconds + A.RespawnSeconds
	Ascent.touch(C, st2, 0, 2, back)
	-- A MICROSECOND either side, not the boundary itself: (4.1 + 1.1) - 4.1 is 1.0999999999999996
	-- in doubles, so "AT the boundary" is not a question this pair of numbers can ask. The
	-- boundary IS asserted exactly, on the first cycle above, where t0 = 0 makes the subtraction
	-- exact. What this pair is for is that the SECOND cycle obeys the same rule as the first.
	ok(Ascent.solid(C, st2, 0, 2, back + A.CrumbleSeconds - 1e-6), "a respawned pad has its grace back")
	ok(not Ascent.solid(C, st2, 0, 2, back + A.CrumbleSeconds + 1e-6),
		"...and crumbles again on the same rule")

	-- EVERY pad, every shaft, comes back. Not the one the test happened to pick.
	local st3 = Ascent.new(C, model)
	for s = 0, model.storeys - 2 do
		for _, pad in ipairs(model.shafts[s + 1].pads) do Ascent.touch(C, st3, s, pad.index, 0) end
	end
	local allGone, allBack = true, true
	for s = 0, model.storeys - 2 do
		for _, pad in ipairs(model.shafts[s + 1].pads) do
			if Ascent.solid(C, st3, s, pad.index, A.CrumbleSeconds) then allGone = false end
			if not Ascent.solid(C, st3, s, pad.index, A.CrumbleSeconds + A.RespawnSeconds) then
				allBack = false
			end
		end
	end
	ok(allGone, "a shaft stood on end to end crumbles end to end")
	ok(allBack, "...and every pad in every shaft returns")
end

--============================================================================ the flips the server has to draw

do
	local st = Ascent.new(C, model)
	Ascent.touch(C, st, 0, 1, 0)
	-- update() reports only what CHANGED since the last call, because the server writes a Roblox
	-- property per change and writing CanCollide every tick for every pad in a five-storey vault
	-- is 24 replicated property writes at 5Hz for no reason.
	local none = Ascent.update(C, st, 0.1)
	eq(#none, 0, "nothing has changed yet, so nothing is reported")
	local gone = Ascent.update(C, st, A.CrumbleSeconds)
	eq(#gone, 1, "the pad falling away is one change")
	eq(gone[1].solid, false, "...and it is reported as gone")
	eq(gone[1].storey, 0, "...on the right storey")
	eq(gone[1].index, 1, "...and the right pad")
	eq(#Ascent.update(C, st, A.CrumbleSeconds + 0.1), 0, "and it is not reported twice")
	local back = Ascent.update(C, st, A.CrumbleSeconds + A.RespawnSeconds)
	eq(#back, 1, "coming back is one change")
	eq(back[1].solid, true, "...reported as solid")
end

--============================================================================ the shaft is climbable

-- THE UNWINNABLE-VAULT GUARD, in the units the climb is priced in. If a pad crumbles faster than
-- a runner can hop off it, the shaft cannot be climbed by anybody and every vault in the game is
-- a death sentence — and no test above would notice, because each of them would still pass.
do
	local hop = C.Movement.ClimbSecondsPerStep
	ok(A.CrumbleSeconds >= hop, string.format(
		"a pad crumbles %.2fs after it is touched, against a %.2fs hop — the shaft cannot be climbed",
		A.CrumbleSeconds, hop))
	-- ...and the grace is not so long that it is decoration. A runner who stops to line the jump
	-- up has to actually lose the floor.
	ok(A.CrumbleSeconds <= 3 * hop, string.format(
		"a pad holds for %.2fs, which is %.1f hops — nobody will ever see it crumble",
		A.CrumbleSeconds, A.CrumbleSeconds / hop))
	-- A fall has to cost more than shrugging it off: the pad you dropped from is still missing
	-- when you would otherwise be back on it.
	local recover = VaultPath.fallSeconds(C, model.storeyHeight / 2) + A.ModelReapproachSeconds
	ok(A.RespawnSeconds >= recover, string.format(
		"a pad is back after %.2fs but a fall only costs %.2fs — dropping off is free",
		A.RespawnSeconds, recover))

	-- ...AND AN ABSOLUTE CEILING ON THE WHOLE CYCLE, because every assertion above is stated in
	-- units of RespawnSeconds and therefore scales with it: setting it to 1e9 leaves all of them
	-- green while the shaft is destroyed for the rest of the run. The mutation gate found exactly
	-- that. The bound is the CLEAN CLIMB of one storey: a runner who misses the top hop falls,
	-- walks back, and starts at pad 1 — and pad 1 was touched a whole climb ago, so if the cycle
	-- is shorter than the climb they never wait for it. Longer, and a fall from the top means
	-- standing under a hole in the shaft while the collapse rises.
	local cycle = A.CrumbleSeconds + A.RespawnSeconds
	local climb = VaultPath.climbBaseSeconds(C, model)
	ok(cycle <= climb, string.format(
		"a pad's crumble-and-return cycle is %.2fs against a %.2fs climb — a runner who misses the "
			.. "top hop comes back to a shaft with a hole in it", cycle, climb))
end

--============================================================================ CONTROL

-- A change the module must NOT notice. Crumbling is about time and geometry; nothing in it may
-- depend on which tier the vault is, or what colour it is painted.
do
	local bronze = build(1, 1)
	local a = Ascent.new(C, bronze)
	local b = Ascent.new(C, model)
	Ascent.touch(C, a, 0, 1, 0)
	Ascent.touch(C, b, 0, 1, 0)
	eq(Ascent.solid(C, a, 0, 1, A.CrumbleSeconds), Ascent.solid(C, b, 0, 1, A.CrumbleSeconds),
		"CONTROL: a Bronze pad and a Gold pad crumble on the same clock")
	local painted = {}
	for k, v in pairs(C) do painted[k] = v end
	painted.Hud = { AccentColor = { r = 255, g = 0, b = 255 },
		DangerColor = { r = 0, g = 255, b = 0 }, PanelColor = { r = 0, g = 0, b = 0 } }
	eq(Ascent.solid(painted, a, 0, 1, A.CrumbleSeconds - 1e-6), true,
		"CONTROL: repainting the HUD does not change when a pad falls")
end

print(string.format("Ascent: %d passed, %d failed", passed, failed))
if failed > 0 then error("Ascent spec failed", 0) end
