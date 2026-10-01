-- Spec for Rest. Run: luau tests/Rest.spec.luau
--
-- Copied from plus1-jump/tests/Rest.spec.luau (md5 4c38d41f...) with the module (md5 19226cb6...). Everything above
-- "SIGNAL LOST'S ADAPTATION" is the template's spec, unchanged but for this header, run against the adapted module
-- (which reads the template's ctx exactly as before when ctx.where is absent). Below it, DESIGN.md §6.
--
-- Spec for Rest: what "pausing" means in a world that cannot pause. Run: luau tests/Rest.spec.luau
--
-- A Roblox server cannot stop the world for one player, so rest is a STATE the player enters, with
-- rules that make it relaxing and make it useless as an exploit:
--   * you can rest by asking (manual) or by standing still long enough (idle, AFK-safe);
--   * you cannot START resting mid-air or while a threat is inbound — rest is not a panic button.
--     The request is queued and taken the moment it is safe, or dropped if you move first;
--   * any movement wakes you, so nothing that needs movement (earning progress) can happen at rest;
--   * the module reports whether hazard clocks may run; callers FREEZE them (see Hazards.spec),
--     they never reset them, so resting cannot thin out hazards.
-- Game-agnostic and pure.
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

local cfg = {
	IdleSeconds = 20,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.3,
	PendingSeconds = 8,
}

local STILL = { moving = false, grounded = true, threat = false }
local MOVING = { moving = true, grounded = true, threat = false }
local AIR = { moving = false, grounded = false, threat = false }
local THREAT = { moving = false, grounded = true, threat = true }

truthy((Rest.validate(cfg)), "a well-formed rest config validates")
do
	local bad = table.clone(cfg)
	bad.WakeOnMove = false
	local ok, err = Rest.validate(bad)
	eq(ok, false, "WakeOnMove=false is rejected: resting while moving would let a player climb in rest")
	truthy(type(err) == "string", "and says why")
end
do
	local bad = table.clone(cfg)
	bad.BlockWhileThreat = false
	eq((Rest.validate(bad)), false, "BlockWhileThreat=false is rejected: rest would become a panic button")
end
do
	local bad = table.clone(cfg)
	bad.IdleSeconds = -1
	eq((Rest.validate(bad)), false, "a negative IdleSeconds is rejected")
end

--================================================================ manual rest

do
	local s = Rest.new()
	eq(Rest.isResting(s), false, "a new player is not resting")
	eq(Rest.hazardsMayRun(s), true, "and hazards may run")
	eq(Rest.request(s, cfg, STILL), "resting", "asking to rest while standing on something with no threat: resting")
	eq(Rest.isResting(s), true, "is resting")
	eq(s.source, "manual", "manually")
	eq(Rest.hazardsMayRun(s), false, "hazards may not run while resting")
	eq(Rest.request(s, cfg, STILL), "already", "asking again is a no-op")
end
do
	local s = Rest.new()
	Rest.request(s, cfg, STILL)
	local events = 0
	for _ = 1, 3600 do
		if Rest.update(s, cfg, 1, STILL) ~= nil then events += 1 end
	end
	eq(events, 0, "an hour of rest, standing still, stays rest")
	eq(Rest.isResting(s), true, "still resting after an hour")
end

do
	local s = Rest.new()
	Rest.request(s, cfg, STILL)
	eq(Rest.update(s, cfg, 0.1, MOVING), nil, "movement inside the wake grace (sitting down wobble) does not wake")
	eq(Rest.update(s, cfg, 0.3, MOVING), "woke", "movement after the grace wakes the player")
	eq(Rest.isResting(s), false, "they are climbing again")
	eq(Rest.hazardsMayRun(s), true, "and hazards may run again")
end

do
	local s = Rest.new()
	Rest.request(s, cfg, STILL)
	Rest.update(s, cfg, 1, STILL)
	eq(Rest.update(s, cfg, 0.1, AIR), "woke", "leaving the ground (a jump, a push) ends rest immediately")
end

do
	local s = Rest.new()
	Rest.request(s, cfg, STILL)
	eq(Rest.stop(s), "stopped", "the rest button toggles it off")
	eq(Rest.isResting(s), false, "not resting")
	eq(Rest.stop(s), "idle", "stopping when not resting is harmless")
end

--================================================================ not a panic button

do
	local s = Rest.new()
	eq(Rest.request(s, cfg, THREAT), "queued", "asking to rest with a hazard inbound is QUEUED, not granted")
	eq(Rest.isResting(s), false, "so the hazard still arrives at an active player")
	eq(Rest.hazardsMayRun(s), true, "and hazards keep running")
	eq(Rest.update(s, cfg, 2, THREAT), nil, "still queued while the threat is live")
	eq(Rest.isResting(s), false, "still not resting")
	eq(Rest.update(s, cfg, 0.1, STILL), "started", "the moment the sky is clear, the queued rest starts")
	eq(Rest.isResting(s), true, "resting")
end

do
	local s = Rest.new()
	eq(Rest.request(s, cfg, AIR), "queued", "asking mid-jump is queued")
	eq(Rest.update(s, cfg, 0.5, { moving = true, grounded = true, threat = false }), "dropped",
		"landing and running on drops the queued request (they chose to keep climbing)")
	eq(Rest.isResting(s), false, "not resting")
	eq(s.pending, false, "nothing left queued")
end

-- The warning says MOVE. A player who presses Rest and then does exactly that must not lose the request
-- for obeying it (review 2026-09-17: walking off the lane silently cancelled the queued rest).
do
	local DODGING = { moving = true, grounded = true, threat = true }
	local s = Rest.new()
	eq(Rest.request(s, cfg, THREAT), "queued", "set-up: Rest pressed with a hazard inbound")
	local ev = nil
	for _ = 1, 30 do
		ev = Rest.update(s, cfg, 0.1, DODGING) or ev
	end
	eq(ev, nil, "walking off the lane while the hazard is still inbound keeps the request queued")
	eq(s.pending, true, "still queued after 3 s of dodging")
	eq(Rest.isResting(s), false, "and still not resting (rest never starts under a live threat)")
	eq(Rest.update(s, cfg, 0.1, STILL), "started", "the dodge done and the sky clear, standing still starts the rest")
end
do
	local s = Rest.new()
	Rest.request(s, cfg, THREAT)
	Rest.update(s, cfg, 2, { moving = true, grounded = true, threat = true })
	eq(Rest.update(s, cfg, 0.1, MOVING), nil,
		"the frame the sky clears, a player still letting go of the stick keeps the request (wake grace)")
	eq(Rest.update(s, cfg, cfg.WakeGraceSeconds, MOVING), "dropped",
		"walking on under a clear sky past the grace drops it (they chose to keep climbing)")
	eq(s.pending, false, "nothing left queued")
end

do
	local s = Rest.new()
	Rest.request(s, cfg, THREAT)
	local ev = nil
	for _ = 1, 100 do
		ev = Rest.update(s, cfg, 0.1, THREAT)
		if ev then break end
	end
	eq(ev, "expired", "a queued request that never becomes safe expires after PendingSeconds")
	eq(Rest.isResting(s), false, "and never turns into rest by itself later")
	eq(Rest.update(s, cfg, 0.1, STILL), nil, "an expired request does not come back when it gets quiet")
end

do
	local s = Rest.new()
	Rest.request(s, cfg, THREAT)
	eq(Rest.stop(s), "cancelled", "pressing the button again cancels a queued request")
	eq(Rest.update(s, cfg, 0.1, STILL), nil, "and it does not start later")
end

--================================================================ idle rest (AFK safety)

do
	local s = Rest.new()
	local startedAt = nil
	local t = 0
	for _ = 1, 400 do
		t += 0.1
		local ev = Rest.update(s, cfg, 0.1, STILL)
		if ev == "started" then startedAt = t; break end
	end
	truthy(startedAt ~= nil and math.abs(startedAt - cfg.IdleSeconds) < 0.11,
		"standing still for IdleSeconds rests automatically (" .. tostring(startedAt) .. ")")
	eq(s.source, "idle", "as idle rest")
	eq(Rest.update(s, cfg, 0.5, MOVING), "woke", "and moving wakes an idle rest too")
end

do
	local s = Rest.new()
	local started = false
	for i = 1, 1000 do
		local ctx = if i % 100 == 0 then MOVING else STILL -- a nudge every 10 s
		if Rest.update(s, cfg, 0.1, ctx) == "started" then started = true end
	end
	eq(started, false, "a player who moves every 10 s never idles into rest")
end

do
	local s = Rest.new()
	local started = false
	for _ = 1, 400 do
		if Rest.update(s, cfg, 0.1, THREAT) == "started" then started = true end
	end
	eq(started, false, "idle rest does not begin while a threat is inbound either")
	local ev
	for _ = 1, 5 do
		ev = Rest.update(s, cfg, 0.1, STILL)
		if ev then break end
	end
	eq(ev, nil, "the idle timer restarted when the threat appeared; it does not start the instant it clears")
end

do
	local s = Rest.new()
	local started = false
	for _ = 1, 400 do
		if Rest.update(s, cfg, 0.1, AIR) == "started" then started = true end
	end
	eq(started, false, "falling for 40 s is not idling")
end

do
	local noIdle = table.clone(cfg)
	noIdle.IdleSeconds = 0
	truthy((Rest.validate(noIdle)), "IdleSeconds = 0 disables idle rest")
	local s = Rest.new()
	local started = false
	for _ = 1, 10000 do
		if Rest.update(s, noIdle, 0.1, STILL) == "started" then started = true end
	end
	eq(started, false, "and then standing still never rests")
end

--================================================================ SIGNAL LOST'S ADAPTATION (DESIGN.md §6)
-- Rest is allowed wherever there is air (the lifeboat and air modules) and nowhere else. In vacuum a request is
-- REFUSED with a reason, never queued: you cannot rest without moving to air, and moving drops a queued request.
-- ctx.where = "hub" | "air" | "vacuum" | nil (nil: not in the world, a ride or a blackout: never allowed).
local SL = require("../src/shared/Config")
local RC = SL.Rest

do
	local ok, err = Rest.validateStation(RC)
	truthy(ok, "Config.Rest passes validateStation (" .. tostring(err) .. ")")
	local bad = table.clone(RC)
	bad.AllowedIn = { hub = true, air = true, vacuum = true }
	local okV, errV = Rest.validateStation(bad)
	eq(okV, false, "a config that allows rest in vacuum is refused")
	truthy(type(errV) == "string" and string.find(errV, "vacuum", 1, true) ~= nil, "saying why (" .. tostring(errV) .. ")")
	local typo = table.clone(RC)
	typo.AllowedIn = { hub = true, air = true, airlock = true }
	eq((Rest.validateStation(typo)), false, "an unknown place name is refused (a typo must not open a hole)")
	local none = table.clone(RC)
	none.AllowedIn = {}
	eq((Rest.validateStation(none)), false, "rest allowed nowhere is refused")
	local noThreat = table.clone(RC)
	noThreat.BlockWhileThreat = false
	eq((Rest.validateStation(noThreat)), false, "the template's rules still hold (BlockWhileThreat)")
end

local AIR_STILL = { moving = false, grounded = true, threat = false, where = "air" }
local HUB_STILL = { moving = false, grounded = true, threat = false, where = "hub" }
local VAC_STILL = { moving = false, grounded = true, threat = false, where = "vacuum" }

do
	local s = Rest.new()
	eq(Rest.request(s, RC, VAC_STILL), "refused", "asking to rest in vacuum is refused")
	eq(s.pending, false, "and NOT queued")
	eq(Rest.isResting(s), false, "not resting")
	eq(Rest.refusal(RC, "vacuum"), RC.Text.NoAir, "the reason: " .. RC.Text.NoAir)
	eq(Rest.request(s, RC, AIR_STILL), "resting", "in an air module: resting")
	eq(Rest.hazardsMayRun(s), false, "hazard clocks freeze while resting")
	Rest.stop(s)
	eq(Rest.request(s, RC, HUB_STILL), "resting", "in the lifeboat: resting")
	Rest.stop(s)
	eq(Rest.request(s, RC, { moving = false, grounded = true, threat = false, where = nil }), "refused", "outside the world (a ride, a blackout): refused")
end

do
	-- idle rest: 20 s standing still in air, never in vacuum
	local s = Rest.new()
	local started = nil
	local t = 0
	for _ = 1, 400 do
		t += 0.1
		if Rest.update(s, RC, 0.1, AIR_STILL) == "started" then started = t; break end
	end
	truthy(started ~= nil and math.abs(started - RC.IdleSeconds) < 0.11, "20 s standing still in air: idle rest (" .. tostring(started) .. ")")
	eq(s.source, "idle", "from idle")
	local v = Rest.new()
	local any = false
	for _ = 1, 600 do
		if Rest.update(v, RC, 0.1, VAC_STILL) ~= nil then any = true end
	end
	eq(any, false, "60 s standing still in vacuum: never an idle rest")
	eq(Rest.isResting(v), false, "not resting")
end

do
	-- resting in air, then the player is (somehow) in vacuum: woken at once
	local s = Rest.new()
	Rest.request(s, RC, AIR_STILL)
	eq(Rest.update(s, RC, 0.1, VAC_STILL), "woke", "a resting player found in vacuum wakes at once")
	-- movement wakes, after the wake grace
	Rest.request(s, RC, HUB_STILL)
	eq(Rest.update(s, RC, 0.2, { moving = true, grounded = true, threat = false, where = "hub" }), nil, "a wobble inside the 0.4 s grace does not wake")
	eq(Rest.update(s, RC, 0.3, { moving = true, grounded = true, threat = false, where = "hub" }), "woke", "movement after the grace wakes")
end

do
	-- a request queued in air (a threat that cannot really happen there, but the template's rule stands) is dropped
	-- the moment the player is in vacuum
	local s = Rest.new()
	eq(Rest.request(s, RC, { moving = false, grounded = false, threat = false, where = "air" }), "queued", "mid-hop in air: queued")
	eq(Rest.update(s, RC, 0.1, { moving = false, grounded = true, threat = false, where = "vacuum" }), "dropped", "landing in vacuum drops it")
	eq(s.pending, false, "nothing pending")
end

do
	-- the exploit this must close: resting changes no number anything counts (hazards only freeze), and the
	-- template's measured rest-toggle result holds for Signal Lost's scheduler too (tests/Hazards.spec.luau)
	eq(Rest.PAUSES_AIR, false, "rest never pauses the air clock: AIR is the server's arithmetic")
	eq(RC.AllowedIn.vacuum, nil, "and it is never allowed where AIR drains")
end

print(string.format("Rest: %d passed, %d failed", passed, failed))
assert(failed == 0, "Rest tests failed")
