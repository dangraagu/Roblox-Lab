-- Spec for VaultEnv: where in the vault the player is, and what the environment may do about it.
-- Run: luau tests/VaultEnv.spec.luau
--
-- The vault-specific half of the eye candy (the game-agnostic half is EnvBands / Hazards / Rest,
-- copied from +1 Jump). Every rule here is one the brief or the repo's history makes load-bearing:
--   * DEPTH is the progress value: the floor you are running, plus how deep the tier's vault is
--     buried. It comes from the run the server started, never from a clock;
--   * a ceiling drop never lands in the climb shaft, near the hole in the floor above the shaft,
--     in the first seconds of a run, in the last seconds before the seal, or with the collapse
--     close behind: the obby's pads stay readable and nothing the budget prices is disturbed;
--   * decoration is placed from (storey, cell, seed) ONLY. It never reads the maze, the route or
--     the gems, so it cannot tell a player which way the exit is (fork-tower/REVIEW-3.md,
--     anomaly-observatory/CLAUDE.md: this repo has closed replication leaks before);
--   * the danger reading is the real collapse: the kill plane's height against the runner's.
local VaultEnv = require("../src/shared/VaultEnv")
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local VaultFloor = require("../src/shared/VaultFloor")
local MazeGen = require("../src/shared/MazeGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local function build(tier: number, floor: number, seed: number?): any
	local spec = Progression.difficulty(Config, tier, floor)
	spec.seed = seed or Progression.seedFor(Config, tier, floor)
	return VaultFloor.build(Config, spec, MazeGen, Rng), spec
end

-- vault-local root position of a runner standing in fine cell (fx, fy) of storey s
local function standAt(model: any, s: number, fx: number, fy: number, dx: number?, dz: number?): any
	local S = model.cellSize
	return {
		x = (fx - (model.gCols - 1) / 2) * S + (dx or 0),
		y = s * model.storeyHeight + Config.Run.RunnerRootHeight,
		z = (fy - (model.gRows - 1) / 2) * S + (dz or 0),
	}
end

--================================================================ depth

do
	local D = Config.Env.TierDepth
	eq(#D, #Config.Tiers, "every tier has a depth")
	eq(VaultEnv.depth(Config, 1, 1), D[1] + 1, "Bronze floor 1 is depth TierDepth[1] + 1")
	eq(VaultEnv.depth(Config, 2, 7), D[2] + 7, "Silver floor 7 is TierDepth[2] + 7")
	for t = 1, #Config.Tiers do
		local flatAt = nil
		for f = 1, 1000 do
			if flatAt == nil and VaultEnv.depth(Config, t, f + 1) <= VaultEnv.depth(Config, t, f) then flatAt = f end
		end
		eq(flatAt, nil, "depth grows with every floor inside tier " .. t .. " (floors 1..1000)")
	end
	for t = 2, #Config.Tiers do
		truthy(D[t] > D[t - 1], "a harder tier's vault is buried deeper (tier " .. t .. ")")
	end
	eq(VaultEnv.depth(Config, 1, 0), VaultEnv.depth(Config, 1, 1), "a floor below 1 reads as floor 1")
	eq(VaultEnv.depth(Config, 9, 3), VaultEnv.depth(Config, 1, 3), "an unknown tier reads as the first (a bad remote costs nothing)")
end

do
	-- deepest cleared, from the floors the server already pushes (next floor per tier)
	eq(VaultEnv.deepestCleared(Config, { 1, 1, 1 }), 0, "nothing cleared is depth 0")
	eq(VaultEnv.deepestCleared(Config, { 6, 1, 1 }), Config.Env.TierDepth[1] + 5, "Bronze floor 6 next = floor 5 cleared")
	eq(VaultEnv.deepestCleared(Config, { 30, 3, 1 }), math.max(Config.Env.TierDepth[1] + 29, Config.Env.TierDepth[2] + 2),
		"the deepest of all tiers")
	eq(VaultEnv.deepestCleared(Config, { ["1"] = 4, ["2"] = 1 }), Config.Env.TierDepth[1] + 3,
		"string keys (a JSON round trip) read the same")
	eq(VaultEnv.deepestCleared(Config, nil), 0, "no state yet is depth 0")
end

--================================================================ locate

do
	local m = build(3, 1)
	local s = 2
	local ex = m.exitCells[s + 1]
	local fx, fy = 2 * ex.cx + 1, 2 * ex.cy + 1
	local loc = VaultEnv.locate(Config, m, standAt(m, s, fx, fy, 2.5, -2.5))
	eq(loc.storey, s, "a runner standing on storey 2 is on storey 2")
	eq(loc.fx, fx, "in the right fine column")
	eq(loc.fy, fy, "and row")
	eq(loc.onFloor, true, "standing on the floor")
	eq(loc.inside, true, "inside the footprint")
	local pad = m.shafts[s + 1].pads[3]
	local onPad = VaultEnv.locate(Config, m, { x = pad.x, y = pad.y + Config.Run.RunnerRootHeight, z = pad.z })
	eq(onPad.storey, s, "a runner on pad 3 of storey 2's shaft is still on storey 2")
	eq(onPad.onFloor, false, "but NOT on the floor")
	local out = VaultEnv.locate(Config, m, { x = m.footprint.w, y = 3, z = 0 })
	eq(out.inside, false, "outside the footprint is outside")
	local top = VaultEnv.locate(Config, m, standAt(m, m.storeys - 1, 3, 3))
	eq(top.storey, m.storeys - 1, "the top storey is found")
	local under = VaultEnv.locate(Config, m, { x = 0, y = -50, z = 0 })
	eq(under.storey, 0, "below the vault clamps to storey 0")
	eq(under.onFloor, false, "and is not standing on anything")
end

--================================================================ where a drop may land

local RUN_OK = { elapsed = 60, timeLeft = 120, danger = 0 }

do
	local H = Config.Hazards
	local m = build(3, 1)
	-- every fine cell of every storey: the shaft cell, the hole cell and their neighbours refuse
	local refusedShaft, refusedHole, allowed = 0, 0, 0
	local leak = nil
	for s = 0, m.storeys - 1 do
		local ex, en = m.exitCells[s + 1], m.entryCells[s + 1]
		local efx, efy = 2 * ex.cx + 1, 2 * ex.cy + 1
		local hfx, hfy = 2 * en.cx + 1, 2 * en.cy + 1
		for fy = 1, m.gRows - 2 do
			for fx = 1, m.gCols - 2 do
				if m.grids[s + 1][fy][fx] == false then
					local ok = VaultEnv.hazardEligible(Config, m, standAt(m, s, fx, fy), RUN_OK)
					local nearShaft = math.max(math.abs(fx - efx), math.abs(fy - efy)) < H.ShaftMarginCells
					local nearHole = math.max(math.abs(fx - hfx), math.abs(fy - hfy)) < H.ShaftMarginCells
					if nearShaft then
						if ok then leak = leak or string.format("storey %d cell %d,%d next to the shaft", s, fx, fy) end
						refusedShaft += 1
					elseif nearHole then
						if ok then leak = leak or string.format("storey %d cell %d,%d next to the hole", s, fx, fy) end
						refusedHole += 1
					else
						if not ok then leak = leak or string.format("storey %d cell %d,%d refused for no reason", s, fx, fy) end
						allowed += 1
					end
				end
			end
		end
	end
	eq(leak, nil, "a drop may land exactly where it should: not by the shaft, not by the hole, everywhere else")
	truthy(refusedShaft > 0 and refusedHole > 0 and allowed > 0,
		string.format("(checked: %d near the shaft, %d near the hole, %d open)", refusedShaft, refusedHole, allowed))
	-- ...and the ring cannot reach the hole from any allowed cell
	local worst = math.huge
	for s = 1, m.storeys - 1 do
		local en = m.entryCells[s + 1]
		local hx = (2 * en.cx + 1 - (m.gCols - 1) / 2) * m.cellSize
		local hz = (2 * en.cy + 1 - (m.gRows - 1) / 2) * m.cellSize
		for fy = 1, m.gRows - 2 do
			for fx = 1, m.gCols - 2 do
				if m.grids[s + 1][fy][fx] == false then
					for _, d in { { -5.9, -5.9 }, { 5.9, 5.9 }, { -5.9, 5.9 }, { 5.9, -5.9 }, { 0, 0 } } do
						local p = standAt(m, s, fx, fy, d[1], d[2])
						if VaultEnv.hazardEligible(Config, m, p, RUN_OK) then
							-- distance from the runner to the nearest point of the hole's square
							local dx = math.max(0, math.abs(p.x - hx) - m.cellSize / 2)
							local dz = math.max(0, math.abs(p.z - hz) - m.cellSize / 2)
							worst = math.min(worst, math.sqrt(dx * dx + dz * dz))
						end
					end
				end
			end
		end
	end
	local ringR = 0
	for _, k in H.Kinds do ringR = math.max(ringR, k.hitRadius + H.PlayerRadius) end
	truthy(worst > ringR + H.KnockClearStuds,
		string.format("from every allowed spot the hole is %.1f studs away: more than the widest ring (%.1f) plus the knock's slide (%.1f)",
			worst, ringR, H.KnockClearStuds))
end

do
	local H = Config.Hazards
	local m = build(1, 1)
	local s = 0
	-- find an allowed cell
	local p = nil
	for fy = 1, m.gRows - 2 do
		for fx = 1, m.gCols - 2 do
			if p == nil and m.grids[1][fy][fx] == false and VaultEnv.hazardEligible(Config, m, standAt(m, s, fx, fy), RUN_OK) then
				p = standAt(m, s, fx, fy)
			end
		end
	end
	truthy(p ~= nil, "Bronze floor 1 storey 0 has somewhere a drop may land")
	if p then
		local function why(run: any, pos: any?): string?
			local ok, reason = VaultEnv.hazardEligible(Config, m, pos or p, run)
			return if ok then nil else reason
		end
		eq(why({ elapsed = H.GraceSeconds - 0.1, timeLeft = 100, danger = 0 }), "grace", "not in the first GraceSeconds of a run")
		eq(why({ elapsed = H.GraceSeconds, timeLeft = 100, danger = 0 }), nil, "(and from GraceSeconds on it may)")
		eq(why({ elapsed = 60, timeLeft = H.QuietBeforeSealSeconds - 0.1, danger = 0 }), "seal", "not in the last seconds before the seal")
		eq(why({ elapsed = 60, timeLeft = 100, danger = H.MaxDanger + 0.01 }), "collapse", "not with the collapse close behind")
		eq(why(RUN_OK, { x = p.x, y = p.y + 4, z = p.z }), "floor", "not in mid-air or on a pad")
		eq(why(RUN_OK, { x = m.footprint.w, y = p.y, z = 0 }), "outside", "not outside the vault")
		eq(why(nil), "norun", "not without a run")
	end
end

--================================================================ danger is the real collapse

do
	local m = build(2, 1)
	local root = 1 * m.storeyHeight + Config.Run.RunnerRootHeight -- standing on storey 1
	local kill = root - m.killMargin -- plane height at which RunState.caught fires
	approx(VaultEnv.danger(Config, m, kill, root), 1, "at the kill line danger is 1")
	approx(VaultEnv.danger(Config, m, kill - Config.Env.DangerStuds, root), 0, "DangerStuds below it danger is 0")
	approx(VaultEnv.danger(Config, m, kill - 1000, root), 0, "far below, 0")
	approx(VaultEnv.danger(Config, m, kill + 5, root), 1, "above the kill line (a dead runner) still 1")
	local prev = -1
	local mono = true
	for i = 0, 100 do
		local d = VaultEnv.danger(Config, m, kill - Config.Env.DangerStuds + i * Config.Env.DangerStuds / 100, root)
		if d < prev - 1e-12 then mono = false end
		prev = d
	end
	truthy(mono, "danger only rises as the plane rises")
	-- at the drop-in the collapse is exactly one storey behind storey 0: calm, not alarming
	local start = m.killPlane.startY
	approx(VaultEnv.danger(Config, m, start, Config.Run.RunnerRootHeight), 0, "at the drop-in the danger reads 0")
end

--================================================================ decoration never reads the maze

do
	local a = build(3, 1, 111)
	local b = build(3, 1, 222) -- same size, a different maze
	truthy(a.cells == b.cells, "(two mazes of the same size)")
	local differs = false
	for s = 0, a.storeys - 1 do
		for fy = 0, a.gRows - 1 do
			for fx = 0, a.gCols - 1 do
				if a.grids[s + 1][fy][fx] ~= b.grids[s + 1][fy][fx] then differs = true end
			end
		end
	end
	truthy(differs, "(whose walls differ)")
	local same = true
	for s = 0, a.storeys - 1 do
		local sa = VaultEnv.propSites(a, s, 777, 0.4)
		local sb = VaultEnv.propSites(b, s, 777, 0.4)
		if #sa ~= #sb then same = false end
		for i = 1, math.min(#sa, #sb) do
			if sa[i].cx ~= sb[i].cx or sa[i].cy ~= sb[i].cy or sa[i].roll ~= sb[i].roll then same = false end
		end
	end
	eq(same, true, "prop sites depend on (storey, cell, seed) only: two different mazes get identical sites")
	local sites = VaultEnv.propSites(a, 1, 777, 0.4)
	local bad = nil
	for _, st in sites do
		local en, ex = a.entryCells[2], a.exitCells[2]
		if (st.cx == en.cx and st.cy == en.cy) or (st.cx == ex.cx and st.cy == ex.cy) then bad = st end
		if st.cx < 0 or st.cy < 0 or st.cx >= a.cells or st.cy >= a.cells then bad = st end
	end
	eq(bad, nil, "no prop hangs in the shaft cell or over the hole (both are fixed corners, not the route)")
	local total = 0
	for s = 0, a.storeys - 1 do total += #VaultEnv.propSites(a, s, 777, 0.4) end
	local possible = a.storeys * (a.cells * a.cells - 2)
	truthy(total > possible * 0.25 and total < possible * 0.55,
		string.format("density 0.4 hangs about 40%% of cells (%d of %d)", total, possible))
	eq(#VaultEnv.propSites(a, 0, 777, 0), 0, "density 0 hangs nothing")
	truthy(#VaultEnv.propSites(a, 0, 778, 0.4) >= 0, "(another seed runs)")
	local x = VaultEnv.propSites(a, 0, 777, 0.4)
	local y = VaultEnv.propSites(a, 0, 778, 0.4)
	local moved = #x ~= #y
	for i = 1, math.min(#x, #y) do
		if x[i].cx ~= y[i].cx or x[i].cy ~= y[i].cy then moved = true end
	end
	truthy(moved, "a different floor seed hangs them differently (floors do not all look the same)")
end

--================================================================ readability arithmetic

do
	approx(VaultEnv.contrast({ 255, 255, 255 }, { 0, 0, 0 }), 21, "white on black is 21:1", 1e-6)
	approx(VaultEnv.contrast({ 128, 128, 128 }, { 128, 128, 128 }), 1, "a colour on itself is 1:1")
	approx(VaultEnv.contrast({ 0, 0, 0 }, { 255, 255, 255 }), 21, "and it is symmetric")
end

--================================================================ the pad is chosen, not blended

do
	local dark, light = { 20, 20, 24 }, { 240, 240, 236 }
	local cyan, navy = { 124, 236, 255 }, { 40, 92, 160 }
	local p = VaultEnv.readablePad(dark, { navy, cyan }, 3)
	eq(p, cyan, "over a dark floor the lighter candidate is chosen")
	p = VaultEnv.readablePad(light, { cyan, navy }, 3)
	eq(p, navy, "over a light floor the darker one")
	local grey = { 132, 140, 149 }
	local fallback = VaultEnv.readablePad(grey, { cyan, navy }, 3)
	truthy(fallback ~= cyan and fallback ~= navy, "when neither candidate reaches 3:1 over a mid grey, neither is used")
	truthy(VaultEnv.contrast(fallback, grey) >= 3, string.format("and the fallback reads (%.1f:1)", VaultEnv.contrast(fallback, grey)))
	-- palette at a pure band vs a blend
	local EnvBands = { locate = function(_, d) if d < 1 then return 1, 1, 0 end return 1, 2, 0.5 end }
	local cfg = { Env = { MinPadContrast = 3, CrackBlend = 0.7, Bands = {
		{ palette = { wall = { 10, 10, 10 }, floor = dark, pad = cyan, accent = { 1, 2, 3 }, glow = { 4, 5, 6 }, crack = { 255, 90, 50 }, wallReflect = 0 } },
		{ palette = { wall = { 30, 30, 30 }, floor = light, pad = navy, accent = { 7, 8, 9 }, glow = { 10, 11, 12 }, crack = { 255, 90, 50 }, wallReflect = 0.2 } },
	} } }
	local pure = VaultEnv.palette(cfg, EnvBands, 0)
	eq(pure.pad[1], cyan[1], "a pure band paints its own pad")
	eq(pure.floor[1], dark[1], "and its own floor")
	local mid = VaultEnv.palette(cfg, EnvBands, 5)
	approx(mid.wall[1], 20, "walls blend halfway")
	approx(mid.wallReflect, 0.1, "and so does their shine")
	eq(mid.floor[1], light[1], "the floor is the dominant band's own (t = 0.5 goes to the band blending in), never a grey in between")
	truthy(VaultEnv.contrast(mid.pad, mid.floor) >= 3, "and the pad stands out on it")
	local cracked = VaultEnv.crackedPad(cfg, pure, 1)
	approx(cracked[1], cyan[1] + (255 - cyan[1]) * 0.7, "a fully cracked pad is CrackBlend of the way to the crack colour")
	local half = VaultEnv.crackedPad(cfg, pure, 0.5)
	approx(half[1], cyan[1] + (255 - cyan[1]) * 0.35, "halfway through its crumble, half as far")
	eq(VaultEnv.crackedPad(cfg, pure, 0)[1], cyan[1], "an untouched pad is its own colour")
end

--================================================================ the pad's look follows the SERVER's pad
-- (review finding: the crack used to run on this client's own clock and vanish 1.1 s after the
-- landing, while the server — whose timer starts when its TRUSTED position reaches the pad, ticks
-- every 0.2 s and replicates back — dropped the pad 0.07-0.25 s later, plus ping. The pad read
-- WHOLE, or flashed "it's back", in the one moment a jump would still have saved the runner.)
-- VaultEnv.padLook returns "whole", "crack" + progress 0..1, "flash" + what is left of it 1..0, or
-- "gone".

do
	local cfg = { Ascent = { CrumbleSeconds = 1.1 }, Env = { CrackHoldSeconds = 1.5, PadFlashSeconds = 0.45 } }
	local C, HOLD, FLASH = 1.1, 1.5, 0.45
	-- the crack's progress, or nil when the pad is not cracking
	local function crack(st, standing, gone, now)
		local look, amount = VaultEnv.padLook(cfg, st, standing, gone, now)
		return if look == "crack" then amount else nil
	end
	local st = {}
	eq(VaultEnv.padLook(cfg, st, false, false, 0), "whole", "an untouched pad nobody stands on is whole")
	approx(crack(st, true, false, 10), 0, "the landing starts the crack at 0")
	approx(crack(st, true, false, 10 + C / 2), 0.5, "halfway through the crumble, half cracked")
	approx(crack(st, true, false, 10 + C), 1, "fully cracked at CrumbleSeconds")
	approx(crack(st, true, false, 10 + C + 0.25), 1,
		"the server has not dropped it yet: the crack is HELD at full, never whole again")
	approx(crack(st, true, false, 10 + C + 30), 1,
		"and it stays held while the runner still stands on it: the server will count that stand")
	eq(VaultEnv.padLook(cfg, st, true, true, 10 + C + 30.1), "gone", "the server dropped it: nothing is drawn on a pad that is gone")
	eq(VaultEnv.padLook(cfg, st, true, true, 42), "gone", "(still gone, whatever the client thinks it stands on)")
	local look, left = VaultEnv.padLook(cfg, st, false, false, 45)
	eq(look, "flash", "it came back: it flashes, and no crack is carried over")
	approx(left, 1, "(the whole flash is still to come)")
	local _, half = VaultEnv.padLook(cfg, st, false, false, 45 + FLASH / 2)
	approx(half, 0.5, "the flash fades over PadFlashSeconds")
	eq(VaultEnv.padLook(cfg, st, false, false, 45 + FLASH + 0.01), "whole", "and then it is a whole, fresh pad")
	approx(crack(st, true, false, 50), 0, "landing on the returned pad starts a new crack from 0")

	-- stepped off before the server dropped it: held for CrackHoldSeconds past the crumble, then let go
	local s2 = {}
	crack(s2, true, false, 0)
	approx(crack(s2, false, false, 0.3), 0.3 / C, "(stepped off at 0.3 s: the crack keeps spreading)")
	approx(crack(s2, false, false, C + HOLD - 0.01), 1, "held at full until CrackHoldSeconds past the crumble")
	eq(VaultEnv.padLook(cfg, s2, false, false, C + HOLD + 0.01), "whole",
		"then let go: the server never dropped it, so it never counted a stand (a pad brushed on the way past)")
	approx(crack(s2, true, false, C + HOLD + 0.5), 0, "and a later landing cracks it afresh")

	-- a runner already on a pad when it comes back (arriving mid-air): the crack starts the moment it is back
	local s3 = {}
	crack(s3, true, false, 0)
	VaultEnv.padLook(cfg, s3, true, true, 1.3)
	approx(crack(s3, true, false, 4.4), 0, "a pad that returns under a runner starts its crack when it returns (no flash first)")
	approx(crack(s3, true, false, 4.4 + C / 2), 0.5, "and runs from there")

	-- landed on while it still flashed "it's back": the crack wins, and the flash never resumes
	local s4 = {}
	crack(s4, true, false, 0)
	VaultEnv.padLook(cfg, s4, false, true, 1.3)
	eq(VaultEnv.padLook(cfg, s4, false, false, 4.4), "flash", "(back, flashing)")
	approx(crack(s4, true, false, 4.5), 0, "a landing 0.1 s into the flash cracks the pad at once")
	approx(crack(s4, false, false, 4.6), 0.1 / C, "(stepped off again at once)")
	local sawFlash = false
	for i = 1, 400 do
		local l = VaultEnv.padLook(cfg, s4, false, false, 4.6 + i * 0.01)
		if l == "flash" then sawFlash = true end
	end
	eq(sawFlash, false, "and when that crack is let go the old flash does not come back: nothing came back")
	eq(VaultEnv.padLook(cfg, s4, false, false, 9), "whole", "(whole)")

	-- the rule does not lean on the shipped timings (a crack outlasts a 0.45 s flash anyway): even a
	-- long flash is cancelled for good by a crack
	local long = { Ascent = { CrumbleSeconds = 1.1 }, Env = { CrackHoldSeconds = 1.5, PadFlashSeconds = 10 } }
	local s5 = {}
	VaultEnv.padLook(long, s5, false, true, 0)
	eq(VaultEnv.padLook(long, s5, false, false, 1), "flash", "(back, with a ten-second flash)")
	eq(VaultEnv.padLook(long, s5, true, false, 1.1), "crack", "(landed on: cracking)")
	VaultEnv.padLook(long, s5, false, false, 1.2)
	eq(VaultEnv.padLook(long, s5, false, false, 1.1 + C + HOLD + 0.01), "whole",
		"a crack cancels the flash for good, whatever the timings: once let go the pad is whole, not 'back'")
end

--================================================================ gems stay findable
-- (review finding: the client repaints walls and floors per stratum but the gems kept the tier's
-- colour — Silver's pale blue on the Frozen Vault's ice read 1.10:1 against the wall, Bronze's orange
-- on the tomb's sandstone 1.16:1.)

do
	local tierGem = { 168, 226, 255 } -- pale ice blue
	local darkFloor, darkWall = { 34, 26, 26 }, { 58, 44, 42 }
	local iceFloor, iceWall = { 226, 238, 246 }, { 176, 214, 236 }
	local sapphire, gold = { 40, 80, 200 }, { 255, 226, 120 }
	eq(VaultEnv.readableGem(tierGem, darkFloor, darkWall, { gold }, 3, 1.8), tierGem, "where the tier's own gem colour reads, it is kept")
	eq(VaultEnv.readableGem(tierGem, iceFloor, iceWall, { gold, sapphire }, 3, 1.8), sapphire,
		"where it would vanish, the stratum's gem that reads is used instead")
	local navy = { 20, 20, 120 }
	eq(VaultEnv.readableGem(tierGem, iceFloor, iceWall, { sapphire, navy }, 3, 1.8), navy,
		"of two stratum gems that both read, the one that reads better (a blend floor has two)")
	local fb = VaultEnv.readableGem(tierGem, iceFloor, iceWall, { gold }, 3, 1.8)
	truthy(fb ~= gold and fb ~= tierGem, "when no candidate reads, neither the tier's nor the candidate is used")
	truthy(VaultEnv.contrast(fb, iceFloor) >= 3 and VaultEnv.contrast(fb, iceWall) >= 1.8,
		string.format("and the black-or-white fallback reads (%.1f:1 floor, %.1f:1 wall)", VaultEnv.contrast(fb, iceFloor), VaultEnv.contrast(fb, iceWall)))
	-- through a palette: the candidates are the two blending bands' own gems
	local cfg = {
		Tiers = { { gemColor = { r = 168, g = 226, b = 255 } } },
		Env = { MinGemContrast = 3, MinGemWallContrast = 1.8, Bands = {
			{ palette = { gem = gold } }, { palette = { gem = sapphire } },
		} },
	}
	local g = VaultEnv.gem(cfg, { floor = iceFloor, wall = iceWall, band = 1, next = 2, t = 0.6 }, 1)
	eq(g[1] == sapphire[1] and g[2] == sapphire[2] and g[3] == sapphire[3], true, "VaultEnv.gem picks from the blending bands' gems")
	local k = VaultEnv.gem(cfg, { floor = darkFloor, wall = darkWall, band = 1, next = 1, t = 0 }, 1)
	eq(k[1] == 168 and k[2] == 226 and k[3] == 255, true, "and keeps the tier's colour where it reads")
	g[1] = 0
	eq(sapphire[1], 40, "it hands out a fresh array, never the band's own table")
end

--================================================================ the drop's ring stays visible
-- (review finding: the yellow ring, Neon at 0.35 transparency, read 1.16:1 on the Frozen Vault's
-- snow — the telegraph's danger zone, invisible for its first two seconds.)

do
	local snow, dark = { 226, 238, 246 }, { 34, 26, 26 }
	local over = VaultEnv.ringOver({ 255, 0, 0 }, 0.25, { 0, 0, 255 })
	approx(over[1], 191.25, "the ring is seen over the floor: colour x (1 - transparency) + floor x transparency (R)")
	approx(over[3], 63.75, "(B)")
	local yellow = { color = { 255, 210, 60 }, transparency = 0.35 }
	local gold = { color = { 140, 100, 0 }, transparency = 0.15 }
	eq(VaultEnv.readableRing(dark, { yellow, gold }, 3), yellow, "the first candidate that reads is used (yellow on a dark floor)")
	eq(VaultEnv.readableRing(snow, { yellow, gold }, 3), gold, "and on snow, where yellow vanishes, the next one")
	local best = VaultEnv.readableRing(snow, { yellow, { color = { 255, 255, 255 }, transparency = 0.35 } }, 3)
	eq(best, yellow, "when none reads, the one that reads best (never nothing)")
	local cfg = { Env = { MinRingContrast = 3, RingFollow = { yellow, gold }, RingLock = { { color = { 170, 0, 20 }, transparency = 0.25 } } } }
	eq(VaultEnv.ring(cfg, snow, false), gold, "VaultEnv.ring reads the follow candidates while the ring follows")
	eq(VaultEnv.ring(cfg, snow, true), cfg.Env.RingLock[1], "and the lock candidates once it locks")
end

--================================================================ the shaft

do
	local m = build(3, 1)
	local s = 1
	local ex = m.exitCells[s + 1]
	eq(VaultEnv.inShaft(Config, m, standAt(m, s, 2 * ex.cx + 1, 2 * ex.cy + 1)), true, "the stairwell cell is the shaft")
	local pad = m.shafts[s + 1].pads[4]
	eq(VaultEnv.inShaft(Config, m, { x = pad.x, y = pad.y + 3, z = pad.z }), true, "and so is standing on a pad")
	eq(VaultEnv.inShaft(Config, m, standAt(m, s, 3, 3)), 3 == 2 * ex.cx + 1 and 3 == 2 * ex.cy + 1, "an ordinary corridor is not")
end

print(string.format("VaultEnv: %d passed, %d failed", passed, failed))
