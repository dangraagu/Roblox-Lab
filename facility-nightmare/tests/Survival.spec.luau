-- Survival.spec — DESIGN.md §14 Survival invariants, written before the module.
-- Run: luau tests/Survival.spec.luau
local Config = require("../src/shared/Config")
local Survival = require("../src/shared/Survival")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local BASE = { batteryCap = 45, grace = 4, staminaCap = 4, secondWinds = 0 }
local function fresh(over)
	local e = table.clone(BASE)
	for k, v in over or {} do e[k] = v end
	return Survival.new(Config, e)
end
local function has(events, name)
	for _, e in events do if e == name then return true end end
	return false
end
local function run(s, input, seconds, dt)
	dt = dt or 0.1
	local all = {}
	local steps = math.floor(seconds / dt + 0.5)
	for _ = 1, steps do
		for _, e in Survival.step(Config, s, input, dt) do table.insert(all, e) end
	end
	return all
end

--============================================================ 1. battery and exposure

do
	local s = fresh()
	eq(s.battery, 45, "a run starts on a full battery")
	eq(s.exposure, 0, "…and no exposure")
	run(s, { wantLight = false, dark = false }, 10)
	eq(s.battery, 45, "light off in a lit room: no drain")
	run(s, { wantLight = true, dark = false }, 10)
	near(s.battery, 35, 1e-9, "light on in a LIT room drains 1/s (the player's own waste)")
	eq(s.exposure, 0, "…and exposure stays 0 in the light")
	run(s, { wantLight = true, dark = true }, 5)
	near(s.battery, 30, 1e-9, "light on in the dark drains 1/s")
	eq(s.exposure, 0, "light on in the dark: exposure HOLDS")
	run(s, { wantLight = false, dark = true }, 2)
	near(s.exposure, 2, 1e-9, "light off in the dark: exposure rises 1/s")
	near(s.battery, 30, 1e-9, "…and the battery is untouched")
	run(s, { wantLight = true, dark = true }, 3)
	near(s.exposure, 2, 1e-9, "turning the light back on in the dark holds exposure where it is")
	run(s, { wantLight = false, dark = false }, 1.5)
	near(s.exposure, 0.5, 1e-9, "in the light exposure recovers at 1/s")
	run(s, { wantLight = false, dark = false }, 5)
	eq(s.exposure, 0, "…down to 0, never below")
end

do -- the battery empties mid-tick: the rest of the tick is dark exposure, and the light goes off
	local s = fresh()
	s.battery = 0.05
	local ev = Survival.step(Config, s, { wantLight = true, dark = true }, 0.1)
	eq(s.battery, 0, "battery bottoms out at 0")
	eq(s.lightOn, false, "the flashlight turns itself off")
	truthy(has(ev, "batteryEmpty"), "…and says so")
	near(s.exposure, 0.05, 1e-9, "the half-tick after the battery died counts as exposure")
	local ev2 = Survival.step(Config, s, { wantLight = true, dark = true }, 0.1)
	eq(s.lightOn, false, "an empty battery cannot be turned on")
	truthy(not has(ev2, "batteryEmpty"), "'battery empty' is said once, not every tick")
	near(s.exposure, 0.15, 1e-9, "…so asking for light on an empty battery still exposes you")
end

--============================================================ 2. death at grace, Second Wind

do
	local s = fresh()
	local ev = run(s, { wantLight = false, dark = true }, 3.9)
	eq(s.dead, false, "3.9 s in the dark: alive")
	ev = run(s, { wantLight = false, dark = true }, 0.1)
	eq(s.dead, true, "4.0 s in the dark (forty 0.1 s ticks): the dark takes you")
	truthy(has(ev, "dead"), "…with a 'dead' event")
	local ev2 = Survival.step(Config, s, { wantLight = false, dark = true }, 0.1)
	eq(#ev2, 0, "a dead state emits nothing more")
end

do
	local s = fresh({ grace = 7 })
	run(s, { wantLight = false, dark = true }, 6.9)
	eq(s.dead, false, "Night Eyes x3: grace 7 s")
	run(s, { wantLight = false, dark = true }, 0.1)
	eq(s.dead, true, "…and death at 7 s")
end

do
	local s = fresh({ secondWinds = 1 })
	s.battery = 0
	local ev = run(s, { wantLight = false, dark = true }, 4)
	eq(s.dead, false, "Second Wind cancels the first killing moment")
	truthy(has(ev, "secondWind"), "…and says so")
	eq(s.exposure, 0, "…exposure to 0")
	near(s.battery, 10, 1e-9, "…battery +10 s")
	eq(s.secondWinds, 0, "…and it is spent")
	run(s, { wantLight = false, dark = true }, 4)
	eq(s.dead, true, "it never fires twice")
end

do
	local s = fresh({ secondWinds = 1 })
	s.battery = 40
	run(s, { wantLight = false, dark = true }, 4)
	near(s.battery, 45, 1e-9, "Second Wind's battery respects the cap")
end

--============================================================ 3. bad dt

do
	for _, dt in { 0 / 0, -1, 0, "0.1", nil, math.huge } do
		local s = fresh()
		s.exposure = 1
		s.battery = 20
		s.stamina = 2
		local before = string.format("%s|%s|%s|%s|%s", s.battery, s.exposure, s.stamina, tostring(s.dead), tostring(s.lightOn))
		local ev = Survival.step(Config, s, { wantLight = true, wantSprint = true, dark = true }, dt)
		local after = string.format("%s|%s|%s|%s|%s", s.battery, s.exposure, s.stamina, tostring(s.dead), tostring(s.lightOn))
		eq(after, before, "dt = " .. tostring(dt) .. " changes nothing")
		eq(#ev, 0, "dt = " .. tostring(dt) .. " emits nothing")
	end
end

--============================================================ 4. cells

do
	local s = fresh()
	eq(Survival.pickupCell(Config, s), false, "a cell is NOT consumed at a full battery")
	eq(s.battery, 45, "…and the battery is unchanged")
	s.battery = 20
	eq(Survival.pickupCell(Config, s), true, "below the cap a cell is consumed")
	near(s.battery, 35, 1e-9, "…adding 15 s")
	s.battery = 40
	eq(Survival.pickupCell(Config, s), true, "a cell that would overfill is still consumed whole")
	eq(s.battery, 45, "…capped at the battery size")
	local big = fresh({ batteryCap = 75 })
	eq(big.battery, 75, "Deep Cell x3: the run starts at 75")
end

--============================================================ sprint and stamina

do
	local s = fresh()
	eq(s.stamina, 4, "full stamina at run start")
	run(s, { wantSprint = true, dark = false }, 1)
	near(s.stamina, 3, 1e-9, "sprinting drains 1/s")
	eq(s.sprinting, true, "…and the state says sprinting")
	run(s, { wantSprint = true, dark = false }, 3)
	near(s.stamina, 0, 1e-9, "…to empty")
	Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1)
	eq(s.sprinting, false, "no stamina, no sprint, even while it is requested")
	near(s.stamina, 0.05, 1e-9, "…and that refused tick already refills (0.1 s x 4/8)")
	run(s, { wantSprint = false, dark = false }, 3.9)
	near(s.stamina, 2, 1e-6, "stamina refills over 8 s from empty (half in 4 s)")
	run(s, { wantSprint = false, dark = false }, 10)
	eq(s.stamina, 4, "…capped at full")
	local m = fresh({ staminaCap = 7 })
	m.stamina = 0
	run(m, { wantSprint = false, dark = false }, 4)
	near(m.stamina, 3.5, 1e-6, "Marathon x3: 7 s of stamina still refills empty-to-full in 8 s")
end

do -- EXHAUSTION. Found by robloxemu/check_facilitynightmare.luau, not by this file: with sprint
	-- still held at empty stamina, each refused tick refilled 0.05 s, which re-armed sprint on the
	-- next tick, so a held Shift alternated 24/16 every 0.1 s — an average of 20 studs/s for ever.
	local s = fresh()
	run(s, { wantSprint = true, dark = false }, 4)
	eq(s.stamina, 0, "four seconds of sprint empties the bar")
	local sprintTicks = 0
	for _ = 1, 50 do
		Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1)
		if s.sprinting then sprintTicks += 1 end
	end
	eq(sprintTicks, 0, "holding sprint on an empty bar never sprints again, not even for a tick")
	truthy(s.stamina > 2, "…while the bar refills (" .. string.format("%.2f", s.stamina) .. ")")
	Survival.step(Config, s, { wantSprint = false, dark = false }, 0.1)
	Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1)
	eq(s.sprinting, true, "releasing and pressing again sprints on whatever has refilled")
end

do -- A PRESS re-arms, even with no release tick in between. Found by
	-- robloxemu/check_facilitynightmare_input.luau pressing the real SPRINT button: a phone's SPRINT
	-- is a tap, so after the bar ran out the request was still "held", and the next tap sent a
	-- release; every sprint after the first cost two taps. A release and a press landing inside one
	-- 0.1 s tick are the same thing to a player.
	local s = fresh()
	run(s, { wantSprint = true, dark = false }, 4)
	for _ = 1, 30 do Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1) end
	eq(s.sprinting, false, "control: still exhausted while the request is merely held")
	Survival.step(Config, s, { wantSprint = true, sprintPressed = true, dark = false }, 0.1)
	eq(s.sprinting, true, "a fresh press sprints on what has refilled, with no release tick first")
	-- …and holding after that press is the ordinary rule again
	for _ = 1, 100 do Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1) end
	eq(s.sprinting, false, "held past empty again, it exhausts again")
	local flips = 0
	local was = s.sprinting
	for _ = 1, 50 do
		Survival.step(Config, s, { wantSprint = true, dark = false }, 0.1)
		if s.sprinting ~= was then flips += 1; was = s.sprinting end
	end
	eq(flips, 0, "…and a held request still never flip-flops")
	-- a press with the bar empty does not sprint for nothing
	local e = fresh()
	e.stamina = 0
	e.exhausted = true
	Survival.step(Config, e, { wantSprint = true, sprintPressed = true, dark = false }, 0.1)
	-- that tick's press found 0 stamina: no sprint, and the bar refills a crumb
	eq(e.sprinting, false, "a press on a bar that is exactly empty does not sprint")
end

do -- NO OVERDRAFT (REVIEW-1 finding A3). A sprint tick moves the player dt at SprintSpeed, so it
	-- must cost dt of stamina. It used to start on any crumb above zero: a press on every tick
	-- (Sprint(true) fired each tick re-arms exhaustion) bought a full 0.1 s at 24 studs/s with the
	-- 0.05 s one regen tick had refilled, for an average of 20.03 studs/s for ever against 18.67
	-- for the best honest hold-release-refill pattern. Measured with the server's tick order.
	local function meanSpeed(policy, seconds, dtOf)
		local s = fresh()
		local want, pressed = false, false
		local dist, t, tick = 0, 0, 0
		local speed = Config.Movement.WalkSpeed
		while t < seconds - 1e-9 do
			tick += 1
			local dt = dtOf and dtOf(tick) or 0.1
			dist += speed * dt -- this tick moves at the speed set LAST tick
			t += dt
			want, pressed = policy(tick, s, want)
			Survival.step(Config, s, { wantSprint = want, sprintPressed = pressed, dark = false }, dt)
			speed = if s.sprinting then Config.Movement.SprintSpeed else Config.Movement.WalkSpeed
		end
		return dist / t
	end
	local honest = meanSpeed(function(_, s, want)
		if s.exhausted then return false, false end
		if not want and s.stamina >= s.staminaCap - 1e-9 then return true, true end
		return want, false
	end, 600)
	near(honest, 18.67, 0.01, "control: the best honest pattern (hold to empty, release, refill) averages 18.67 studs/s")
	-- The ceiling any pattern can reach in T seconds when every sprint second is paid for: sprint
	-- time S <= cap + (T - S) x cap / regen. Written out for cap 4, regen 8, T 600: S <= 202.67 s,
	-- 16 + 8 x 202.67 / 600 = 18.702. (Hold-release-refill ends the 600 s on a full, unspent bar,
	-- which is the 0.03 between it and the ceiling.)
	local spam = meanSpeed(function() return true, true end, 600)
	truthy(spam <= 18.702 + 0.005, string.format("a fresh press on EVERY tick stays under the paid-for ceiling of 18.70 studs/s over 600 s (got %.2f; honest %.2f)", spam, honest))

	-- The conservation law behind that number, fuzzed: every second of sprint was paid for by the
	-- starting bar or by refill earned while walking. Random press/hold/release patterns, jittery dt.
	local seed = 12345
	local function rnd()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	local worst = -math.huge
	for trial = 1, 200 do
		local s = fresh({ staminaCap = 4 + (trial % 4) })
		local sprintT, walkT = 0, 0
		local want = false
		for _ = 1, 3000 do
			local dt = 0.08 + 0.04 * rnd()
			local r = rnd()
			local pressed = false
			if r < 0.3 then want, pressed = true, true elseif r < 0.45 then want = false end
			Survival.step(Config, s, { wantSprint = want, sprintPressed = pressed, dark = false }, dt)
			if s.sprinting then sprintT += dt else walkT += dt end
		end
		local earned = s.staminaCap + walkT * s.staminaCap / Config.Movement.StaminaRegenSeconds
		worst = math.max(worst, sprintT - earned)
	end
	truthy(worst <= 1e-6, string.format("no pattern sprints longer than the bar plus its refill (worst excess %.4f s over 200 x 3000 ticks)", worst))

	-- a request that can no longer fund a whole tick is exhausted, so a HELD key never flip-flops
	-- even when the server tick jitters (a crumb below dt left over, then refilled past dt)
	local j = fresh()
	local k = 0
	local sprintTicksAfterEmpty, emptied = 0, false
	for _ = 1, 900 do
		k += 1
		local dt = 0.09 + 0.02 * ((k * 7919) % 13) / 12
		Survival.step(Config, j, { wantSprint = true, sprintPressed = k == 1, dark = false }, dt)
		if emptied and j.sprinting then sprintTicksAfterEmpty += 1 end
		if not j.sprinting then emptied = true end
	end
	eq(sprintTicksAfterEmpty, 0, "held through the end of the bar with a jittering tick, sprint never comes back without a press")
end

do -- exposure fraction for the HUD, and the per-floor reset
	local s = fresh()
	s.exposure = 1
	near(Survival.exposureFraction(s), 0.25, 1e-9, "exposure fraction = exposure / grace")
	Survival.arrive(s)
	eq(s.exposure, 0, "arriving on a new sublevel clears exposure")
	eq(s.lightOn, false, "…and the flashlight starts off")
end

print(string.format("Survival: %d passed, %d failed", passed, failed))
