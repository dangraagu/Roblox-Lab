-- Pure tests for Poacher: the NPC that walks your yard toward your fullest jar.
-- Run from the game directory: luau tests/Poacher.spec.luau
--
-- The catch-rate table at the bottom re-measures DESIGN.md section 6 against the real Layout
-- generator, the real Heist catch test (server rule, with grace) and the real stepping code.
-- Its numbers are printed; the assertions are the orderings and the bounds the design depends on.
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Layout = require("../src/shared/Layout")
local Heist = require("../src/shared/Heist")
local Poacher = require("../src/shared/Poacher")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function fixedRng(v)
	return { next = function() return v end, below = function(_, n) return 1 end }
end

local function blankLair()
	return Layout.fromSpec(Config, { kind = "lair", lines = { { row = 3, cols = { 1, 5, 9 } }, { row = 6, cols = { 1, 5, 9 } } }, rocks = {} })
end

local function run(p, L, untilT)
	return Poacher.step(Config, Layout, Heist, L, p, untilT)
end

--============================================================================ paths

do
	local L = blankLair()
	local path = Poacher.path(Config, Layout, L, 5)
	truthy(path ~= nil, "a path to the centre cage exists")
	eq(#path, 9, "(5,0) to (5,8) straight up is 9 cells")
	eq(path[1][1] .. "," .. path[1][2], "5,0", "starts on the gate approach")
	eq(path[#path][1] .. "," .. path[#path][2], "5,8", "ends on the grab cell")

	-- a laser in the centre gap of row 3: the detour through gap 1 or 9 costs 8 extra cells > 4,
	-- so the poacher takes the laser
	Layout.place(Config, L, 5, 3, "laser")
	path = Poacher.path(Config, Layout, L, 5)
	local throughLaser = false
	for _, c in path do if c[1] == 5 and c[2] == 3 then throughLaser = true end end
	truthy(throughLaser, "a detour of 8 extra cells is dearer than one laser (cost 5)")

	-- a laser whose detour is only 2 extra cells is avoided
	local L2 = Layout.fromSpec(Config, { kind = "lair", lines = { { row = 3, cols = { 4, 6 } } }, rocks = {} })
	Layout.place(Config, L2, 4, 3, "laser")
	local p2 = Poacher.path(Config, Layout, L2, 4)
	local via6 = false
	for _, c in p2 do if c[1] == 6 and c[2] == 3 then via6 = true end end
	truthy(via6, "a laser with a cheap detour is walked around")

	-- snares are never walked through
	Layout.place(Config, L, 1, 3, "snare")
	path = Poacher.path(Config, Layout, L, 1)
	for _, c in path do
		truthy(not (c[1] == 1 and c[2] == 3), "the path never steps on a snare")
	end
end

--============================================================================ walking, holding, leaving

do
	local L = blankLair()
	local p = Poacher.new(Config, Layout, L, 5, fixedRng(0.9), 100)
	eq(p.state, "in", "a new poacher is walking in")
	local x, z = Poacher.position(Config, Layout, p)
	eq(x, 36, "it appears on the gate approach (x)"); eq(z, 20, "...(z)")
	local ev = run(p, L, 100 + 6.4 - 0.01)
	eq(p.state, "in", "64 studs at 10 studs/s is not done at 6.39 s")
	ev = run(p, L, 100 + 6.4 + 0.01)
	eq(p.state, "grab", "...and is holding at 6.41 s")
	x, z = Poacher.position(Config, Layout, p)
	eq(z, 84, "holding on the grab cell")
	ev = run(p, L, 100 + 8.4 - 0.01)
	eq(p.state, "grab", "the hold takes 2 s")
	ev = run(p, L, 100 + 8.4 + 0.01)
	eq(p.state, "out", "then it leaves")
	eq(ev.grabbed, true, "the step that finishes the hold reports the grab")
	ev = run(p, L, 100 + 14.8 + 0.02)
	eq(p.state, "gone", "and is gone 6.4 s later")
	eq(ev.escaped, true, "the step that reaches the gate reports the escape")
end

do
	-- the reckless poacher (roll 0.9 >= caution 0.6) walks straight into an ON net
	local L = blankLair()
	Layout.place(Config, L, 5, 3, "laser")
	local trap = Layout.trapAt(L, 5, 3)
	trap.phase = 0 -- lair laser 1.4 on / 1.9 off: ON windows [1.9, 3.3) + k*3.3
	-- enter at t0: the net (z 41..47) is reached after (41-20)/10 = 2.1 s and left at 2.7 s
	local p = Poacher.new(Config, Layout, L, 5, fixedRng(0.9), 0)
	local ev = run(p, L, 30)
	eq(p.state, "caught", "a reckless poacher walking into an ON net is caught")
	eq(ev.caught, trap, "...by that net")
	eq(p.caughtOn, "in", "...on the way in")

	-- the careful one (roll 0.5 < 0.6) waits for the window
	local q = Poacher.new(Config, Layout, L, 5, fixedRng(0.5), 0)
	run(q, L, 60)
	eq(q.state, "gone", "a careful poacher times every crossing and gets away")
	truthy(q.waited > 0, "...having waited for the net")
end

do
	-- a snare placed on the path ahead catches it
	local L = blankLair()
	local p = Poacher.new(Config, Layout, L, 5, fixedRng(0.9), 0)
	run(p, L, 1)
	Layout.place(Config, L, 5, 4, "snare")
	local ev = run(p, L, 10)
	eq(p.state, "caught", "a snare dropped on the poacher's route catches it")
	eq(ev.caught and ev.caught.kind, "snare", "...and it was the snare")

	-- caught on the way OUT with loot: the step reports it so the server can put it back
	local L2 = blankLair()
	local q = Poacher.new(Config, Layout, L2, 5, fixedRng(0.9), 0)
	run(q, L2, 8.5)
	eq(q.state, "out", "leaving")
	q.loot = 123
	Layout.place(Config, L2, 5, 2, "snare")
	local ev2 = run(q, L2, 20)
	eq(q.state, "caught", "caught on the way out")
	eq(q.caughtOn, "out", "...recorded as out")
	eq(ev2.returned, 123, "...and the step hands the loot back")
end

do
	-- a snare dropped on the cell it is WAITING on catches it too
	local L = blankLair()
	Layout.place(Config, L, 5, 3, "laser")
	local trap = Layout.trapAt(L, 5, 3)
	trap.phase = 0
	local p = Poacher.new(Config, Layout, L, 5, fixedRng(0.5), 0)
	run(p, L, 1.6) -- at (5,2) by 1.6 s and waiting for the net
	local _, z = Poacher.position(Config, Layout, p)
	eq(z, 36, "waiting at the cell before the net")
	Layout.place(Config, L, 5, 2, "snare")
	run(p, L, 1.7)
	eq(p.state, "caught", "a snare under a waiting poacher catches it")
end

--============================================================================ no path

do
	local L = Layout.fromSpec(Config, { kind = "lair", lines = { { row = 3, cols = { 5 } } }, rocks = {} })
	-- force a wall-off that placement rules would refuse, straight into the data
	L.trapsByKey[Layout.key(5, 3)] = { kind = "snare", col = 5, row = 3 }
	table.insert(L.trapOrder, Layout.key(5, 3))
	eq(Poacher.new(Config, Layout, L, 5, fixedRng(0.5), 0), nil, "no route: no poacher")
end

--============================================================================ the catch-rate table

local function pct(xs, p)
	local s = table.clone(xs)
	table.sort(s)
	return s[math.min(#s, math.floor(p * #s) + 1)] or 0
end

local N = 4000
local function scenario(name, setup)
	local rng = Rng.new(4242)
	local caughtIn, caughtOut, thefts, trials = 0, 0, 0, 0
	local trips = {}
	local firstGrab = math.huge
	local incomplete = 0
	for s = 1, N do
		local L = Layout.generateLair(Config, Rng, Layout.lairSeed(Config, 500000 + s))
		local lr = Rng.new(s * 7919)
		if not setup(L, lr) then incomplete += 1 end
		for _, t in Layout.traps(L) do
			if t.kind == "laser" then t.phase = lr:next() * (t.on + t.off) end
		end
		local col = rng:below(9)
		local t0 = rng:next() * 100
		local p = Poacher.new(Config, Layout, L, col, rng, t0)
		if p then
			trials += 1
			local grabAt = nil
			local tt = t0
			while p.state ~= "caught" and p.state ~= "gone" and tt < t0 + 300 do
				tt += 5
				local ev = Poacher.step(Config, Layout, Heist, L, p, tt)
				if ev.grabbed then grabAt = ev.grabbedAt end
			end
			if grabAt then firstGrab = math.min(firstGrab, grabAt - t0) end
			if p.state == "caught" then
				if p.caughtOn == "in" then caughtIn += 1 else caughtOut += 1 end
			elseif p.state == "gone" then
				thefts += 1
				table.insert(trips, p.finishedAt - t0)
			end
		end
	end
	local cin, cout = caughtIn / trials, caughtOut / trials
	print(string.format("  %-40s caught %5.1f%% (in %4.1f, out %4.1f); theft %5.1f%%; trip median %.1f s; earliest grab %.2f s; %d of %d lairs refused a trap",
		name, 100 * (cin + cout), 100 * cin, 100 * cout, 100 * thefts / trials, pct(trips, 0.5), firstGrab, incomplete, N))
	return { caught = cin + cout, theft = thefts / trials, trials = trials, firstGrab = firstGrab }
end

local function gapsOf(L, i) return table.clone(L.lines[i].cols) end

-- Each setup places through Layout.place, so the placement rules apply exactly as in the game. A
-- lair whose rocks leave a gap unreachable refuses a trap there; those lairs are counted and
-- printed rather than silently measured as a different defense.
local none = scenario("no traps", function() return true end)
local one = scenario("one laser in a gap, no snares", function(L, r)
	local g = gapsOf(L, 1)
	return (Layout.place(Config, L, g[r:below(#g)], L.lines[1].row, "laser"))
end)
-- Force one line the way a player would: pick the laser gap, snare the other two, and if the rules
-- refuse (rocks can wall a gap in), try the next gap as the laser one. Returns false only when no
-- arrangement of that line is legal.
local function forceLine(L, r, i)
	local g = gapsOf(L, i)
	local row = L.lines[i].row
	local startAt = r:below(#g)
	for k = 0, #g - 1 do
		local laserCol = g[((startAt - 1 + k) % #g) + 1]
		local placed = {}
		local ok = true
		for _, c in g do
			if c ~= laserCol then
				if Layout.place(Config, L, c, row, "snare") then
					table.insert(placed, c)
				else
					ok = false
				end
			end
		end
		if ok and Layout.place(Config, L, laserCol, row, "laser") then
			return true
		end
		for _, c in placed do Layout.clear(L, c, row) end
	end
	return false
end
local line1 = scenario("one line forced (2 snares + 1 laser)", function(L, r)
	return forceLine(L, r, 1)
end)
local both = scenario("both lines forced (4 snares + 2 lasers)", function(L, r)
	local a = forceLine(L, r, 1)
	local b = forceLine(L, r, 2)
	return a and b
end)

eq(none.trials, N, "every undefended lair had a route")
eq(none.caught, 0, "an undefended lair never catches a poacher")
truthy(one.caught < line1.caught, "forcing a line beats a lone laser")
truthy(line1.caught < both.caught, "forcing both lines beats forcing one")
truthy(one.caught < 0.15, "an unforced laser barely matters")
truthy(both.theft > 0, "defense is never a wall: some thefts still succeed with both lines forced")
-- the race the design promises: 10 s of warning + 64 studs at 10 studs/s + a 2 s hold = 18.4 s
truthy(none.firstGrab + Config.Poacher.WarningSeconds >= 18.4 - 1e-6,
	string.format("no grab lands before 18.4 s after the warning starts (earliest %.2f)", none.firstGrab + Config.Poacher.WarningSeconds))

print(string.format("Poacher: %d passed, %d failed", passed, failed))
if failed > 0 then error("Poacher tests failed") end
