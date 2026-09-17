-- Pure tests for Heist: laser timing, the server's continuous catch test, and the raid solver.
-- Run from the game directory: luau tests/Heist.spec.luau
--
-- The solver section re-measures DESIGN.md section 5's raid-time table against the real Layout
-- generator and the real catch geometry. Those numbers are PRINTED; the only hard promises
-- asserted are the ones the design makes by construction (every camp solvable under the padded
-- human model) and the orderings any sane difficulty ladder must keep.
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Layout = require("../src/shared/Layout")
local Heist = require("../src/shared/Heist")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tol)
	end
end

--============================================================================ laser state

do
	local trap = { kind = "laser", on = 1.0, off = 2.2, phase = 0 }
	eq(Heist.laserState(Config, trap, 0), "off", "t=0 local 0 is OFF")
	eq(Heist.laserState(Config, trap, 1.69), "off", "t=1.69 still OFF")
	eq(Heist.laserState(Config, trap, 1.71), "warn", "the last 0.5 s of OFF is WARN")
	eq(Heist.laserState(Config, trap, 2.19), "warn", "t=2.19 WARN")
	eq(Heist.laserState(Config, trap, 2.2), "on", "t=2.2 ON")
	eq(Heist.laserState(Config, trap, 3.19), "on", "t=3.19 ON")
	eq(Heist.laserState(Config, trap, 3.2), "off", "the cycle repeats at 3.2")
	eq(Heist.laserState(Config, trap, 32 + 2.3), "on", "ten cycles later, same state")
	trap.phase = 0.5
	eq(Heist.laserState(Config, trap, 0), "off", "phase 0.5: t=0 is local 0.5, OFF")
	eq(Heist.laserState(Config, trap, 1.7), "on", "phase 0.5: t=1.7 is local 2.2, ON")
	trap.phase = 0
	-- grace: the server treats the first 0.2 s of every ON window as OFF
	truthy(not Heist.dangerousAt(Config, trap, 2.3), "t=2.3 is inside the latency grace")
	truthy(Heist.dangerousAt(Config, trap, 2.45), "t=2.45 is past the grace")
	truthy(not Heist.dangerousAt(Config, trap, 1.0), "OFF is never dangerous")
	eq(Heist.laserState(Config, { kind = "snare" }, 5), "on", "a snare is always armed")
end

--============================================================================ the catch test

-- A hand-built camp: gaps at 1, 5, 9 on row 3; a laser in the centre gap (5,3), a snare at (2,5).
local function camp()
	local L = Layout.fromSpec(Config, { kind = "camp", lines = { { row = 3, cols = { 1, 5, 9 } } }, rocks = {} })
	Layout.place(Config, L, 5, 3, "laser")
	local t = Layout.trapAt(L, 5, 3)
	t.on, t.off, t.phase = 1.0, 2.2, 0
	Layout.place(Config, L, 2, 5, "snare")
	return L
end

do
	local L = camp()
	-- gap (5,3): x 32..40, z 40..48; danger x 31..41 (fence both sides), z 41..47
	local ON_T, OFF_T = 2.6, 0.5
	eq(Heist.caught(Config, Layout, L, 36, 44, ON_T, 36, 44, ON_T + 0.1), Layout.trapAt(L, 5, 3), "standing in the net while ON is a catch")
	eq(Heist.caught(Config, Layout, L, 36, 44, OFF_T, 36, 44, OFF_T + 0.1), nil, "standing in it while OFF is not")
	eq(Heist.caught(Config, Layout, L, 36, 38, ON_T, 36, 50, ON_T + 0.1), Layout.trapAt(L, 5, 3),
		"crossing the whole net inside ONE tick while ON is a catch (no slipping between samples)")
	eq(Heist.caught(Config, Layout, L, 36, 38, OFF_T, 36, 50, OFF_T + 0.1), nil, "the same crossing while OFF is not")
	-- time is interpolated along the segment: the tick ends in ON, but the net was left before it
	-- switched (area part of the segment is the first 3 of 12 studs... z 41..47 of 38->50 is 25%..75%)
	eq(Heist.caught(Config, Layout, L, 36, 38, 2.0, 36, 50, 2.4), nil, "area crossed at t 2.10-2.30, all before ON+grace (2.40)")
	eq(Heist.caught(Config, Layout, L, 36, 38, 2.2, 36, 50, 2.6), Layout.trapAt(L, 5, 3), "area crossed at t 2.30-2.50 overlaps ON past the grace")
	eq(Heist.caught(Config, Layout, L, 36, 38, 2.1, 36, 50, 2.3), nil, "a crossing entirely inside the grace window is safe")
	-- corners
	eq(Heist.caught(Config, Layout, L, 42, 44, ON_T, 38, 40, ON_T + 0.1), Layout.trapAt(L, 5, 3), "a segment clipping the net's corner is a catch")
	eq(Heist.caught(Config, Layout, L, 43, 44, ON_T, 40, 38.5, ON_T + 0.1), nil, "a segment passing just outside the corner is not")
	-- THE NOCLIP LANE: hugging the gap's edge at x = 31.5 is only possible for a trusted position that
	-- has been let 1 stud into the fence margin. It must still be caught.
	eq(Heist.caught(Config, Layout, L, 31.5, 38, ON_T, 31.5, 50, ON_T + 0.1), Layout.trapAt(L, 5, 3),
		"walking the 1-stud fence margin of a gap does NOT get past its net")
	-- teleport through: a banked 10.8-stud jump over the whole net in one tick
	eq(Heist.caught(Config, Layout, L, 36, 39, ON_T, 36, 49.8, ON_T + 0.1), Layout.trapAt(L, 5, 3), "a banked jump through an ON net is a catch")
	-- snares: always armed; danger inset 1 stud towards open floor
	-- snare (2,5): x 8..16, z 56..64; danger x 9..15, z 57..63
	eq(Heist.caught(Config, Layout, L, 12, 54, 0.3, 12, 60, 0.4), Layout.trapAt(L, 2, 5), "walking onto a snare is a catch at any time")
	eq(Heist.caught(Config, Layout, L, 8.5, 54, 0.3, 8.5, 66, 0.4), nil, "walking its outer half-stud margin is not")
	eq(Heist.caught(Config, Layout, L, 20, 60, 0.3, 17, 60, 0.4), nil, "stopping short of a snare is not")
	eq(Heist.caught(Config, Layout, L, 12, 60, 0.3, 12, 60, 0.3), nil, "a zero-duration, zero-length sample catches nothing")
end

do
	-- the earliest catch wins when a segment crosses two traps
	local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = {} })
	Layout.place(Config, L, 5, 2, "snare")
	Layout.place(Config, L, 5, 4, "snare")
	eq(Heist.caught(Config, Layout, L, 36, 30, 1, 36, 70, 2), Layout.trapAt(L, 5, 2), "the first trap along the segment is the one reported")
	eq(Heist.caught(Config, Layout, L, 36, 70, 1, 36, 30, 2), Layout.trapAt(L, 5, 4), "...in either direction")
end

do
	-- REVIEW-1.md B1: a tick's trusted path can bend (a straight leg, then a slide along a wall), so
	-- the catch runs along every LEG, each timed by its share of the path's length. A chord from the
	-- tick's start to its end would skip a trap only the bend touches.
	local L = camp()
	local snare = Layout.trapAt(L, 2, 5) -- danger x 9..15, z 57..63
	eq(Heist.caught(Config, Layout, L, 4, 60, 0.3, 12, 68, 0.4), nil, "the chord (4,60)->(12,68) misses the snare")
	eq(Heist.caughtPath(Config, Layout, L, { 4, 60, 12, 60, 12, 68 }, 0.3, 0.4), snare,
		"...but the bent path (4,60)->(12,60)->(12,68) runs through it and is caught")
	-- leg timing: two 16-stud legs, the second crossing the net (5,3) at 31 %..69 % of its length.
	-- Over [1, 3] the second leg spans [2, 3] and is inside the net at 2.31..2.69: ON past the grace
	-- (2.40), a catch. Over [0, 2] it is inside at 1.31..1.69, OFF.
	local net = Layout.trapAt(L, 5, 3)
	local path = { 20, 36, 36, 36, 36, 52 }
	eq(Heist.caughtPath(Config, Layout, L, path, 1, 3), net, "each leg is timed by its share of the path: inside the net at 2.31-2.69 is a catch")
	eq(Heist.caughtPath(Config, Layout, L, path, 0, 2), nil, "...and at 1.31-1.69 it is not")
	eq(Heist.caughtPath(Config, Layout, L, { 36, 44 }, 2.6, 2.7), net, "a one-point path is standing still: in the net while ON is a catch")
	eq(Heist.caughtPath(Config, Layout, L, { 36, 30, 36, 30 }, 2.6, 2.7), nil, "...and standing outside it is not")
end

--============================================================================ earliest safe crossing

do
	local trap = { kind = "laser", on = 1.0, off = 2.2, phase = 0 }
	-- the net is inside [a, b] after departure; ON windows [2.2, 3.2) + k*3.2
	eq(Heist.earliestCrossing(trap, 0, 0.3, 0.7, 0), 0, "a crossing inside OFF goes immediately")
	near(Heist.earliestCrossing(trap, 1.8, 0.3, 0.7, 0), 2.9, 1e-9, "a crossing that would overlap ON waits for its end")
	near(Heist.earliestCrossing(trap, 1.8, 0.3, 0.7, 0.3), 3.2, 1e-9, "with a 0.3 s pad it waits 0.3 s longer")
	eq(Heist.earliestCrossing({ kind = "laser", on = 2.2, off = 1.4, phase = 0 }, 0, 0, 1.0, 0.3), nil,
		"a crossing longer than the padded OFF window is impossible")
	eq(Heist.earliestCrossing({ kind = "snare" }, 0, 0, 0.5, 0), nil, "a snare can never be crossed")
end

--============================================================================ the by-construction argument

for tier, P in Config.Camps do
	local carry = 6 / Config.Raid.CarrySpeed
	local window = P.off - 2 * Config.Raid.HumanPad - carry
	truthy(window > 0, string.format("tier %d: padded carry window %.2f s > 0 (off %.1f)", tier, window, P.off))
	print(string.format("  tier %d padded carry window %.2f s = %.1f%% of a %.1f s cycle", tier, window, 100 * window / (P.on + P.off), P.on + P.off))
end

--============================================================================ the solver

do
	-- an open camp: no lasers, no rocks. Prize at column 1: 8 rows + 4 columns = 12 cells = 96 studs.
	local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = {} })
	L.cages = { { col = 1, prize = true, sp = "hodag" } }
	L.tier = 1
	local r = Heist.solveRaid(Config, Layout, L, { pad = 0 })
	near(r.inTime, 96 / 16, 1e-9, "open camp: 96 studs in at 16")
	near(r.total, 96 / 16 + 1.0 + 96 / 12, 1e-9, "open camp: + 1 s hold + 96 studs out at 12")
end

do
	-- one forced laser at (5,3) with a known phase; prize straight up at column 5
	local L = Layout.fromSpec(Config, { kind = "camp", lines = { { row = 3, cols = { 5 } } }, rocks = {} })
	Layout.place(Config, L, 5, 3, "laser")
	local t = Layout.trapAt(L, 5, 3)
	t.on, t.off, t.phase = 1.0, 2.2, 0
	L.cages = { { col = 5, prize = true, sp = "hodag" } }
	L.tier = 1
	local r = Heist.solveRaid(Config, Layout, L, { pad = 0.3 })
	truthy(r ~= nil, "a forced-laser camp is solvable")
	-- every crossing the plan makes must survive the SERVER's catch test with the same pad
	for _, x in r.crossings do
		truthy(not Heist.crossingCaught(Config, Layout, L, x, 0.3), string.format("planned crossing at %.2f s is not caught", x.depart))
		truthy(not Heist.crossingCaught(Config, Layout, L, x, nil), "...and not caught by the server rule (grace, no pad)")
	end
	eq(#r.crossings, 2, "the plan crosses the forced net twice (in and out)")
	-- the timed route a walker can follow: starts and ends on the gate cell, time never runs
	-- backwards, and no stretch is faster than the speed of its half of the raid
	local route = r.route
	truthy(#route >= 4, "the plan has a timed route")
	eq(route[1].x .. "," .. route[1].z, "36,20", "the route starts on the gate cell")
	eq(route[#route].x .. "," .. route[#route].z, "36,20", "...and ends there")
	near(route[#route].t, r.total, 1e-9, "...at the plan's total time")
	local backwards, tooFast = 0, 0
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		local dt = b.t - a.t
		if dt < -1e-9 then backwards += 1 end
		local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		if d > 1e-9 and d / dt > Config.Raid.WalkSpeed + 1e-6 then tooFast += 1 end
	end
	eq(backwards, 0, "route time never runs backwards")
	eq(tooFast, 0, "no stretch of the route is faster than walking speed")
	local held = false
	for i = 2, #route do
		if route[i].grab and route[i].t - route[i - 1].t >= Config.Camps[1].hold - 1e-9 then held = true end
	end
	truthy(held, "the route stands on the grab cell for the whole hold")
	local bare = Heist.solveRaid(Config, Layout, L, { pad = 0, noLasers = true })
	near(bare.total, 8 * 8 / 16 + 1.0 + 8 * 8 / 12, 1e-9, "without lasers: 8 cells each way")
	truthy(r.total >= bare.total, "lasers never make a raid faster")
	-- mutation guard: a crossing timed INTO the ON window is reported as caught
	local bad = { trap = t, depart = 1.9, speed = 16, from = { 5, 2 }, to = { 5, 4 } }
	truthy(Heist.crossingCaught(Config, Layout, L, bad, nil), "a crossing departing 1.9 s runs into the ON window")
end

local function pct(xs, p)
	local s = table.clone(xs)
	table.sort(s)
	return s[math.min(#s, math.floor(p * #s) + 1)]
end

local N = 300
local medians = {}
for tier = 1, 4 do
	local H, B, Z, cost = {}, {}, {}, {}
	local unsolved = 0
	local checked, caughtPlans = 0, 0
	for s = 1, N do
		local C = Layout.generateCamp(Config, Rng, Layout.campSeed(Config, 7000 * tier, s, tier), tier)
		local human = Heist.solveRaid(Config, Layout, C, { pad = Config.Raid.HumanPad })
		local bot = Heist.solveRaid(Config, Layout, C, { pad = 0 })
		local bare = Heist.solveRaid(Config, Layout, C, { pad = 0, noLasers = true })
		if human == nil or bot == nil or bare == nil then
			unsolved += 1
		else
			table.insert(H, human.total)
			table.insert(B, bot.total)
			table.insert(Z, bare.total)
			table.insert(cost, human.total - bare.total)
			for _, x in human.crossings do
				checked += 1
				if Heist.crossingCaught(Config, Layout, C, x, nil) then caughtPlans += 1 end
			end
		end
	end
	eq(unsolved, 0, string.format("tier %d: every one of %d camps is solvable under the padded human model", tier, N))
	eq(caughtPlans, 0, string.format("tier %d: none of %d planned crossings is caught by the server's test", tier, checked))
	medians[tier] = pct(H, 0.5)
	print(string.format("  tier %d human median %.2f p90 %.2f p99 %.2f max %.2f | flawless median %.2f | no lasers %.2f | laser cost median %.2f",
		tier, pct(H, 0.5), pct(H, 0.9), pct(H, 0.99), pct(H, 1), pct(B, 0.5), pct(Z, 0.5), pct(cost, 0.5)))
	truthy(pct(H, 1) < Config.Raid.RaidSeconds / 3, string.format("tier %d: the worst human-model raid (%.2f s) is far inside the %d s cap", tier, pct(H, 1), Config.Raid.RaidSeconds))
end
for tier = 2, 4 do
	truthy(medians[tier] > medians[tier - 1], string.format("tier %d camps take longer than tier %d (%.2f > %.2f)", tier, tier - 1, medians[tier], medians[tier - 1]))
end

print(string.format("Heist: %d passed, %d failed", passed, failed))
if failed > 0 then error("Heist tests failed") end
