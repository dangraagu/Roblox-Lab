-- Spec for Hazards: rare, telegraphed, one-at-a-time ENVIRONMENTAL hazards. Run: luau tests/Hazards.spec.luau
--
-- Adapted from plus1-jump's template. What is kept: a clock that only runs while the player is exposed
-- to hazards (it FREEZES otherwise and is never reset), one hazard every IntervalMin..IntervalMax
-- seconds of that time, never two at once, and "the zone the client draws is exactly what hits".
-- What is different in FACILITY: nothing flies. A hazard comes down from the ceiling onto the spot the
-- player stood on when it started, so the danger zone is a fixed circle on one room's floor, and it only
-- ever starts on a legal spot: the room's interior, off the car/lift pad, in a LIT room. The dark is the
-- game's threat; a hazard never adds to it (a room that starts to flicker cancels its hazard).
-- Pure: vectors are { x, y, z } tables, randomness is injected, rooms are opaque ids.
local Hazards = require("../src/shared/Hazards")

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
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local function lcg(seed)
	local s = seed % 4294967296
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

-- The spec carries its own config so the rules are tested independently of the game's tuning
-- (tests/EnvConfig.spec.luau checks the real Config against the same rules).
local cfg = {
	IntervalMin = 120,
	IntervalMax = 180,
	MinTelegraphSeconds = 2.5,
	ReactionSeconds = 1.0,
	PlayerRadius = 1.5,
	EscapeSpeed = 10.4,
	SpotMinWallDistance = 6,
	PadKeepOut = 5.5,
	FixtureKeepOut = 2.5,
	ArrivalGraceSeconds = 6,
	Kinds = {
		leak = { telegraph = 3.0, burst = 0.5, hitRadius = 2.0, knock = 20, lift = 0 },
		arc = { telegraph = 2.8, burst = 0.4, hitRadius = 1.8, knock = 24, lift = 2 },
	},
}
local INNER = 13 -- a 28-stud cell with 1-stud walls

--================================================================ validate

truthy((Hazards.validate(cfg)), "a well-formed hazard config validates")
local function without(mut)
	local c = table.clone(cfg)
	c.Kinds = {}
	for k, v in cfg.Kinds do c.Kinds[k] = table.clone(v) end
	mut(c)
	return Hazards.validate(c)
end
eq((without(function(c) c.IntervalMax = 100 end)), false, "IntervalMax below IntervalMin is rejected")
eq((without(function(c) c.IntervalMin = 0 end)), false, "IntervalMin 0 is rejected (a hazard every frame)")
eq((without(function(c) c.Kinds.leak.telegraph = 2 end)), false, "a telegraph shorter than MinTelegraphSeconds is rejected")
do
	local ok, err = without(function(c) c.Kinds.leak.telegraph = 2.5; c.ReactionSeconds = 2.4 end)
	eq(ok, false, "a telegraph too short to react AND walk out of the zone at EscapeSpeed is rejected")
	truthy(type(err) == "string" and string.find(err, "escape") ~= nil, "…and says it cannot be escaped (" .. tostring(err) .. ")")
end
eq((without(function(c) c.Kinds.leak.hitRadius = 4.6 end)), false,
	"a zone that reaches SpotMinWallDistance is rejected: it could reach a wall and the doorway in it")
eq((without(function(c) c.Kinds.leak.knock = Hazards.MAX_KNOCK + 1 end)), false, "a knock above MAX_KNOCK is rejected")
eq((without(function(c) c.Kinds.leak.lift = Hazards.MAX_LIFT + 1 end)), false, "a lift above MAX_LIFT is rejected")
eq((without(function(c) c.Kinds.leak.burst = 0 end)), false, "a burst of 0 s is rejected (it could never hit, or never end)")
eq((without(function(c) c.Kinds.leak.hitRadius = 0 end)), false, "a hitRadius of 0 is rejected")
eq((without(function(c) c.Kinds = nil end)), false, "no Kinds is rejected")
eq((without(function(c) c.EscapeSpeed = 0 end)), false, "EscapeSpeed 0 is rejected")
eq((without(function(c) c.FixtureKeepOut = nil end)), false, "no FixtureKeepOut is rejected")
eq((without(function(c) c.ArrivalGraceSeconds = -1 end)), false, "a negative ArrivalGraceSeconds is rejected")
eq((without(function(c) c.ArrivalGraceSeconds = nil end)), false, "no ArrivalGraceSeconds is rejected")
truthy((without(function(c) c.ArrivalGraceSeconds = 0 end)), "ArrivalGraceSeconds 0 is allowed (no grace)")

--================================================================ arrival grace
-- The clock carries over between sublevels (frozen, never reset), so a hazard can be due while the player
-- stands on the powered lift's pad at the choice, where none may start. Without a grace it came the moment
-- they stepped off the next sublevel's car, over the arrival's THE POWER IS FAILING banner
-- (check_facilitynightmare_hazards E).
eq(Hazards.arrivalOk(cfg, 0), false, "no hazard the moment a player arrives on a sublevel")
eq(Hazards.arrivalOk(cfg, 5.9), false, "…nor 5.9 s in")
truthy(Hazards.arrivalOk(cfg, 6), "…from ArrivalGraceSeconds on, as usual")
truthy(Hazards.arrivalOk(cfg, 600), "…and for the rest of the sublevel")
eq(Hazards.arrivalOk(cfg, nil), false, "not on a sublevel at all (nil): no")

--================================================================ spots

truthy(Hazards.spotOk(cfg, INNER, 0, 6.9, false), "the interior of an ordinary room is a legal spot")
eq(Hazards.spotOk(cfg, INNER, 0, 0, false), false, "…but not under the light fixture in the middle of every room")
eq(Hazards.spotOk(cfg, INNER, 2.4, -1, false), false, "…anywhere under it")
truthy(Hazards.spotOk(cfg, INNER, 2.6, 0, false), "…just off the fixture it is")
eq(Hazards.spotOk(cfg, INNER, 0, 0, true), false, "the centre of a room holding the car or lift is not (its roof is in the way)")
eq(Hazards.spotOk(cfg, INNER, 5.4, 5.4, true), false, "…nor anywhere on that pad")
truthy(Hazards.spotOk(cfg, INNER, 6, 0, true), "…but off the pad it is")
eq(Hazards.spotOk(cfg, INNER, 7.1, 0, false), false, "closer than SpotMinWallDistance to a wall is not (a doorway is in every wall's middle)")
eq(Hazards.spotOk(cfg, INNER, 0, -7.1, false), false, "…on any side")
eq(Hazards.spotOk(cfg, INNER, 12, 12, false), false, "a corner is not")
do
	-- every legal spot's zone (the largest kind's) stays inside the room, at least a stud off every wall
	local worst = math.huge
	for _, k in cfg.Kinds do
		local r = k.hitRadius + cfg.PlayerRadius
		for x = -13, 13, 0.25 do
			for z = -13, 13, 0.25 do
				if Hazards.spotOk(cfg, INNER, x, z, false) then
					worst = math.min(worst, INNER - (math.max(math.abs(x), math.abs(z)) + r))
				end
			end
		end
	end
	truthy(worst >= 1 - 1e-9, "every legal zone keeps at least a stud off every wall (closest " .. worst .. ")")
end

--================================================================ plan, phases, zone, hit

do
	local p = Hazards.plan(cfg, "leak", { x = 10, y = 3, z = -4 }, "roomA")
	eq(p.kind, "leak", "a plan knows its kind")
	eq(p.room, "roomA", "…its room")
	approx(p.x, 10, "…is centred where the player stood (x)")
	approx(p.z, -4, "…(z)")
	approx(p.radius, 2.0 + 1.5, "…zone radius = hitRadius + PlayerRadius")
	approx(p.burstAt, 3.0, "…bursts when the telegraph ends")
	approx(p.endsAt, 3.5, "…and is over after the burst")
	eq(Hazards.phase(p, 0), "warn", "t 0: warning")
	eq(Hazards.phase(p, 2.99), "warn", "t 2.99: still warning")
	eq(Hazards.phase(p, 3.0), "burst", "t 3.0: burst")
	eq(Hazards.phase(p, 3.5), "after", "t 3.5: over")

	truthy(Hazards.inZone(p, { x = 10, y = 3, z = -4 }), "the player where they stood is in the zone")
	truthy(Hazards.inZone(p, { x = 13.49, y = 3, z = -4 }), "…3.49 studs off still is")
	eq(Hazards.inZone(p, { x = 13.51, y = 3, z = -4 }), false, "…3.51 studs off is not")
	truthy(Hazards.inZone(p, { x = 10, y = 40, z = -4 }), "height does not matter (it comes down on you, jumping or not)")

	eq(Hazards.checkHit(p, 0, 2.9, { x = 10, y = 3, z = -4 }, true), false, "no hit while it is only a warning")
	truthy(Hazards.checkHit(p, 2.9, 3.0, { x = 10, y = 3, z = -4 }, true), "a hit the frame it bursts, standing still")
	eq(Hazards.checkHit(p, 3.1, 3.2, { x = 10, y = 3, z = -4 }, false), false, "no hit on a player in another room")
	eq(Hazards.checkHit(p, 3.1, 3.2, { x = 14, y = 3, z = -4 }, true), false, "no hit outside the zone")
	eq(Hazards.checkHit(p, 3.6, 3.7, { x = 10, y = 3, z = -4 }, true), false, "no hit after the burst")
	p.hit = true
	eq(Hazards.checkHit(p, 3.1, 3.2, { x = 10, y = 3, z = -4 }, true), false, "a hazard hits once")
end

--================================================================ knock

do
	local p = Hazards.plan(cfg, "arc", { x = 0, y = 3, z = 0 }, 1)
	local v = Hazards.knockVelocity(cfg, p, { x = 2, y = 3, z = 0 }, { x = 0, y = 0, z = 1 })
	approx(v.x, 24, "the knock pushes away from the zone's centre at the kind's knock speed")
	approx(v.z, 0, "…horizontally")
	approx(v.y, 2, "…with the kind's small lift")
	local c = Hazards.knockVelocity(cfg, p, { x = 0.1, y = 3, z = 0 }, { x = 0, y = 0, z = -1 })
	approx(c.z, -24, "at the centre, the fallback direction (the caller passes 'backwards')")
	local z = Hazards.knockVelocity(cfg, p, { x = 0, y = 3, z = 0 }, { x = 0, y = 0, z = 0 })
	approx(math.sqrt(z.x * z.x + z.z * z.z), 24, "with no fallback either, some horizontal push of the right size")
	local huge = table.clone(p)
	huge.knock, huge.lift = 500, 500
	local h = Hazards.knockVelocity(cfg, huge, { x = 3, y = 3, z = 4 }, { x = 1, y = 0, z = 0 })
	truthy(math.sqrt(h.x * h.x + h.z * h.z) <= Hazards.MAX_KNOCK + 1e-9, "a knock is capped at MAX_KNOCK whatever the plan says")
	truthy(h.y <= Hazards.MAX_LIFT + 1e-9, "…and so is the lift")
end

--================================================================ the scheduler

local SPOT = { x = 0, y = 3, z = 0 }
local LIVE = { eligible = true, kinds = { "leak" }, spot = SPOT, room = 1, activeRoomLit = true }
local function stepN(s, seconds, ctx, rand, dt)
	dt = dt or 0.1
	local evs = {}
	for _ = 1, math.floor(seconds / dt + 0.5) do
		local e = Hazards.step(s, cfg, dt, ctx, rand)
		if e then table.insert(evs, e) end
	end
	return evs
end
local function count(evs, t)
	local n = 0
	for _, e in evs do if e.type == t then n += 1 end end
	return n
end

do
	local rand = lcg(7)
	local s = Hazards.newScheduler(cfg, rand)
	truthy(s.nextAt >= 120 and s.nextAt <= 180, "the first hazard is due 120-180 s in (" .. s.nextAt .. ")")
	local evs = stepN(s, 119.9, LIVE, rand)
	eq(count(evs, "spawn"), 0, "nothing in the first 120 s")
end

do -- the clock only runs while the player is exposed to hazards
	local rand = lcg(11)
	local s = Hazards.newScheduler(cfg, rand)
	for _, ctx in {
		{ eligible = false, kinds = { "leak" }, spot = SPOT, room = 1 }, -- the break room, the ride, a dark room, rest
		{ eligible = true, kinds = {}, spot = SPOT, room = 1 }, -- a quiet band
	} do
		stepN(s, 3600, ctx, rand)
	end
	approx(s.clock, 0, "an hour ineligible and an hour in a quiet band: the clock never moved")
	eq(s.spawned, 0, "…and nothing launched")
	local evs = stepN(s, s.nextAt - 0.05, LIVE, rand)
	eq(count(evs, "spawn"), 0, "…and the first hazard still needs its whole interval of exposed time afterwards")
	evs = stepN(s, 0.2, LIVE, rand)
	eq(count(evs, "spawn"), 1, "…then it comes")
end

do -- a due hazard waits for a legal spot and never piles up
	local rand = lcg(19)
	local s = Hazards.newScheduler(cfg, rand)
	local walking = { eligible = true, kinds = { "leak" }, spot = nil, room = 1, activeRoomLit = true }
	local evs = stepN(s, 900, walking, rand)
	eq(count(evs, "spawn"), 0, "15 min exposed but never on a legal spot: nothing launched")
	evs = stepN(s, 10, LIVE, rand)
	eq(count(evs, "spawn"), 1, "on a legal spot: exactly ONE launches (no backlog burst)")
	evs = stepN(s, 109, LIVE, rand) -- 10 s already spent above: 119 s after the launch in all
	eq(count(evs, "spawn"), 0, "…and the next needs a full IntervalMin of exposed time again")
end

do -- one at a time, intervals, long-run rate
	local rand = lcg(2026)
	local s = Hazards.newScheduler(cfg, rand)
	local spawns, lastAt, minGap, maxGap, maxActive = 0, nil, math.huge, 0, 0
	local hours = 20
	for _ = 1, hours * 36000 do
		local e = Hazards.step(s, cfg, 0.1, LIVE, rand)
		if e and e.type == "spawn" then
			spawns += 1
			if lastAt then
				minGap = math.min(minGap, s.clock - lastAt)
				maxGap = math.max(maxGap, s.clock - lastAt)
			end
			lastAt = s.clock
		end
		maxActive = math.max(maxActive, if s.active then 1 else 0)
	end
	local per = hours * 3600 / spawns
	print(string.format("    20 h exposed: %d hazards, one per %.1f s; gaps %.1f-%.1f s", spawns, per, minGap, maxGap))
	truthy(per >= 140 and per <= 160, "one hazard per 140-160 s of exposed time (" .. per .. ")")
	truthy(minGap >= 120 - 0.11 and maxGap <= 180 + 0.11, "every gap within 120-180 s")
	eq(maxActive, 1, "never two at once")
end

do -- one at a time is the scheduler's own rule, not a side effect of long intervals (resume session: the
	-- mutation that dropped the rule survived, because 120-180 s intervals never let two meet)
	local fast = table.clone(cfg)
	fast.IntervalMin, fast.IntervalMax = 0.5, 0.6
	local rand = lcg(5)
	local s = Hazards.newScheduler(fast, rand)
	local live, overlap, spawns = nil, 0, 0
	for _ = 1, 600 do
		local e = Hazards.step(s, fast, 0.1, LIVE, rand)
		if e and e.type == "spawn" then
			spawns += 1
			if live then overlap += 1 end
			live = e.plan
		elseif e and (e.type == "done" or e.type == "cancel") and e.plan == live then
			live = nil
		end
	end
	truthy(spawns >= 10, "control: with a 0.5 s interval hazards come back to back (" .. spawns .. " in 60 s)")
	eq(overlap, 0, "…and still none starts while another is live")
end

do -- freezing is not resetting: toggling exposure cannot thin hazards out
	local function perHour(onSeconds, offSeconds)
		local rand = lcg(99)
		local s = Hazards.newScheduler(cfg, rand)
		local exposed = 0
		local off = { eligible = false, kinds = { "leak" }, spot = SPOT, room = 1, activeRoomLit = true }
		while exposed < 6 * 3600 do
			stepN(s, onSeconds, LIVE, rand)
			exposed += onSeconds
			if offSeconds > 0 then stepN(s, offSeconds, off, rand) end
		end
		return s.spawned
	end
	local base = perHour(60, 0)
	local toggler = perHour(6, 6)
	local rider = perHour(40, 110)
	print(string.format("    6 h exposed: continuous %d, toggling every 6 s %d, 40 s of every 150 s %d", base, toggler, rider))
	eq(toggler, base, "walking in and out of a dark room every 6 s: the same hazards per exposed hour")
	eq(rider, base, "exposed 40 s of every 150 s: the same hazards per exposed hour")
end

--================================================================ cancel, burst, done

do
	local rand = lcg(3)
	local s = Hazards.newScheduler(cfg, rand)
	s.nextAt = 0
	local e = Hazards.step(s, cfg, 0.1, LIVE, rand)
	eq(e and e.type, "spawn", "due now on a legal spot: spawn")
	local plan = e.plan
	local saw = {}
	for _ = 1, 60 do
		local ev = Hazards.step(s, cfg, 0.1, LIVE, rand)
		if ev then saw[ev.type] = (saw[ev.type] or 0) + 1 end
	end
	eq(saw.burst, 1, "one burst event")
	eq(saw.done, 1, "one done event")
	eq(s.active, nil, "…and nothing active afterwards")
	truthy(plan.t >= plan.endsAt, "the plan ran to its end")

	s.nextAt = s.clock
	e = Hazards.step(s, cfg, 0.1, LIVE, rand)
	eq(e and e.type, "spawn", "a second one")
	local dying = { eligible = false, kinds = { "leak" }, spot = SPOT, room = 1, activeRoomLit = false }
	local c = Hazards.step(s, cfg, 0.1, dying, rand)
	eq(c and c.type, "cancel", "its room starts to flicker: the hazard is called off (the dark's warning outranks it)")
	eq(s.active, nil, "…and nothing is active")
end

--================================================================ escape: every direction, both speeds

do
	for _, speed in { 16, 10.4 } do
		local hits, tries = 0, 0
		for kindName in cfg.Kinds do
			for deg = 0, 350, 10 do
				local p = Hazards.plan(cfg, kindName, { x = 0, y = 3, z = 0 }, 1)
				local a = math.rad(deg)
				local pos = { x = 0, y = 3, z = 0 }
				local t = 0
				while t < p.endsAt + 0.2 do
					local t0 = t
					t += 1 / 30
					if t > cfg.ReactionSeconds then
						pos.x += math.cos(a) * speed / 30
						pos.z += math.sin(a) * speed / 30
					end
					if Hazards.checkHit(p, t0, t, pos, true) then p.hit = true end
				end
				tries += 1
				if p.hit then hits += 1 end
			end
		end
		eq(hits, 0, string.format("reacting after %.1f s and walking out at %.1f studs/s in any of 36 directions: 0 of %d hit",
			cfg.ReactionSeconds, speed, tries))
	end
	local stay = Hazards.plan(cfg, "leak", { x = 0, y = 3, z = 0 }, 1)
	local hitStay = false
	for i = 1, 150 do
		if Hazards.checkHit(stay, (i - 1) / 30, i / 30, { x = 0.3, y = 3, z = 0 }, true) then hitStay = true; stay.hit = true end
	end
	truthy(hitStay, "control: a player who stays put IS hit")
end

--================================================================ measured rarity against a model of play

-- A player in lit rooms with hazards (the only time the clock runs). The model is INVENTED, not
-- measured on people: it walks for 1-5 s at 16 studs/s inside the room, stands for 1-8 s, repeats.
-- "reacts" = on a warning while inside the zone, waits ReactionSeconds, walks straight out and watches it
-- come down from just outside the ring;
-- "ignores" = keeps doing whatever it was doing. A near-hit is a burst within 8 studs of the player.
local function play(hours, reacts, seed)
	local rand = lcg(seed)
	local s = Hazards.newScheduler(cfg, rand)
	local pos = { x = 0, y = 3, z = 0 }
	local mode, left, hx, hz = "stand", 3, 1, 0
	local stats = { spawns = 0, near = 0, hits = 0 }
	local fleeing = nil
	local dt = 0.1
	for _ = 1, math.floor(hours * 3600 / dt) do
		local legal = Hazards.spotOk(cfg, INNER, pos.x, pos.z, false)
		local ctx = { eligible = true, kinds = { "leak", "arc" }, spot = if legal then { x = pos.x, y = 3, z = pos.z } else nil,
			room = 1, activeRoomLit = true }
		local t0 = s.active and s.active.t or 0
		local e = Hazards.step(s, cfg, dt, ctx, rand)
		if e and e.type == "spawn" then
			stats.spawns += 1
			if reacts and Hazards.inZone(e.plan, pos) then fleeing = { wait = cfg.ReactionSeconds, plan = e.plan } end
		end
		local p = s.active or (e and e.type == "done" and e.plan) or nil
		if p then
			if e and e.type == "burst" then
				local dx, dz = pos.x - p.x, pos.z - p.z
				if dx * dx + dz * dz <= 64 then stats.near += 1 end
			end
			if Hazards.checkHit(p, t0, p.t, pos, true) then p.hit = true; stats.hits += 1 end
		end
		-- movement
		if fleeing then
			fleeing.wait -= dt
			if fleeing.wait <= 0 then
				local dx, dz = pos.x - fleeing.plan.x, pos.z - fleeing.plan.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < 1e-3 then dx, dz, d = 1, 0, 1 end
				if d <= fleeing.plan.radius + 0.5 then
					pos.x += dx / d * 16 * dt
					pos.z += dz / d * 16 * dt
				elseif Hazards.phase(fleeing.plan, fleeing.plan.t) == "after" or s.active ~= fleeing.plan then
					fleeing = nil
				end
			end
		else
			left -= dt
			if left <= 0 then
				if mode == "stand" then
					mode, left = "walk", 1 + 4 * rand()
					local a = rand() * math.pi * 2
					hx, hz = math.cos(a), math.sin(a)
				else
					mode, left = "stand", 1 + 7 * rand()
				end
			end
			if mode == "walk" then
				pos.x += hx * 16 * dt
				pos.z += hz * 16 * dt
				if math.abs(pos.x) > 11 then hx = -hx; pos.x = math.clamp(pos.x, -11, 11) end
				if math.abs(pos.z) > 11 then hz = -hz; pos.z = math.clamp(pos.z, -11, 11) end
			end
		end
	end
	local minutes = hours * 60
	return stats.spawns / minutes, stats.near / minutes, stats.hits / minutes, stats.hits / math.max(1, stats.spawns)
end
do
	local hz1, near1, hit1 = play(10, true, 41)
	local hz2, near2, hit2, share2 = play(10, false, 41)
	print(string.format("    model, reacts: %.3f hazards/min, %.3f near-hits/min (one per %.1f min), %.3f hits/min",
		hz1, near1, 1 / math.max(near1, 1e-9), hit1))
	print(string.format("    model, ignores: %.3f hazards/min, %.3f near-hits/min, %.3f hits/min (one per %.1f min), hit share %.2f",
		hz2, near2, hit2, 1 / math.max(hit2, 1e-9), share2))
	truthy(hz1 >= 1 / 3 - 0.02 and hz1 <= 1 / 2 + 0.02, "about one hazard per 2-3 exposed minutes (" .. hz1 .. "/min)")
	truthy(near1 >= 1 / 3 - 0.05 and near1 <= 1 / 2 + 0.02, "…and each one is a near-hit for a player who reacts (" .. near1 .. "/min)")
	eq(hit1, 0, "a player who reacts to the warning is never hit")
	truthy(hit2 > 0 and hit2 <= hz2, "a player who ignores every warning is hit sometimes, never more than once per hazard")
end

print(string.format("Hazards: %d passed, %d failed", passed, failed))
