-- Line — the production line's steady flow: speeds, capacities, the chute, overflow, jams, income and the
-- bottleneck. Run: luau tests/Line.spec.luau
--
-- DESIGN.md section 4.2, hand-worked: the chute feeds the Shredder exactly as fast as it can shred (never
-- below the 0.5 junk/s trickle); each station moves min(what reaches it, its capacity); whatever it cannot
-- take rides past unchanged and sells as what it already is; a jammed machine is not working, a sputtering
-- one still is. Every number below is worked by hand in the comment beside it, never from the module.

local Config = require("../src/shared/Config")
local Line = require("../src/shared/Line")

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

local C = Config
-- a line as an array of six station states, in belt order
local function line(spec: { any }?)
	local S = {}
	for t = 1, 6 do
		local s = spec and spec[t]
		S[t] = { n = s and s.n or 0, L = s and s.L or 1, jam = { s and s.jam and s.jam[1] or 0, s and s.jam and s.jam[2] or 0 } }
	end
	return S
end

--============================================================================ speeds (M1)
near(Line.speed(C, 1, 1), 1.0, 1e-12, "the Shredder does 1.0 items/s at level 1")
near(Line.speed(C, 2, 1), 1.6, 1e-12, "the Furnace 1.6")
near(Line.speed(C, 6, 1), 10.5, 1e-12, "the Rocket Bay 10.5")
near(Line.speed(C, 1, 2), 1.25, 1e-12, "a level is x1.25")
near(Line.speed(C, 3, 5), 2.6 * 1.25 ^ 4, 1e-9, "level 5 of the Press: 2.6 x 1.25^4 = 6.3477")

--============================================================================ the chute and the trickle
do
	local S = line()
	near(Line.intake(C, S), 0.5, 1e-12, "no Shredder: the chute trickles 0.5 junk/s")
	local r = Line.flow(C, S)
	near(r[1], 0.5, 1e-12, "...and it rides to the dock as junk")
	near(Line.income(C, S, 1), 0.5, 1e-12, "income 0.5 x $1 = $0.5/s")
end
do
	local S = line({ { n = 1 } })
	near(Line.intake(C, S), 1.0, 1e-12, "a level-1 Shredder: the chute feeds it 1.0 junk/s (its capacity)")
	local r = Line.flow(C, S)
	near(r[1], 0, 1e-12, "all of it is shredded: no junk at the dock")
	near(r[2], 1.0, 1e-12, "1.0 scrap/s")
	near(Line.income(C, S, 1), 2.0, 1e-12, "income 1.0 x $2 = $2/s")
end
do
	-- a Shredder slower than the trickle cannot happen at level 1, but a half-jammed one could feed less: the
	-- chute never drops below the trickle
	local S = line({ { n = 1, jam = { 2, 0 } } })
	near(Line.intake(C, S), 0.5, 1e-12, "a jammed Shredder: the chute falls back to the 0.5 trickle, never zero")
	local r = Line.flow(C, S)
	near(r[1], 0.5, 1e-12, "and that junk rides past the jammed Shredder unchanged")
	near(r[2], 0, 1e-12, "no scrap")
	near(Line.income(C, S, 1), 0.5, 1e-12, "income $0.5/s")
	near(Line.intake(C, S, true), 1.0, 1e-12, "ignoring jams (what the star plans for): 1.0")
end

--============================================================================ two stations, overflow
do
	-- Shredder L1 (1.0/s) + Furnace L1 (1.6/s): the Furnace takes everything
	local S = line({ { n = 1 }, { n = 1 } })
	local r = Line.flow(C, S)
	near(r[2], 0, 1e-12, "a Furnace faster than the Shredder: no scrap left")
	near(r[3], 1.0, 1e-12, "1.0 ingot/s")
	near(Line.income(C, S, 1), 5.0, 1e-12, "income 1.0 x $5 = $5/s")
end
do
	-- Shredder L5: 1.25^4 = 2.44140625/s; Furnace L1: 1.6/s. The Furnace moves 1.6; 0.84140625 scrap rides past.
	local S = line({ { n = 1, L = 5 }, { n = 1 } })
	local r = Line.flow(C, S)
	near(r[2], 0.84140625, 1e-9, "overflow: 2.4414 - 1.6 = 0.8414 scrap/s rides past the Furnace and sells as scrap")
	near(r[3], 1.6, 1e-9, "the Furnace ships 1.6 ingot/s")
	near(Line.income(C, S, 1), 0.84140625 * 2 + 1.6 * 5, 1e-9, "income 0.8414 x 2 + 1.6 x 5 = $9.6828/s")
	local reach, cap = Line.reach(C, S)
	near(reach[2], 2.44140625, 1e-9, "what reaches the Furnace is what the Shredder made")
	near(cap[2], 1.6, 1e-9, "the Furnace can take 1.6")
	near(Line.loads(C, S)[2], 2.44140625 / 1.6, 1e-9, "its load is 153%: items ride past")
end
do
	-- a twin doubles the station
	local S = line({ { n = 1, L = 5 }, { n = 2 } })
	local r = Line.flow(C, S)
	near(r[3], 2.44140625, 1e-9, "a twinned Furnace (3.2/s) takes all 2.4414")
	near(Line.income(C, S, 1), 2.44140625 * 5, 1e-9, "income $12.207/s")
	-- a jammed twin halves it
	local J = line({ { n = 1, L = 5 }, { n = 2, jam = { 2, 0 } } })
	near(Line.flow(C, J)[3], 1.6, 1e-9, "one of the two machines jammed: the station keeps half (1.6)")
	local J2 = line({ { n = 1, L = 5 }, { n = 2, jam = { 0, 2 } } })
	near(Line.flow(C, J2)[3], 1.6, 1e-9, "...whichever of the two it is")
	-- a sputtering machine still works
	local P = line({ { n = 1, L = 5 }, { n = 2, jam = { 1, 0 } } })
	near(Line.flow(C, P)[3], 2.44140625, 1e-9, "a SPUTTERING machine is still working")
	-- both jammed: everything rides past as scrap
	local B = line({ { n = 1, L = 5 }, { n = 2, jam = { 2, 2 } } })
	local rb = Line.flow(C, B)
	near(rb[2], 2.44140625, 1e-9, "both machines jammed: every scrap rides past")
	near(rb[3], 0, 1e-12, "and no ingot ships")
	near(Line.flow(C, B, true)[3], 2.44140625, 1e-9, "ignoring jams the station is whole again")
	-- a machine index past n is ignored (the twin is not built)
	local G = line({ { n = 1, L = 5 }, { n = 1, jam = { 0, 2 } } })
	near(Line.flow(C, G)[3], 1.6, 1e-9, "a jam flag on an unbuilt twin changes nothing")
end

--============================================================================ income multiplier (Gold Bolts)
do
	local S = line({ { n = 1 } })
	near(Line.income(C, S, 1.5), 3.0, 1e-12, "one Gold Bolt: x1.5")
	near(Line.mult(C, 0), 1, 1e-12, "no bolts: x1")
	near(Line.mult(C, 4), 3, 1e-12, "four bolts: 1 + 4 x 0.5 = x3")
end

--============================================================================ a full line, deep stations
do
	-- every station twinned at level 1: intake 2.0; furnace 3.2, press 5.2 ... all take 2.0 -> 2.0 rockets/s
	local spec = {}
	for t = 1, 6 do spec[t] = { n = 2 } end
	local S = line(spec)
	local r = Line.flow(C, S)
	near(r[7], 2.0, 1e-9, "a twinned level-1 line ships what the twinned Shredder feeds: 2.0 rockets/s")
	near(Line.income(C, S, 1), 400, 1e-9, "income 2.0 x $200 = $400/s")
	-- the level cap bounds the rocket rate: twinned level-100 stations, the Shredder is the slowest
	local top = {}
	for t = 1, 6 do top[t] = { n = 2, L = C.Stations.MaxLevel } end
	local rt = Line.flow(C, line(top))[7]
	near(rt / 7.85e9, 1, 0.01, string.format("the most a line can ever ship: 2 x 1.25^99 = %.3g rockets/s (DESIGN 10.2: 7.85e9)", rt))
end

--============================================================================ the bottleneck
do
	eq((Line.bottleneck(C, line())), nil, "no station built: no bottleneck")
	local t, ratio = Line.bottleneck(C, line({ { n = 1 } }))
	eq(t, 1, "the Shredder alone is the bottleneck")
	near(ratio, 1, 1e-12, "...at ratio 1 (it takes exactly what the chute gives it)")
	t = Line.bottleneck(C, line({ { n = 1 }, { n = 1 } }))
	eq(t, 1, "a Furnace faster than the Shredder: the Shredder still limits the line")
	t, ratio = Line.bottleneck(C, line({ { n = 1, L = 5 }, { n = 1 } }))
	eq(t, 2, "a Shredder outrunning the Furnace: the Furnace is the bottleneck")
	near(ratio, 1.6 / 2.44140625, 1e-9, "at 1.6 / 2.4414 = 0.655")
	-- ties go to the earlier station: Shredder L1 (1.0) and a Furnace at exactly 1.0 cannot happen with the
	-- configured speeds, so a tie is built with a jammed twin ignored (bottleneck plans for a working line)
	t = Line.bottleneck(C, line({ { n = 1, L = 5 }, { n = 2, jam = { 2, 2 } } }))
	eq(t, 1, "the bottleneck ignores jams (it names the slowest station, not the broken one)")
end

--============================================================================ ordered(): the persisted map -> belt order
do
	local stations = {
		shredder = { n = 1, L = 3, jam = { 0, 0 } }, furnace = { n = 2, L = 1, jam = { 2, 0 } },
		press = { n = 0, L = 1, jam = { 0, 0 } }, cutter = { n = 0, L = 1, jam = { 0, 0 } },
		assembler = { n = 0, L = 1, jam = { 0, 0 } }, rocketbay = { n = 0, L = 1, jam = { 0, 0 } },
	}
	local S = Line.ordered(C, stations)
	eq(#S, 6, "six stations in belt order")
	eq(S[1], stations.shredder, "the Shredder first (the same table, not a copy)")
	eq(S[2], stations.furnace, "then the Furnace")
	eq(S[6], stations.rocketbay, "the Rocket Bay last")
	eq(Line.indexOf(C, "press"), 3, "station ids map to their belt index")
	eq(Line.indexOf(C, "nope"), nil, "an unknown id has none")
end

print(string.format("Line: %d passed, %d failed", passed, failed))
if failed > 0 then error("Line spec failed", 0) end
