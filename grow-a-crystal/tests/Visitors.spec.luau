-- Spec for Visitors: the rare, HARMLESS ambient events of the cavern (a moth swirl, a bat swoop).
-- Run: luau tests/Visitors.spec.luau
--
-- Grow a Crystal is an idle game with no failure state, so it has no knock-down hazards at all
-- (EYECANDY.md §3 says why). What it keeps from +1 Jump's hazard scheduler is the CLOCK: something
-- rare and pretty happens about once every 2-3 minutes of play, never two at once, never in the
-- first band (a new player learns the loop in peace), and a player who RESTS is left alone.
-- The properties pinned here:
--   * rarity: launches IntervalMin..IntervalMax seconds apart (measured over simulated hours);
--   * one at a time: a visitor in flight blocks the next;
--   * rest FREEZES the clock and never resets it, so toggling rest does not change how many
--     visitors an hour of play brings (the same exploit probe +1 Jump runs, although nothing here
--     could be gained by it: a visitor takes nothing and gives nothing);
--   * an event already in flight finishes while resting (rest never deletes something on screen);
--   * a quiet band re-rolls a due visitor instead of releasing a backlog when a new band opens;
--   * the module is pure: injected rand, no Roblox.
local Visitors = require("../src/shared/Visitors")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local function lcg(seed)
	local s = seed
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

local cfg = {
	IntervalMin = 120,
	IntervalMax = 180,
	Kinds = {
		mothSwirl = { seconds = 7 },
		batSwoop = { seconds = 6 },
	},
}

--=========================================================================== validate
do
	truthy(Visitors.validate(cfg), "the reference config validates")
	local function bad(mut, why)
		local c = table.clone(cfg)
		c.Kinds = table.clone(cfg.Kinds)
		mut(c)
		local ok = Visitors.validate(c)
		truthy(not ok, "validate rejects " .. why)
	end
	bad(function(c) c.IntervalMin = 0 end, "IntervalMin 0")
	bad(function(c) c.IntervalMax = 100 end, "IntervalMax < IntervalMin")
	bad(function(c) c.Kinds = nil end, "no Kinds")
	bad(function(c) c.Kinds.batSwoop = { seconds = 0 } end, "a kind that lasts 0 s")
	bad(function(c) c.Kinds.batSwoop = { seconds = 130 } end, "a kind that outlasts IntervalMin (two could overlap)")
	bad(function(c) c.Kinds.batSwoop = {} end, "a kind with no duration")
	eq(select(1, Visitors.validate(nil)), false, "validate rejects nil")
end

--=========================================================================== clock basics
do
	local rand = lcg(7)
	local clock = Visitors.newClock(cfg, rand)
	truthy(clock.dueIn >= cfg.IntervalMin and clock.dueIn <= cfg.IntervalMax,
		"the first visitor is due IntervalMin..IntervalMax seconds in (" .. tostring(clock.dueIn) .. ")")
	eq(clock.active, nil, "nothing is flying at start")

	-- step until the first launch, climbing (not resting), in a band that has kinds
	local t, ev = 0, nil
	while t < 400 do
		ev = Visitors.step(clock, cfg, 0.5, { resting = false, kinds = { "batSwoop" } }, rand)
		t += 0.5
		if ev then break end
	end
	truthy(ev ~= nil and ev.type == "launch", "a visitor launches")
	eq(ev and ev.kind, "batSwoop", "of a kind the band allows")
	truthy(t >= cfg.IntervalMin and t <= cfg.IntervalMax + 0.5, "at the scheduled time (" .. t .. " s)")
	truthy(clock.active ~= nil, "and it is now in flight")
	eq(clock.active and clock.active.seconds, 6, "with the kind's duration")

	-- while it flies, nothing else launches, even with the clock far overdue
	clock.dueIn = -1000
	local more = 0
	for _ = 1, 10 do
		local e = Visitors.step(clock, cfg, 0.5, { resting = false, kinds = { "batSwoop" } }, rand)
		if e and e.type == "launch" then more += 1 end
	end
	eq(more, 0, "never two at once")
end

--=========================================================================== quiet band
do
	local rand = lcg(11)
	local clock = Visitors.newClock(cfg, rand)
	local launches = 0
	for _ = 1, 3600 * 2 do
		local e = Visitors.step(clock, cfg, 0.5, { resting = false, kinds = {} }, rand)
		if e and e.type == "launch" then launches += 1 end
	end
	eq(launches, 0, "a band with no visitor kinds never launches (the first band stays calm)")
	truthy(clock.dueIn > 0, "a due visitor in a quiet band is re-rolled, never stored up")
	-- entering a band with kinds: the next launch still waits a real interval, no backlog burst
	local t = 0
	while t < 400 do
		local e = Visitors.step(clock, cfg, 0.5, { resting = false, kinds = { "mothSwirl" } }, rand)
		t += 0.5
		if e and e.type == "launch" then break end
	end
	truthy(t > 0.5, "the first launch after a quiet band is not immediate (" .. t .. " s)")
	truthy(t <= cfg.IntervalMax + 0.5, "and not later than one interval")
end

--=========================================================================== rest
do
	local rand = lcg(5)
	local clock = Visitors.newClock(cfg, rand)
	local due = clock.dueIn
	local restLaunches = 0
	for _ = 1, 2000 do
		local e = Visitors.step(clock, cfg, 0.5, { resting = true, kinds = { "batSwoop" } }, rand)
		if e and e.type == "launch" then restLaunches += 1 end
	end
	eq(restLaunches, 0, "no launch in 1000 s of rest")
	eq(clock.dueIn, due, "resting FREEZES the clock (1000 s of rest moved it by nothing)")
	-- and it does not RESET it either: 30 s of play then rest, the remaining time is kept
	for _ = 1, 60 do Visitors.step(clock, cfg, 0.5, { resting = false, kinds = { "batSwoop" } }, rand) end
	local kept = clock.dueIn
	truthy(math.abs(kept - (due - 30)) < 1e-9, "30 s of play moved it by 30 s")
	for _ = 1, 200 do Visitors.step(clock, cfg, 0.5, { resting = true, kinds = { "batSwoop" } }, rand) end
	eq(clock.dueIn, kept, "a second rest keeps the remaining time, never resets it")

	-- an event already in flight finishes during rest; rest never deletes it early
	clock.dueIn = 0.1
	local e = Visitors.step(clock, cfg, 0.5, { resting = false, kinds = { "batSwoop" } }, rand)
	eq(e and e.type, "launch", "launch for the in-flight test")
	local done, doneAt = false, 0
	for i = 1, 40 do
		local d = Visitors.step(clock, cfg, 0.5, { resting = true, kinds = { "batSwoop" } }, rand)
		if d and d.type == "done" then done = true; doneAt = i * 0.5; break end
	end
	truthy(done, "the visitor in flight finishes while the player rests")
	eq(doneAt, 6, "at its own end time, not earlier")
end

--=========================================================================== measured rarity
local function measure(restPattern, seconds, seed)
	local rand = lcg(seed)
	local clock = Visitors.newClock(cfg, rand)
	local launches, gaps, last, maxActive = 0, {}, nil, 0
	local playing = 0
	local t = 0
	local dt = 0.25
	while playing < seconds do
		local resting = restPattern(t)
		local e = Visitors.step(clock, cfg, dt, { resting = resting, kinds = { "mothSwirl", "batSwoop" } }, rand)
		if not resting then playing += dt end
		if e and e.type == "launch" then
			launches += 1
			if last then table.insert(gaps, playing - last) end
			last = playing
		end
		maxActive = math.max(maxActive, clock.active and 1 or 0)
		t += dt
	end
	return launches, gaps, maxActive
end

do
	local H = 20 * 3600
	local n, gaps, maxActive = measure(function() return false end, H, 3)
	local perMinute = n / (H / 60)
	print(string.format("  measured: %d visitors in 20 h of play = one per %.1f s (%.3f/min)", n, H / n, perMinute))
	local lo, hi = math.huge, 0
	for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g) end
	print(string.format("  gaps between launches: %.1f .. %.1f s of play", lo, hi))
	truthy(H / n >= 120 and H / n <= 190, "about one visitor every 2-3 minutes of play")
	truthy(lo >= cfg.IntervalMin, "never closer than IntervalMin")
	truthy(hi <= cfg.IntervalMax + 0.5, "never further apart than IntervalMax (launch to launch, in play time)")
	eq(maxActive, 1, "never more than one at a time")

	-- the rest-toggle probe: resting must not thin visitors per hour of PLAY
	local nToggle = measure(function(t) return (t % 14) < 7 end, H, 3)
	local nLong = measure(function(t) return (t % 150) < 40 end, H, 3)
	print(string.format("  per 20 h of play: never rests %d · toggles every 7 s %d · rests 40 of every 150 s %d", n, nToggle, nLong))
	truthy(math.abs(nToggle - n) <= 1, "toggling rest every 7 s does not change visitors per hour of play")
	truthy(math.abs(nLong - n) <= 1, "long rests do not change visitors per hour of play")
end

--=========================================================================== purity
do
	local a = measure(function() return false end, 3600, 99)
	local b = measure(function() return false end, 3600, 99)
	eq(a, b, "same rand, same visitors (the module keeps no hidden state)")
end

print(string.format("Visitors: %d passed, %d failed", passed, failed))
if failed > 0 then error("Visitors spec failed", 0) end
