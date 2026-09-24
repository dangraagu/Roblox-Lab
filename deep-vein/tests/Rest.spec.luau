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

--================================================================ Deep Vein: a minimum awake time between rests
--
-- Deep Vein's progress is CLICKING, not walking: a miner stands still and swings. The glue counts a
-- click as activity (it wakes a resting miner), so nobody mines while resting. What remained open was
-- the TOGGLE: swing, press Rest, swing, press Rest. Each swing wakes the miner and each press freezes
-- the hazard clock again, so the clock would only run in the slivers between a swing and the next
-- press, and hazards per swing would fall by the fraction of time spent "resting". Two rules close it:
--   * SettleSeconds: a rest starts only after the miner has been still (no step, no swing) that long;
--   * MinAwakeSeconds: after any rest ends, a new one cannot START until the miner has been awake that
--     long.
-- A request that cannot start yet is queued like an unsafe one, and a miner who keeps swinging drops it.

local awakeCfg = table.clone(cfg)
awakeCfg.MinAwakeSeconds = 6
awakeCfg.SettleSeconds = 1.5
awakeCfg.PendingSeconds = 10

truthy((Rest.validate(awakeCfg)), "a config with MinAwakeSeconds validates")
do
	local bad = table.clone(awakeCfg)
	bad.MinAwakeSeconds = -1
	eq((Rest.validate(bad)), false, "a negative MinAwakeSeconds is rejected")
	local bad2 = table.clone(awakeCfg)
	bad2.MinAwakeSeconds = "6"
	eq((Rest.validate(bad2)), false, "a non-numeric MinAwakeSeconds is rejected")
	local bad3 = table.clone(awakeCfg)
	bad3.SettleSeconds = -0.5
	eq((Rest.validate(bad3)), false, "a negative SettleSeconds is rejected")
	local bad4 = table.clone(awakeCfg)
	bad4.SettleSeconds = 12
	eq((Rest.validate(bad4)), false, "SettleSeconds >= PendingSeconds is rejected: every queued request would expire")
end

do
	local s = Rest.new()
	eq(Rest.request(s, awakeCfg, STILL), "resting", "a fresh miner who has not moved yet rests at once")
end

do
	-- settle: a swing a moment ago holds the request back until the miner has been still SettleSeconds
	local s = Rest.new()
	Rest.update(s, awakeCfg, 0.05, MOVING)
	eq(Rest.request(s, awakeCfg, STILL), "queued", "a rest asked for right after a swing is queued")
	local startedAt = nil
	for i = 1, 40 do
		if Rest.update(s, awakeCfg, 0.05, STILL) == "started" and startedAt == nil then startedAt = i * 0.05 end
	end
	truthy(startedAt ~= nil and math.abs(startedAt - 1.5) < 0.051,
		"…and starts after SettleSeconds of stillness (" .. tostring(startedAt) .. " s)")
end

do
	local s = Rest.new()
	Rest.update(s, awakeCfg, 0.05, MOVING)
	Rest.request(s, awakeCfg, STILL)
	for _ = 1, 10 do Rest.update(s, awakeCfg, 0.05, STILL) end
	eq(Rest.update(s, awakeCfg, 0.05, MOVING), "dropped", "a swing while the request waits drops it (the miner chose to mine)")
	eq(Rest.isResting(s), false, "…and they are not resting")
end

do
	local s = Rest.new()
	eq(Rest.request(s, awakeCfg, STILL), "resting", "a fresh miner can rest at once (nothing has woken them yet)")
	for _ = 1, 5 do Rest.update(s, awakeCfg, 0.1, STILL) end
	eq(Rest.update(s, awakeCfg, 0.1, MOVING), "woke", "activity wakes the miner")
	eq(Rest.request(s, awakeCfg, STILL), "queued", "a rest asked for right after waking is QUEUED, not started")
	eq(Rest.isResting(s), false, "…so the hazard clock runs")
	local startedAt = nil
	for i = 1, 70 do
		local ev = Rest.update(s, awakeCfg, 0.1, STILL)
		if ev == "started" and startedAt == nil then startedAt = i * 0.1 end
	end
	truthy(startedAt ~= nil and startedAt >= 6 - 1e-6 and startedAt <= 6.1 + 1e-6,
		"and it starts once the miner has been awake MinAwakeSeconds (" .. tostring(startedAt) .. " s)")
end

do
	local s = Rest.new()
	Rest.request(s, awakeCfg, STILL)
	eq(Rest.stop(s), "stopped", "pressing the button again stops the rest")
	eq(Rest.request(s, awakeCfg, STILL), "queued", "a stop counts as waking: the next rest waits MinAwakeSeconds too")
end

do
	local s = Rest.new()
	Rest.request(s, awakeCfg, STILL)
	Rest.update(s, awakeCfg, 0.5, MOVING)
	for _ = 1, 70 do Rest.update(s, awakeCfg, 0.1, STILL) end
	eq(Rest.request(s, awakeCfg, STILL), "resting", "after MinAwakeSeconds awake, a request starts at once")
end

do
	-- The toggler: swings every 0.5 s (a swing is one frame of activity) and presses Rest straight after
	-- every swing, for ten minutes. Without the minimum awake time they would be resting most of it.
	local function toggler(c)
		local s = Rest.new()
		local restingTime, t = 0, 0
		local dt = 0.05
		local nextSwing = 0
		while t < 600 do
			local swing = t >= nextSwing
			if swing then nextSwing = t + 0.5 end
			local ev = Rest.update(s, c, dt, if swing then MOVING else STILL)
			if swing and not Rest.isResting(s) then
				Rest.request(s, c, STILL)
			end
			if Rest.isResting(s) then restingTime += dt end
			t += dt
		end
		return restingTime
	end
	local without = table.clone(awakeCfg)
	without.MinAwakeSeconds = 0
	without.SettleSeconds = 0
	local exploited = toggler(without)
	local closed = toggler(awakeCfg)
	truthy(exploited > 300, "CONTROL: with neither rule a swing-and-rest toggler rests "
		.. string.format("%.0f", exploited) .. " of 600 s (the hole this closes)")
	eq(closed, 0, "with both rules a miner who keeps swinging never rests at all")
	local onlyAwake = table.clone(awakeCfg)
	onlyAwake.SettleSeconds = 0
	local leak = toggler(onlyAwake)
	truthy(leak > 0, "CONTROL: MinAwakeSeconds alone still lets a toggler rest between swings ("
		.. string.format("%.1f", leak) .. " s), which is why SettleSeconds exists")
end

print(string.format("Rest: %d passed, %d failed", passed, failed))
assert(failed == 0, "Rest tests failed")
