-- Spec for Climb: Fork Tower's progress value, the fork-pad sanctuary and the hazard gate.
-- Run: luau tests/Climb.spec.luau
--
-- Climb is the fork-tower half of "the world changes as you progress" (EnvBands is the game-agnostic
-- half, copied verbatim from +1 Jump). What it has to guarantee, and why each one matters here:
--   * PROGRESS IS FLOORS CLIMBED, from the server's floor and the player's own altitude inside the
--     section they are climbing. At a fork it is EXACTLY (floor - 1): a function of the floor number
--     alone, so the world a player sees in front of two unread doors cannot depend on anything the
--     read is supposed to sell (REVIEW-3, REVIEW-4). A trapped section is longer, so it moves the
--     blend more slowly, but only after the door was chosen.
--   * A FALL NEVER TAKES THE WORLD BACK: below the fork pad the fraction clamps to 0.
--   * THE FORK PAD IS A SANCTUARY: the hazard clock never runs there, nothing launches there and
--     nothing hits there. Reading costs Config.Fork.ReadSeconds on the server's clock, and a hazard
--     that could knock a reader off the pad would add a cost to reading that the measured
--     break-even (tests/readcost.measure.luau) never priced.
local Climb = require("../src/shared/Climb")

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
	tol = tol or 1e-9
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local FLOORS = 10

--================================================================ progress

-- A tower as the server builds it: fork n's top at forkY[n], section n's exit platform top at
-- exitY[n], and fork n+1 sitting at the exit's height (Main.server buildSection).
local forkY = { [1] = 0, [2] = 20, [3] = 44 }
local exitY = { [1] = 20, [2] = 44 }

-- at a fork (section not built yet): exactly floor - 1, whatever the altitude
eq(Climb.progress(1, false, 3, forkY, {}, FLOORS), 0, "at fork 1, progress is 0")
eq(Climb.progress(3, false, 47, forkY, exitY, FLOORS), 2, "at fork 3 (its section not built), progress is exactly 2")
eq(Climb.progress(3, false, -500, forkY, exitY, FLOORS), 2, "a player who fell below fork 3 still reads 2: a fall never takes the world back")
eq(Climb.progress(3, false, 9000, forkY, exitY, FLOORS), 2, "and a player far above it reads 2 as well: at a fork only the floor counts")

-- climbing a section: floor - 1 + the fraction of the section's height climbed
local climbing = { [1] = 0, [2] = 20 }
local climbExit = { [1] = 20, [2] = 44 }
approx(Climb.progress(2, false, 20, climbing, climbExit, FLOORS), 1, "on fork 2's pad height with section 2 built: 1.0")
approx(Climb.progress(2, false, 32, climbing, climbExit, FLOORS), 1.5, "half-way up section 2: 1.5")
approx(Climb.progress(2, false, 44, climbing, climbExit, FLOORS), 2, "on section 2's exit: 2.0")
approx(Climb.progress(2, false, 60, climbing, climbExit, FLOORS), 2, "above the exit: clamped to 2.0 (never past the next fork)")
approx(Climb.progress(2, false, -100, climbing, climbExit, FLOORS), 1, "fallen below the section: clamped to 1.0")

-- continuity across the server's own step: standing on section n's exit reads n, and the moment
-- the server moves the player to floor n+1 (section n+1 not built) it reads n as well
approx(Climb.progress(2, false, 44, climbing, climbExit, FLOORS), Climb.progress(3, false, 44, forkY, exitY, FLOORS),
	"reaching the exit (floor 2 climbing) and arriving at fork 3 read the same progress: no cut at the step")

-- the summit is the top of the progress scale, however high it is
eq(Climb.progress(11, true, 1234, forkY, exitY, FLOORS), FLOORS, "at the summit, progress is the floor count")
eq(Climb.progress(10, true, 0, forkY, exitY, FLOORS), FLOORS, "the summit flag wins over the floor number")

-- garbage in, a band out
eq(Climb.progress(0, false, 0, {}, {}, FLOORS), 0, "floor 0 (no profile yet) is clamped to floor 1")
eq(Climb.progress(99, false, 0, {}, {}, FLOORS), FLOORS - 1, "a floor past the top without the summit flag clamps to the last fork")
eq(Climb.progress(2, false, 0 / 0, climbing, climbExit, FLOORS), 1, "NaN altitude reads the floor's own value")
eq(Climb.progress(2, false, 30, { [2] = 20 }, { [2] = 20 }, FLOORS), 1, "a degenerate section (exit not above the fork) reads the floor's own value")
eq(Climb.progress(0 / 0, false, 0, {}, {}, FLOORS), 0, "a NaN floor reads floor 1")

-- monotone in altitude while climbing (a smooth blend has no fold)
do
	local last, ok = -1, true
	for y = -50, 80, 0.5 do
		local p = Climb.progress(2, false, y, climbing, climbExit, FLOORS)
		if p < last - 1e-12 then ok = false end
		last = p
	end
	truthy(ok, "progress never decreases as the climber rises through a section")
end

--================================================================ the named floor

eq(Climb.namedFloor(1, false, FLOORS), 1, "floor 1 is named floor 1")
eq(Climb.namedFloor(10, false, FLOORS), 10, "floor 10 is named floor 10")
eq(Climb.namedFloor(11, true, FLOORS), FLOORS + 1, "the summit is named floor 11 (one past the top)")
eq(Climb.namedFloor(10, true, FLOORS), FLOORS + 1, "the summit flag names the summit whatever the floor says")
eq(Climb.namedFloor(0, false, FLOORS), 1, "no profile yet: floor 1")
eq(Climb.namedFloor(55, false, FLOORS), FLOORS, "past the top without the summit flag: the last floor")
-- the NAMED floor and the continuous progress agree at every fork: floor n reads n - 1
for n = 1, FLOORS do
	eq(Climb.namedFloor(n, false, FLOORS) - 1, Climb.progress(n, false, 0, {}, {}, FLOORS),
		"fork " .. n .. ": the named floor and the progress agree")
end
eq(Climb.namedFloor(11, true, FLOORS) - 1, Climb.progress(11, true, 0, {}, {}, FLOORS), "the summit: they agree too")

--================================================================ the sanctuary

-- a pad as the server builds it: top-centre (x, y, z) and its footprint (sx, sz)
local pad = { x = 10, y = 0, z = 14, sx = 26, sz = 20 }
truthy(Climb.onPad({ x = 10, y = 3, z = 14 }, pad, 1.5, 12), "a root standing in the middle of the pad is on it")
truthy(Climb.onPad({ x = 10 + 13 + 1.4, y = 3, z = 14 }, pad, 1.5, 12), "a root just past the edge, still overlapping it by the player's radius, is on it")
truthy(not Climb.onPad({ x = 10 + 13 + 1.6, y = 3, z = 14 }, pad, 1.5, 12), "a root further out than edge + radius is not")
truthy(not Climb.onPad({ x = 10, y = 3, z = 14 + 10 + 1.6 }, pad, 1.5, 12), "the same along z")
truthy(not Climb.onPad({ x = 10, y = -2, z = 14 }, pad, 1.5, 12), "below the pad's top is not on it (falling past)")
truthy(Climb.onPad({ x = 10, y = 11.9, z = 14 }, pad, 1.5, 12), "a jump above the pad is still over the sanctuary")
truthy(not Climb.onPad({ x = 10, y = 12.1, z = 14 }, pad, 1.5, 12), "but not higher than the ceiling")
truthy(not Climb.onPad({ x = 0 / 0, y = 3, z = 14 }, pad, 1.5, 12), "a NaN position is never on a pad")
do
	local pads = { pad, { x = 200, y = 40, z = 90, sx = 26, sz = 20 } }
	truthy(Climb.inSanctuary({ x = 200, y = 43, z = 90 }, pads, 1.5, 12), "inSanctuary finds the second pad")
	truthy(not Climb.inSanctuary({ x = 100, y = 43, z = 90 }, pads, 1.5, 12), "and nothing between them")
	truthy(not Climb.inSanctuary({ x = 10, y = 3, z = 14 }, {}, 1.5, 12), "no pads, no sanctuary")
end

--================================================================ the hazard gate

-- climbing = the player's current floor has its section built (the door is chosen) and they are not
-- at the summit. Everything else is not climbing: an unanswered fork, the summit, no lane at all.
do
	local g = Climb.gate({ climbing = true, sanctuary = false, resting = false })
	truthy(g.clock and g.launch and g.hit and not g.dismiss, "climbing a section: the clock runs, a hazard may launch and hit")
end
do
	local g = Climb.gate({ climbing = true, sanctuary = false, resting = true })
	truthy(not g.clock and not g.launch, "resting: the clock freezes and nothing launches")
	truthy(g.hit, "... but a hazard ALREADY in flight is not cancelled by resting (rest is never a panic button)")
	truthy(not g.dismiss, "and nothing is dismissed")
end
do
	local g = Climb.gate({ climbing = true, sanctuary = true, resting = false })
	truthy(not g.clock and not g.launch and not g.hit, "on a fork pad while climbing (the next pad): no clock, no launch, no hit")
	truthy(g.dismiss, "and a hazard in flight is dismissed: the pad is where the player reads")
end
do
	local g = Climb.gate({ climbing = false, sanctuary = true, resting = false })
	truthy(not g.clock and not g.launch and not g.hit and g.dismiss, "at an unanswered fork, on the pad: nothing runs, anything flying is dismissed")
end
do
	local g = Climb.gate({ climbing = false, sanctuary = false, resting = false })
	truthy(not g.clock and not g.launch, "not climbing (fork answered by nobody, summit, no lane): the clock is frozen, nothing launches")
	-- Review 2026-09-24 (low): the next fork's LES prompt reaches 16 studs (Main.server buildFork) and
	-- the next pad sits 2 studs past the exit, so the front 3.5 studs of every exit platform are in
	-- reach of the prompt and OFF the pad. With a hazard launched in the last seconds of the climb, a
	-- player who pressed R the moment the prompt appeared on the exit's edge was knocked 0.97 s into
	-- the 1.1 s hold (measured through the real client). Clearing the floor ends the climb, so it ends
	-- what the climb launched: from that moment the player can be reading.
	truthy(g.dismiss, "the floor is cleared (not climbing), off any pad: a hazard still in flight is dismissed")
	truthy(not g.hit, "and nothing hits once the floor is cleared (the exit's edge is in the next read's reach)")
end
-- every combination: the clock runs ONLY while climbing, off a pad, not resting; launch never
-- without the clock; hit only while climbing and never on a pad; dismiss on a pad AND whenever the
-- player is not climbing (the floor is cleared, the summit, no lane)
do
	local ok = true
	for _, c in { true, false } do
		for _, s in { true, false } do
			for _, r in { true, false } do
				local g = Climb.gate({ climbing = c, sanctuary = s, resting = r })
				if g.clock ~= (c and not s and not r) then ok = false end
				if g.launch and not g.clock then ok = false end
				if g.hit ~= (c and not s) then ok = false end
				if g.dismiss ~= (s or not c) then ok = false end
				if g.hit and g.dismiss then ok = false end
			end
		end
	end
	truthy(ok, "the gate's truth table holds for all eight combinations")
end

--================================================================ the clock goes the short way round

-- Lighting.ClockTime is a dial. A glide from 23.9 (the night summit) to 0.5 (the dungeon, after a
-- rebirth) must pass through midnight, not back through noon; nearestClock picks the reading of
-- `current` (mod 24) nearest to `target`, so a plain approach() then takes the short arc.
approx(Climb.nearestClock(23.9, 0.5), -0.1, "23.9 toward 0.5 reads -0.1: forward through midnight")
approx(Climb.nearestClock(0.5, 23.9), 24.5, "0.5 toward 23.9 reads 24.5: back through midnight")
approx(Climb.nearestClock(17.6, 0.5), 17.6 - 24, "the server's 17.6 toward the dungeon's 0.5 goes forward through the evening")
approx(Climb.nearestClock(8.6, 16.4), 8.6, "8.6 toward 16.4 stays: already the short way")
approx(Climb.nearestClock(30, 5), 6, "any reading is folded onto the dial first")
approx(Climb.nearestClock(-3, 2), -3, "negative readings too")
do
	local ok = true
	for c = 0, 23.5, 0.5 do
		for t = 0, 23.5, 0.5 do
			local n = Climb.nearestClock(c, t)
			if math.abs(n - t) > 12 + 1e-9 then ok = false end
			if math.abs(((n - c) % 24)) > 1e-9 and math.abs(((n - c) % 24) - 24) > 1e-9 then ok = false end
		end
	end
	truthy(ok, "for every pair on the half hour: the same time of day, never more than 12 h from the target")
end
approx(Climb.clockOf(24.5), 0.5, "clockOf folds onto [0, 24)")
approx(Climb.clockOf(-0.1), 23.9, "clockOf folds a negative reading")
approx(Climb.clockOf(12), 12, "clockOf leaves the dial alone")

print(string.format("Climb: %d passed, %d failed", passed, failed))
