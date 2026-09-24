-- Spec for Rest: what "pause" means in FACILITY. Run: luau tests/Rest.spec.luau
--
-- A Roblox server cannot stop the world for one player, and in this game the world IS the clock: a
-- run is the blackout front spreading through the floor. Freezing it for one player would be the
-- exploit the owner warned about (rest just before a room dies, walk out when you like). So rest is
-- between runs, in the break room, where no clock, front, hazard or penalty exists to pause:
--   * resting is allowed only in the phases Config.Rest.Phases lists, and validate() refuses any
--     list that names a phase of a run (ride, floor, dying) or anything it does not know;
--   * you rest by sitting on a break-room bench, or by standing still there for IdleSeconds;
--   * getting up, moving, stepping into the elevator car or the run starting ends it;
--   * the module has no hook into the run at all: Rest.PAUSES_RUN_CLOCK is false and stays false.
-- Adapted from plus1-jump's Rest (a state, not a frozen world); pure, game-agnostic in shape.
local Rest = require("../src/shared/Rest")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local cfg = { Phases = { hub = true }, IdleSeconds = 20 }

local function ctx(phase, seated, moving, boarding)
	return { phase = phase, seated = seated == true, moving = moving == true, boarding = boarding == true }
end

--================================================================ validate

truthy((Rest.validate(cfg)), "rest in the break room only: valid")
for _, phase in { "floor", "ride", "dying" } do
	local bad = { Phases = { hub = true, [phase] = true }, IdleSeconds = 20 }
	local ok, err = Rest.validate(bad)
	eq(ok, false, "rest allowed in '" .. phase .. "' is rejected: it is part of a run")
	truthy(type(err) == "string" and #err > 0, "…and says why (" .. tostring(err) .. ")")
end
eq((Rest.validate({ Phases = { lobby = true }, IdleSeconds = 20 })), false, "an unknown phase is rejected (a typo must not open a hole)")
eq((Rest.validate({ Phases = {}, IdleSeconds = 20 })), false, "no phase at all is rejected (rest would silently never happen)")
eq((Rest.validate({ Phases = { hub = true }, IdleSeconds = -1 })), false, "a negative IdleSeconds is rejected")
eq((Rest.validate({ Phases = { hub = false }, IdleSeconds = 20 })), false, "hub = false is not a phase list")
eq(Rest.PAUSES_RUN_CLOCK, false, "rest never pauses the run clock (the blackout front)")

--================================================================ allowed

truthy(Rest.allowed(cfg, "hub"), "the break room is a place to rest")
for _, phase in { "ride", "floor", "dying", "nonsense" } do
	eq(Rest.allowed(cfg, phase), false, "…'" .. phase .. "' is not")
end
eq(Rest.allowed(cfg, nil), false, "no state yet (loading): not resting")

--================================================================ the bench

do
	local s = Rest.new()
	eq(Rest.isResting(s), false, "a new player is not resting")
	eq(Rest.hazardsMayRun(s), true, "…and hazards may run (there are none in the break room anyway)")
	eq(Rest.update(s, cfg, 0.1, ctx("hub", true)), "started", "sitting on a bench in the break room: rest starts at once")
	eq(s.source, "bench", "…from the bench")
	eq(Rest.hazardsMayRun(s), false, "…and nothing may bother a resting player")
	local events = 0
	for _ = 1, 36000 do
		if Rest.update(s, cfg, 0.1, ctx("hub", true)) ~= nil then events += 1 end
	end
	eq(events, 0, "an hour on the bench stays rest")
	eq(Rest.update(s, cfg, 0.1, ctx("hub", false, false)), "woke", "standing up wakes you")
	eq(Rest.isResting(s), false, "…and you are not resting")
end

--================================================================ idle

do
	local s = Rest.new()
	for _ = 1, 199 do Rest.update(s, cfg, 0.1, ctx("hub", false, false)) end
	eq(Rest.isResting(s), false, "19.9 s standing still: not yet")
	eq(Rest.update(s, cfg, 0.1, ctx("hub", false, false)), "started", "20 s standing still in the break room: resting")
	eq(s.source, "idle", "…idle")
	eq(Rest.update(s, cfg, 0.1, ctx("hub", false, true)), "woke", "moving wakes an idle rest")
	for _ = 1, 150 do Rest.update(s, cfg, 0.1, ctx("hub", false, false)) end
	Rest.update(s, cfg, 0.1, ctx("hub", false, true))
	for _ = 1, 150 do Rest.update(s, cfg, 0.1, ctx("hub", false, false)) end
	eq(Rest.isResting(s), false, "a step resets the idle count (15 s + a step + 15 s is not 20 s still)")
end
do
	local s = Rest.new()
	for _ = 1, 200 do Rest.update(s, cfg, 0.1, ctx("hub", false, false)) end
	eq(Rest.update(s, cfg, 0.1, ctx("hub", true, false)), nil, "idle, then sitting down: still resting, no new event")
	eq(s.source, "bench", "…now on the bench")
	eq(Rest.update(s, cfg, 0.1, ctx("hub", false, false)), "woke", "…and standing up ends it")
end
do
	local s = Rest.new()
	local off = { Phases = { hub = true }, IdleSeconds = 0 }
	for _ = 1, 36000 do Rest.update(s, off, 0.1, ctx("hub", false, false)) end
	eq(Rest.isResting(s), false, "IdleSeconds 0 switches idle rest off")
	eq(Rest.update(s, off, 0.1, ctx("hub", true)), "started", "…the bench still works")
end

--================================================================ never during a run

do
	local s = Rest.new()
	Rest.update(s, cfg, 0.1, ctx("hub", true))
	eq(Rest.update(s, cfg, 0.1, ctx("hub", true, false, true)), "woke", "stepping into the elevator car ends rest (boarding)")
	Rest.update(s, cfg, 0.1, ctx("hub", true))
	eq(Rest.update(s, cfg, 0.1, ctx("ride", true)), "woke", "the ride down ends rest, seated or not")
end
for _, phase in { "ride", "floor", "dying" } do
	local s = Rest.new()
	local started = 0
	for _ = 1, 3000 do
		if Rest.update(s, cfg, 0.1, ctx(phase, true, false)) == "started" then started += 1 end
		if Rest.update(s, cfg, 0.1, ctx(phase, false, false)) == "started" then started += 1 end
	end
	eq(started, 0, "no rest ever starts in '" .. phase .. "', seated or standing still for 10 minutes")
end
do -- property: whatever the sequence, a player is never resting outside the break room
	local seed = 12345
	local function rnd()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	local phases = { "hub", "hub", "hub", "ride", "floor", "dying" }
	local s = Rest.new()
	local bad, rested = 0, 0
	for _ = 1, 200000 do
		local c = ctx(phases[1 + math.floor(rnd() * #phases)], rnd() < 0.4, rnd() < 0.3, rnd() < 0.05)
		for _ = 1, 1 + math.floor(rnd() * 40) do
			Rest.update(s, cfg, 0.5, c)
			if Rest.isResting(s) then
				rested += 1
				if c.phase ~= "hub" or c.boarding then bad += 1 end
			end
		end
	end
	truthy(rested > 1000, "control: the random walk does rest a lot (" .. rested .. " rested steps)")
	eq(bad, 0, "…and never once outside the break room or in the car")
end

print(string.format("Rest: %d passed, %d failed", passed, failed))
