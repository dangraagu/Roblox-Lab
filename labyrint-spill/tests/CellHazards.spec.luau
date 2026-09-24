-- Spec for CellHazards: rare, telegraphed hazards that fall into a maze cell. Run: luau tests/CellHazards.spec.luau
--
-- The labyrinth is a TIMED game with medal times from a shared seed, so a hazard here cannot be a
-- dice roll: two players on level 140 must meet the same icicles at the same moments of their run,
-- exactly like the lava traps. What this spec pins:
--   * placement is a pure function of (level, maze size, trap cells): no RNG state, no clock, no
--     player; never on the start, the exit, a trap cell, or near the start;
--   * timing is a fixed per-cell cycle on the LEVEL clock: a warning of at least MinWarnSeconds,
--     one impact instant, debris; the first impact never inside the level's grace period;
--   * the danger zone (strike + player radius) fits inside the cell, so the passage next to it is
--     always a safe place to wait: a hazard can delay you, it can never wall a level off;
--   * a hit knocks you down in place with a small, capped push that cannot carry you onto the
--     neighbouring cell's trap.
local CellHazards = require("../src/shared/CellHazards")
local EnvBands = require("../src/shared/EnvBands")
local Biomes = require("../src/shared/Biomes")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local CFG = Biomes.Hazards
local SEED = Biomes.Seed

--================================================================ validate

do
	local ok, err = CellHazards.validate(CFG)
	truthy(ok, "the shipped hazard config validates (" .. tostring(err) .. ")")
end
local function mutated(key, value)
	local c = table.clone(CFG)
	c[key] = value
	return (CellHazards.validate(c))
end
eq(mutated("WarnSeconds", 1.0), false, "a warning shorter than MinWarnSeconds is rejected (easy to see coming)")
eq(mutated("MinWarnSeconds", 1.0), false, "MinWarnSeconds itself cannot drop below 2 s")
eq(mutated("Period", CFG.WarnSeconds + 1), false, "a cycle with no quiet gap after the warning is rejected")
eq(mutated("StrikeRadius", 4.0), false, "a danger zone wider than the cell is rejected (the passage must stay a safe spot)")
eq(mutated("KnockPush", 30), false, "a knock that could carry you to the next cell's trap is rejected")
eq(mutated("GraceSeconds", 1), false, "a first impact inside the warning of the level start is rejected")
eq(mutated("Density", 0.5), false, "a hazard in every other cell is rejected (rare)")
eq(mutated("CellSize", 7), false, "the cell size must be the server's CONFIG.CellSize (9)")
eq(mutated("MaxHitHeight", 8), false, "an impact that a jump could clear is rejected (only stepping out of the ring dodges)")
eq(mutated("MaxHitHeight", nil), false, "a config without MaxHitHeight is rejected")
eq(CFG.CellSize, 9, "CellSize mirrors the server")
truthy(CFG.StrikeRadius + CFG.PlayerRadius <= CFG.CellSize / 2, "the danger zone fits in the cell")
truthy(CFG.KnockPush * CFG.KnockSeconds <= CFG.MaxKnockDisplacement, "knock displacement is capped")
truthy(CFG.ShowRadius <= Biomes.Base.locked.TorchRange - 2,
	"hazards are drawn only inside the torch's reach (a glowing ring must not reveal a cell the torch does not light)")
truthy(CFG.ShowRadius >= CFG.CellSize + CFG.StrikeRadius + CFG.PlayerRadius + 4,
	"but far enough out to be seen from the passage before the cell, with room to stop")
truthy(CFG.NearRadius < CFG.ShowRadius, "every near-hit happens where the hazard is drawn")
truthy(CFG.StrikeRadius + CFG.PlayerRadius + CFG.MaxKnockDisplacement < 2 * CFG.CellSize - (CFG.CellSize - 2) / 2 - CFG.PlayerRadius,
	"even the farthest knock stays clear of the next cell's trap footprint")

--================================================================ placement

local function trapSet(list)
	local s = {}
	for _, c in list do s[c[1] .. "," .. c[2]] = true end
	return s
end

do
	local traps = trapSet({ { 3, 3 }, { 5, 1 }, { 8, 8 }, { 12, 4 } })
	local a = CellHazards.pick(140, 20, 20, traps, SEED, CFG)
	local b = CellHazards.pick(140, 20, 20, traps, SEED, CFG)
	eq(#a, #b, "placement is deterministic (count)")
	local same = true
	for i = 1, #a do
		if a[i].cx ~= b[i].cx or a[i].cy ~= b[i].cy or a[i].phase ~= b[i].phase then same = false end
	end
	truthy(same, "placement is deterministic (cells and phases): everyone on level 140 meets the same hazards")
	truthy(#a >= 1, "a 20x20 maze gets at least one hazard")
	local c = CellHazards.pick(141, 20, 20, traps, SEED, CFG)
	local differs = #a ~= #c
	for i = 1, math.min(#a, #c) do
		if a[i].cx ~= c[i].cx or a[i].cy ~= c[i].cy then differs = true end
	end
	truthy(differs, "the next level places its hazards elsewhere")
end

-- every exclusion, over many levels and sizes
do
	local bad = 0
	local total, eligibleTotal = 0, 0
	local spacingBad = 0
	for L = 1, 400 do
		local size = 6 + (L % 25)
		local traps = {}
		for i = 1, (L % 13) do
			traps[((L * 7 + i * 13) % size) .. "," .. ((L * 3 + i * 5) % size)] = true
		end
		local list = CellHazards.pick(L, size, size, traps, SEED, CFG)
		total += #list
		eligibleTotal += size * size
		for i, hz in list do
			if hz.cx < 0 or hz.cy < 0 or hz.cx >= size or hz.cy >= size then bad += 1 end
			if hz.cx == 0 and hz.cy == 0 then bad += 1 end
			if hz.cx == size - 1 and hz.cy == size - 1 then bad += 1 end
			if traps[hz.cx .. "," .. hz.cy] then bad += 1 end
			if math.max(hz.cx, hz.cy) <= CFG.StartClearCells then bad += 1 end
			if hz.phase < 0 or hz.phase >= CFG.Period then bad += 1 end
			for j = i + 1, #list do
				local o = list[j]
				if math.max(math.abs(o.cx - hz.cx), math.abs(o.cy - hz.cy)) < CFG.MinSpacing then spacingBad += 1 end
			end
		end
		if #list > CFG.MaxPerLevel then bad += 1 end
	end
	eq(bad, 0, "never on start, exit, a trap, near the start, outside the maze, or over the per-level cap")
	eq(spacingBad, 0, "two hazards are never closer than MinSpacing cells")
	local share = total / eligibleTotal
	truthy(share > CFG.Density * 0.5 and share <= CFG.Density * 1.05,
		string.format("about Density of the cells carry a hazard (%.4f vs %.4f)", share, CFG.Density))
end
eq(#CellHazards.pick(1, 2, 2, {}, SEED, CFG), 0, "a maze too small to keep hazards off the start gets none")

--================================================================ timeline

do
	local hz = { cx = 4, cy = 4, phase = 2.0 }
	local first = CellHazards.firstImpact(hz, CFG)
	approx(first, CFG.GraceSeconds + 2.0, 1e-9, "the first impact comes after the grace period plus the cell's phase")
	truthy(first >= CFG.GraceSeconds, "never inside the grace period")
	eq(CellHazards.stateAt(hz, 0, CFG), "idle", "the level starts quiet")
	eq(CellHazards.stateAt(hz, first - CFG.WarnSeconds - 0.01, CFG), "idle", "quiet until the warning")
	eq(CellHazards.stateAt(hz, first - CFG.WarnSeconds + 0.01, CFG), "warn", "then the warning")
	eq(CellHazards.stateAt(hz, first - 0.01, CFG), "warn", "the warning lasts right up to the impact")
	eq(CellHazards.stateAt(hz, first + 0.01, CFG), "debris", "then debris")
	eq(CellHazards.stateAt(hz, first + CFG.DebrisSeconds + 0.01, CFG), "idle", "then quiet again")
	eq(CellHazards.stateAt(hz, first + CFG.Period - CFG.WarnSeconds + 0.01, CFG), "warn", "and it repeats every Period")
	local _, prog = CellHazards.stateAt(hz, first - CFG.WarnSeconds / 2, CFG)
	approx(prog, 0.5, 1e-6, "warning progress runs 0 -> 1")
	approx(CellHazards.nextImpact(hz, first - 1, CFG), first, 1e-9, "nextImpact before the first")
	approx(CellHazards.nextImpact(hz, first + 0.001, CFG), first + CFG.Period, 1e-9, "nextImpact after it")

	local imp = CellHazards.impactsBetween(hz, 0, first + 3 * CFG.Period + 0.5, CFG)
	eq(#imp, 4, "impactsBetween counts every impact in (t0, t1]")
	eq(#CellHazards.impactsBetween(hz, first, first + CFG.Period - 0.1, CFG), 0, "(t0, t1] excludes t0")
	eq(#CellHazards.impactsBetween(hz, first - 0.1, first, CFG), 1, "(t0, t1] includes t1")
	eq(#CellHazards.impactsBetween(hz, 5, 4, CFG), 0, "an empty window has no impacts")
	-- the warning of every impact is at least MinWarnSeconds long, measured over 50 cycles
	local shortest = math.huge
	local t = 0
	local warnStart = nil
	while t < first + 50 * CFG.Period do
		local s = CellHazards.stateAt(hz, t, CFG)
		if s == "warn" and warnStart == nil then warnStart = t end
		if s ~= "warn" and warnStart ~= nil then shortest = math.min(shortest, t - warnStart); warnStart = nil end
		t += 0.01
	end
	truthy(shortest >= CFG.MinWarnSeconds - 0.02, string.format("every warning lasts >= MinWarnSeconds (shortest %.2f s)", shortest))
end

--================================================================ hits + knock

do
	local hz = { cx = 4, cy = 4, phase = 0 }
	local centre = { x = 100, y = 3, z = 50 }
	local T = CellHazards.firstImpact(hz, CFG)
	local R = CFG.StrikeRadius + CFG.PlayerRadius
	truthy(CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = 3, z = 50 }, CFG), "standing on the spot at the impact is a hit")
	truthy(CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100 + R - 0.01, y = 3, z = 50 }, CFG), "the edge of the zone is a hit")
	truthy(not CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100 + R + 0.01, y = 3, z = 50 }, CFG), "just outside the zone is not")
	truthy(not CellHazards.checkHit(hz, centre, T + 0.01, T + 0.1, { x = 100, y = 3, z = 50 }, CFG), "after the impact the spot is safe (debris is harmless)")
	truthy(not CellHazards.checkHit(hz, centre, T - 2, T - 0.01, { x = 100, y = 3, z = 50 }, CFG), "during the warning the spot is safe")
	truthy(not CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = 3, z = 50 + CFG.CellSize }, CFG),
		"the passage next to the cell (one step away) is always safe")
	-- a long frame cannot skip an impact
	truthy(CellHazards.checkHit(hz, centre, T - 1.0, T + 1.0, { x = 100, y = 3, z = 50 }, CFG), "a long frame still sees the impact")
	-- height: the object falls INTO the cell from above the walls. A jump never dodges it (only stepping
	-- out of the ring does), but a god-mode flyer high over the maze is not hit by something that fell
	-- to the floor under them.
	truthy(type(CFG.MaxHitHeight) == "number", "the hazard config names how high above the floor an impact reaches")
	local top = centre.y + (CFG.MaxHitHeight or 0)
	truthy(CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = centre.y + 10.5, z = 50 }, CFG),
		"a player at the top of a jump (root ~10.5 studs over the floor) is still hit: jumping is not a dodge")
	truthy(CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = top - 0.01, z = 50 }, CFG), "up to MaxHitHeight is a hit")
	truthy(not CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = top + 0.01, z = 50 }, CFG),
		"above MaxHitHeight (a god-mode flyer over the maze) is not")
	truthy(not CellHazards.checkHit(hz, centre, T - 0.05, T + 0.01, { x = 100, y = centre.y + 40, z = 50 }, CFG),
		"a flyer 40 studs up is not knocked out of the air")

	local v, stand = CellHazards.knock(centre, { x = 102, y = 3, z = 50 }, CFG)
	approx(v.x, CFG.KnockPush, 1e-9, "the knock pushes away from the impact")
	approx(v.z, 0, 1e-9, "horizontally")
	eq(v.y, 0, "and never upward")
	eq(stand, CFG.KnockSeconds, "for KnockSeconds")
	local v2 = CellHazards.knock(centre, { x = 100, y = 3, z = 50 }, CFG)
	approx(math.sqrt(v2.x * v2.x + v2.z * v2.z), CFG.KnockPush, 1e-9, "dead centre still gets a push of the same size")
end

--================================================================ bands decide the kind

eq(Biomes.hazardKindAt(EnvBands, 1), nil, "no hazard at level 1")
for _, b in Biomes.Bands do
	if b.hazard then
		truthy(CFG.Kinds[b.hazard] ~= nil, "hazard kind " .. b.hazard .. " is configured")
		truthy(type(CFG.Kinds[b.hazard].label) == "string", "and has a warning label")
	end
end

print(string.format("CellHazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("CellHazards spec failed", 0) end
