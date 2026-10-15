-- Flood: three rises, each warned 9 s ahead by a red line at the coming height (DESIGN.md §2.5).
-- Run: luau tests/Flood.spec.luau
local Flood = require("../src/shared/Flood")
local Zones = require("../src/shared/Zones")
local MapGen = require("../src/shared/MapGen")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg) eq(math.abs(a - b) <= tol, true, msg .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")") end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local plan = Flood.plan(Config)
eq(#plan, 3, "three rises")
local want = {
	{ warnAt = 3, riseAt = 12, riseEnd = 16, from = -2, to = 2 },
	{ warnAt = 16, riseAt = 25, riseEnd = 29, from = 2, to = 6 },
	{ warnAt = 29, riseAt = 38, riseEnd = 42, from = 6, to = 10 },
}
for k, w in want do
	for key, v in w do
		eq(plan[k][key], v, string.format("rise %d: %s = %s", k, key, tostring(v)))
	end
end

--======================================================================= the water level over time

near(Flood.waterAt(Config, plan, 0), Config.Island.SeaY, 1e-9, "at the name the water is the sea (y -2)")
near(Flood.waterAt(Config, plan, 11.9), -2, 1e-9, "it holds through the first warning")
near(Flood.waterAt(Config, plan, 14), 0, 1e-9, "2 s into the first rise it passes the beach top (y 0)")
near(Flood.waterAt(Config, plan, 16), 2, 1e-9, "after the first rise: 2")
near(Flood.waterAt(Config, plan, 27), 4, 1e-9, "2 s into the second rise it passes level 1's top (y 4)")
near(Flood.waterAt(Config, plan, 42), 10, 1e-9, "after the third: 10")
near(Flood.waterAt(Config, plan, 60), 10, 1e-9, "and it holds there to the end")
do
	local monotone = true
	local prev = -math.huge
	for t = 0, 600 do
		local y = Flood.waterAt(Config, plan, t / 10)
		if y < prev - 1e-9 then monotone = false end
		prev = y
	end
	truthy(monotone, "the water never goes down during a round")
end

--======================================================================= levels 3-4 stay dry; the red line is the truth

for level = 0, 4 do
	local flooded = Zones.flooded(Config.Island, level, Flood.waterAt(Config, plan, 60))
	eq(flooded, level <= 2, string.format("level %d %s at the end", level, if level <= 2 then "is under water" else "stays dry"))
end
do
	-- a cell is flooded exactly when its level is below the rise's covered level, and the red tint (Flood.warned)
	-- covers exactly the cells that will flood at the current rise
	for k, r in plan do
		for level = 0, 4 do
			local willFlood = Zones.flooded(Config.Island, level, r.to)
			eq(Flood.warnedLevel(level, r), willFlood, string.format("rise %d: level %d is tinted red iff it floods", k, level))
		end
	end
end

--======================================================================= what replicates, and when

do
	eq(Flood.currentRise(plan, 2.9), nil, "before 3 s no rise is announced")
	eq(Flood.currentRise(plan, 3), 1, "at 3 s rise 1 is announced")
	eq(Flood.currentRise(plan, 15.9), 1, "until rise 2's warning")
	eq(Flood.currentRise(plan, 16), 2, "rise 2 at 16 s")
	eq(Flood.currentRise(plan, 59), 3, "rise 3 to the end")
	-- the attributes the server publishes never reach past the current rise
	local a = Flood.attributes(plan, 20)
	eq(a.WaterTo, 6, "at 20 s the published target is rise 2's (6)")
	eq(a.RiseAt, 25, "with its start")
	eq(a.RiseEnd, 29, "and its end")
	eq(a.WaterFrom, 2, "and its start height")
	eq(Flood.attributes(plan, 1), nil, "before the first warning nothing is published")
end

--======================================================================= time to escape

do
	local avail = Config.Flood.WarnSeconds + Config.Flood.RiseSeconds / 2 + Config.Hits.GroundGrace
	near(avail, 11.6, 1e-9, "from the red line to a hit: 9 + 2 + 0.6 = 11.6 s")
	local walk = Config.Island.MaxEscapeStuds * Config.Island.PathFactor / Config.WalkSpeed
	truthy(walk < avail, string.format("the longest escape (80 studs x 1.25 at 16 studs/s = %.2f s) leaves %.2f s to react", walk, avail - walk))
	-- and on 300 real maps, every flooding cell's escape fits inside the warning
	local seed = 7
	local function rand()
		seed = (1664525 * seed + 1013904223) % 4294967296
		return seed / 4294967296
	end
	local worst = 0
	for _ = 1, 300 do
		local map = MapGen.generate(Config.Island, rand)
		worst = math.max(worst, MapGen.worstEscape(Config.Island, map.levels))
	end
	truthy(worst * Config.Island.PathFactor / Config.WalkSpeed + 0.8 <= avail,
		string.format("300 maps: the worst escape (%d studs) plus a 0.8 s reaction fits in %.1f s", worst, avail))
end

print(string.format("Flood: %d passed, %d failed", passed, failed))
assert(failed == 0, "Flood tests failed")
