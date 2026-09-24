-- Spec for the altitude <-> progress helpers in Progression. Run: luau tests/Altitude.spec.luau
--
-- The sky bands are driven by how far up the tower the player IS. The tower's geometry is fully
-- determined by Config.Tower (TowerGen stacks TilesPerTier platforms, each stepHeight(t) above the
-- last, and each tier starts on the top platform of the one below), so altitude and "tiers climbed"
-- are the same number in two units. These helpers convert between them; TowerGen is the ground
-- truth they are checked against, and robloxemu/check_plus1_sky.luau checks them again against the
-- Parts the real server builds.
local P = require("../src/shared/Progression")
local TowerGen = require("../src/shared/TowerGen")
local Config = require("../src/shared/Config")

local tw = Config.Tower
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

eq(type(tw.BaseY), "number", "Config.Tower.BaseY exists (the server builds tier 1 on it)")
eq(tw.BaseY, 8, "and it is the 8 the server has always used")

--================================================================ climbHeight

eq(P.climbHeight(0, tw), 0, "no tiers climbed: height 0")
approx(P.climbHeight(1, tw), tw.TilesPerTier * P.stepHeight(1, tw), "tier 1 is TilesPerTier steps")
do
	local loopSum, ok, worst = 0, true, 0
	for n = 1, 1500 do
		loopSum += tw.TilesPerTier * P.stepHeight(n, tw)
		local d = math.abs(P.climbHeight(n, tw) - loopSum)
		if d > worst then worst = d end
		if d > 1e-6 then ok = false end
	end
	truthy(ok, "climbHeight's closed form equals the plain sum for every n up to 1500 (worst " .. worst .. ")")
end
do
	-- and it agrees with the generator the server actually builds from
	local cfg = { Tower = tw, Jump = Config.Jump, WorldSeed = Config.WorldSeed }
	local top, ok = 0, true
	for t = 1, 300 do
		local gen = TowerGen.tier(t, cfg)
		top += gen.exitHeight
		if math.abs(P.climbHeight(t, tw) - top) > 1e-6 then ok = false end
	end
	truthy(ok, "climbHeight(t) is the stacked exitHeight of TowerGen tiers 1..t")
end
do
	-- a config with no step growth at all must not divide by zero
	local flat = table.clone(tw)
	flat.StepPerTier = 0
	approx(P.climbHeight(10, flat), 10 * flat.TilesPerTier * flat.StepMin, "a flat tower (StepPerTier 0) works")
	approx(P.tierProgressAtY(flat.BaseY + P.climbHeight(7, flat), flat), 7, "and inverts")
end

--================================================================ tierProgressAtY

eq(P.tierProgressAtY(tw.BaseY, tw), 0, "standing on the base: 0 tiers climbed")
eq(P.tierProgressAtY(tw.BaseY - 500, tw), 0, "below the base clamps to 0 (falling off the start pad)")
eq(P.tierProgressAtY(0 / 0, tw), 0, "NaN altitude is 0, not NaN")
do
	local ok, worst = true, 0
	for t = 1, 400 do
		for i = 1, tw.TilesPerTier do
			local y = tw.BaseY + P.climbHeight(t - 1, tw) + i * P.stepHeight(t, tw)
			local want = (t - 1) + i / tw.TilesPerTier
			local d = math.abs(P.tierProgressAtY(y, tw) - want)
			if d > worst then worst = d end
			if d > 1e-9 then ok = false end
		end
	end
	truthy(ok, "standing on platform i of tier t reads as (t-1) + i/TilesPerTier tiers climbed, t<=400 (worst "
		.. worst .. ")")
end
do
	local prev, mono = -1, true
	local y = tw.BaseY - 10
	while y < tw.BaseY + 120000 do
		local p = P.tierProgressAtY(y, tw)
		if p < prev then mono = false end
		prev = p
		y += 7.3
	end
	truthy(mono, "progress never decreases as altitude increases (to 120 000 studs)")
end

--================================================================ yAtProgress (the inverse)

do
	local ok, worst = true, 0
	for k = 0, 4000 do
		local p = k * 0.0731
		local back = P.tierProgressAtY(P.yAtProgress(p, tw), tw)
		local d = math.abs(back - p)
		if d > worst then worst = d end
		if d > 1e-6 then ok = false end
	end
	truthy(ok, "yAtProgress inverts tierProgressAtY for p up to 292 (worst " .. worst .. ")")
end
approx(P.yAtProgress(0, tw), tw.BaseY, "progress 0 is the base")
approx(P.yAtProgress(-3, tw), tw.BaseY, "negative progress clamps to the base")

--================================================================ tierAtY (the tier number the HUD shows)

-- Review 2026-09-17 (finding 7): the HUD and the top-10 board name a band by TIER number ("85 🚀"),
-- while the sky named it by tiers climbed. Standing on P_85_1..5 read 84.2-84.8 climbed, so the board
-- said space and the player's own sky said Edge of Space. tierAtY gives the sky the same number the
-- server credits: standing on any platform of tier t is tier t.
eq(P.tierAtY(tw.BaseY, tw), 0, "standing on the start pad: tier 0")
eq(P.tierAtY(tw.BaseY - 300, tw), 0, "below the pad: tier 0")
eq(P.tierAtY(0 / 0, tw), 0, "NaN: tier 0")
do
	local ok, where = true, nil
	for t = 1, 400 do
		local base = tw.BaseY + P.climbHeight(t - 1, tw)
		local step = P.stepHeight(t, tw)
		for i = 1, tw.TilesPerTier do
			local centre = base + i * step
			-- anywhere from the platform's centre height up to just under the next platform's centre
			local nextCentre = if i < tw.TilesPerTier then centre + step else centre + P.stepHeight(t + 1, tw)
			for _, y in { centre, centre + 1.5, (centre + nextCentre) / 2, nextCentre - 0.01 } do
				local want = if i < tw.TilesPerTier or y < nextCentre then t else t + 1
				if P.tierAtY(y, tw) ~= want then
					ok = false
					where = where or string.format("P_%d_%d at y=%.2f read %d", t, i, y, P.tierAtY(y, tw))
				end
			end
		end
	end
	truthy(ok, "on any platform of tier t (and up to the next one) the tier is t, t <= 400 (" .. tostring(where) .. ")")
end
do
	local prev, mono = 0, true
	local y = tw.BaseY - 10
	while y < tw.BaseY + 60000 do
		local t = P.tierAtY(y, tw)
		if t < prev then mono = false end
		prev = t
		y += 3.7
	end
	truthy(mono, "the tier never decreases as altitude increases")
end

print(string.format("Altitude: %d passed, %d failed", passed, failed))
assert(failed == 0, "Altitude tests failed")
