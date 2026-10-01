-- Meteors + PlotGeom — where and when meteors fall, what happens to them, and where plots are.
-- Run: luau tests/Meteors.spec.luau
--
-- Randomness is injected (`rand(): [0, 1)`); the game passes a server-lifetime Random.new(), this spec a
-- deterministic LCG. Nothing in the game is seeded: there is nothing here a client could re-run.

local Config = require("../src/shared/Config")
local Meteors = require("../src/shared/Meteors")
local PlotGeom = require("../src/shared/PlotGeom")
local Economy = require("../src/shared/Economy")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function lcg(seed)
	local s = seed % 4294967296
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

local C = Config

--============================================================================ landing points
do
	local r = lcg(11)
	local out, inner, N = 0, 0, 20000
	for _ = 1, N do
		local x, z = Meteors.landingPoint(C, r)
		local d = math.sqrt(x * x + z * z)
		if d < 8 - 1e-9 or d > 32 + 1e-9 then out += 1 end
		if d < 20 then inner += 1 end
	end
	eq(out, 0, "every one of 20 000 landing points lies in the ring 8 <= r <= 32")
	-- uniform BY AREA: the share inside r = 20 is (400 - 64) / (1024 - 64) = 0.35
	near(inner / N, 0.35, 0.015, "landing points are uniform by area, not by radius")
end
do
	local x, z = Meteors.firstPoint(C)
	eq(x, 0, "a session's first meteor lands on the arrival axis")
	eq(z, -20, "10 studs in front of the arrival pad at z = -30")
end

--============================================================================ the gap
do
	local r = lcg(12)
	local lo, hi, sum, N = math.huge, -math.huge, 0, 20000
	local L = 7
	local si = Economy.spawnInterval(C, L)
	for _ = 1, N do
		local g = Meteors.gap(C, si, r)
		lo, hi, sum = math.min(lo, g), math.max(hi, g), sum + g
	end
	truthy(lo >= si * 0.75 - 1e-9 and hi <= si * 1.25 + 1e-9,
		string.format("every gap is within 0.75..1.25 x the interval (%.3f..%.3f of %.3f)", lo, hi, si))
	near(sum / N / si, 1, 0.01, "and the jitter keeps the rate exact on average")
end

--============================================================================ rarities
do
	local function tally(band, N, seed)
		local r = lcg(seed)
		local t = { common = 0, uncommon = 0, rare = 0, epic = 0, legendary = 0 }
		for _ = 1, N do
			local k = Meteors.rollRarity(C, band, r)
			t[k] += 1
		end
		return t
	end
	local dusk = tally(1, 20000, 21)
	eq(dusk.epic + dusk.legendary, 0, "Dusk never drops an epic or a legendary")
	near(dusk.common / 20000, 0.88, 0.01, "Dusk is 88% pebbles")
	local core = tally(6, 50000, 22)
	near(core.legendary / 50000, 0.02, 0.003, "the Core drops a legendary every ~50 meteors")
	near(core.common / 50000, 0.48, 0.01, "and 48% pebbles")
	local star = tally(4, 50000, 23)
	near(star.legendary / 50000, 0.005, 0.0015, "Starfall: one legendary per ~200 meteors")
end

--============================================================================ fate, decided at the announcement
do
	local base = { x = 0, z = -12, rarity = "common", dishRadius = 14, awake = true, lying = 0 }
	local function fate(over)
		local m = table.clone(base)
		for k, v in over do m[k] = v end
		return Meteors.fate(C, m)
	end
	eq(fate({}), "dish", "inside an awake dish: a dish catch")
	eq(fate({ lying = 20 }), "dish", "the 20-meteor cap never blocks a dish catch (DESIGN's first flaw, fixed)")
	eq(fate({ awake = false }), "lie", "an asleep dish catches nothing: the meteor lies")
	eq(fate({ rarity = "legendary" }), "lie", "the dish never takes a legendary: you walk to it")
	eq(fate({ z = -20 }), "lie", "outside the dish it lies (r = 20 > 14)")
	eq(fate({ z = -20, lying = 19 }), "lie", "19 lying: one more may lie")
	eq(fate({ z = -20, lying = 20 }), "burn", "20 lying: a new one burns up in the sky")
	eq(fate({ z = -20, lying = 20, rarity = "legendary" }), "burn", "the cap applies to legendaries too (DESIGN 4.1)")
	eq(fate({ z = -20, lying = 25, star = true }), "lie", "only the Falling Star ignores the cap")
	eq(fate({ dishRadius = 0, z = -9 }), "lie", "no Collector: nothing is a dish catch")
end

--============================================================================ the Collector sleeps
do
	eq(Meteors.awake(C, 100, 100), true, "a session starts awake")
	eq(Meteors.awake(C, 100 + 599.9, 100), true, "still awake at 9:59.9")
	eq(Meteors.awake(C, 100 + 600, 100), false, "asleep 600 s after the last hand pickup")
	near(Meteors.awakeLeft(C, 100 + 88, 100), 512, 1e-9, "8:32 left 88 s in")
	near(Meteors.awakeLeft(C, 100 + 900, 100), 0, 1e-9, "0 left once asleep, never negative")
	eq(Meteors.clock(492), "8:12", "the HUD's clock reads 8:12")
	eq(Meteors.clock(5), "0:05", "and 0:05")
end

--============================================================================ pickup
do
	eq(Meteors.inPickup(C, 0, 0, 4.9, 0), true, "4.9 studs away is collected")
	eq(Meteors.inPickup(C, 0, 0, 5.1, 0), false, "5.1 studs away is not")
	eq(Meteors.inPickup(C, 3, 4, 0, 0), true, "5.0 exactly is collected (a 3-4-5 triangle)")
	eq(Meteors.inPickup(C, 0 / 0, 0, 0, 0), false, "a NaN position collects nothing")
end

--============================================================================ PlotGeom
do
	local cx1, cz1 = PlotGeom.centre(C, 1)
	local cx2, cz2 = PlotGeom.centre(C, 2)
	near(math.sqrt(cx1 * cx1 + cz1 * cz1), 110, 1e-9, "plot 1 sits on the ring of radius 110")
	local d = math.sqrt((cx1 - cx2) ^ 2 + (cz1 - cz2) ^ 2)
	near(d, 84.19, 0.01, "neighbouring plot centres are 84.2 studs apart (DESIGN 3)")
	truthy(d - 2 * C.World.PlotRadius > 12, "so their rims are 12.2 studs apart: nothing of one plot reaches the next")
	-- the arrival pad is on the observatory side: 110 - 30 = 80 studs from the origin
	for k = 1, 8 do
		local ax, az = PlotGeom.toWorld(C, k, 0, -30)
		near(math.sqrt(ax * ax + az * az), 80, 1e-9, "plot " .. k .. "'s arrival is 80 studs from the observatory")
		local lx, lz = PlotGeom.toLocal(C, k, PlotGeom.toWorld(C, k, 7, -13))
		near(lx, 7, 1e-9, "plot " .. k .. ": toLocal(toWorld(p)) = p (x)")
		near(lz, -13, 1e-9, "plot " .. k .. ": toLocal(toWorld(p)) = p (z)")
		local wx, wz = PlotGeom.toWorld(C, k, 3, 5)
		eq(PlotGeom.plotAt(C, wx, wz), k, "a point on plot " .. k .. " is on plot " .. k)
	end
	eq(PlotGeom.plotAt(C, 0, 0), nil, "the observatory is on no plot")
	-- world corners: the plate covers every rim with room to spare
	truthy(110 + 36 < C.World.BaseplateSize / 2, "the 600-stud plate covers every rim (outer edge at 146)")
end

--============================================================================ the hazard zone's floor (REVIEW-1)
-- The red zone was drawn at the plot disc's height, so on the 1-stud arrival pad 57-81% of it lay under the pad
-- and a player standing there saw four red slivers. The zone is drawn up to the highest LOW surface it overlaps
-- (the pad, the Smelter's base, the Beacon's base: things a player stands on), never the walls (the Smelter's
-- body, the board). robloxemu/check_meteordroptycoon_hazards.luau measures these surfaces on the built parts.
do
	if type(PlotGeom.zoneFloor) ~= "function" or type(PlotGeom.floors) ~= "function" then
		failed += 1
		print("FAIL: PlotGeom.zoneFloor / PlotGeom.floors do not exist (the zone is always drawn at the disc)")
	else
		local disc = C.World.DiscTopY
		local P = C.Plot
		local byPart = {}
		for _, f in PlotGeom.floors(C) do byPart[f.part] = f end
		truthy(byPart.Arrival ~= nil and byPart.SmelterBase ~= nil and byPart.BeaconBase ~= nil, "three low surfaces: the pad, the Smelter's base, the Beacon's base")
		local pad = byPart.Arrival
		near(pad and pad.top or 0, 1.0, 1e-9, "the arrival pad's top is at y = 1 (1 stud tall on the plate)")
		-- a satellite (radius 3.9) on a player standing on the pad: the zone is drawn on top of the pad
		near(PlotGeom.zoneFloor(C, P.Arrival.x, P.Arrival.z, 3.9), 1.0, 1e-9, "a zone on the pad is drawn at the pad's top")
		-- just beside the pad, overlapping its edge by a stud
		near(PlotGeom.zoneFloor(C, P.Arrival.x + 3 + 3.9 - 1, P.Arrival.z, 3.9), 1.0, 1e-9, "a zone that overlaps the pad's edge too")
		-- clear of it by a stud
		near(PlotGeom.zoneFloor(C, P.Arrival.x + 3 + 3.9 + 1, P.Arrival.z, 3.9), disc, 1e-9, "a zone a stud clear of the pad is on the disc")
		-- the pad's corner: a circle near the corner but outside the square does not count
		local cx, cz = P.Arrival.x + 3 + 2.0, P.Arrival.z + 3 + 2.0 -- 2.83 studs from the corner
		near(PlotGeom.zoneFloor(C, cx, cz, 2.5), disc, 1e-9, "a circle past the pad's corner (2.83 studs away, radius 2.5) does not touch it")
		near(PlotGeom.zoneFloor(C, cx, cz, 3.0), 1.0, 1e-9, "radius 3.0 does")
		-- the Smelter's base (radius 6, top 1 stud over the disc) and the Beacon's (radius 2.5, 2 studs)
		near(PlotGeom.zoneFloor(C, 0, -8, 3.9), disc + 1, 1e-9, "a zone on the Smelter's apron is drawn over its base")
		near(PlotGeom.zoneFloor(C, P.Beacon.x, P.Beacon.z - 5, 3.9), disc + 2, 1e-9, "one overlapping the Beacon's base, over it")
		near(PlotGeom.zoneFloor(C, 20, 0, 3.9), disc, 1e-9, "out in the landing ring: the disc")
	end
end

print(string.format("Meteors: %d passed, %d failed", passed, failed))
if failed > 0 then error("Meteors spec failed", 0) end
