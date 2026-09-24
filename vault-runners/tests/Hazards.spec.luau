-- Spec for Hazards (vault edition): rare, telegraphed, one-at-a-time DROPS from the ceiling.
-- Run: luau tests/Hazards.spec.luau
--
-- Adapted from +1 Jump's template (plus1-jump/src/shared/Hazards.luau). The scheduler, the zone and
-- the knock are the template's rules; what changed is the flight. +1 Jump is open sky, so a hazard
-- flies a straight lane toward the player from wherever the camera looks. A vault storey is a
-- maze with a ceiling 16 studs up and walls on every side, and a lane would fly THROUGH the walls.
-- So a vault hazard is a chunk of ceiling: it hangs above the player (the ring under their feet
-- follows them while the warning runs), LOCKS `commit` seconds before it lands, and drops.
--
-- The properties this file pins, and why each one matters to the owner's brief ("rare, easy to see
-- coming and avoid", "the time budget must not change"):
--   * rarity: one per IntervalMin..IntervalMax seconds of RUN time, never two at once;
--   * the clock only runs while the run runs (paused = the hub) and is FROZEN, never reset;
--   * a due hazard waits while the player is somewhere it must not land (the climb shaft, the hole
--     in the floor, the first seconds of a run) instead of being thrown away or fired late in a burst;
--   * the danger is exactly the ring: stepping out of it in ANY direction dodges, standing in it
--     does not; a player on another storey is never hit by a chunk falling on this one;
--   * the knock is capped: it can push a player a few studs, never lift them anywhere.
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

local cfg = {
	IntervalMin = 120,
	IntervalMax = 180,
	MinTelegraphSeconds = 2.5,
	MinCommitSeconds = 1.0,
	MaxTrackSpeed = 60,
	PlayerRadius = 1,
	KnockLift = 6,
	MaxKnock = 30,
	AimJitter = 0.8,
	Kinds = {
		slab = { telegraph = 3, commit = 1.2, fall = 0.35, pass = 1.5, hitRadius = 2.5, knock = 14, dropHeight = 13, reach = 6 },
		icicle = { telegraph = 3.4, commit = 1.4, fall = 0.3, pass = 1.5, hitRadius = 2.2, knock = 12, dropHeight = 13, reach = 6 },
	},
}

local function withKind(k: any): any
	local c = table.clone(cfg)
	c.Kinds = { only = k }
	return c
end
local GOOD = { telegraph = 3, commit = 1.2, fall = 0.35, pass = 1.5, hitRadius = 2.5, knock = 14, dropHeight = 13, reach = 6 }
local function kindWith(field: string, value: any): any
	local k = table.clone(GOOD)
	k[field] = value
	return k
end

--================================================================ validate

truthy((Hazards.validate(cfg)), "a well-formed drop config validates")
truthy((Hazards.validate(withKind(GOOD))), "and so does the single-kind control every rejection below is built from")
do
	local ok, err = Hazards.validate(withKind(kindWith("telegraph", 2)))
	eq(ok, false, "a drop with less warning than MinTelegraphSeconds is rejected (easy to see coming)")
	truthy(type(err) == "string" and string.find(err, "only") ~= nil and string.find(err, "telegraph") ~= nil,
		"and the error names the kind and the rule (" .. tostring(err) .. ")")
end
eq((Hazards.validate(withKind(kindWith("commit", 0.6)))), false,
	"a drop that locks less than MinCommitSeconds before it lands is rejected (no time to step out)")
eq((Hazards.validate(withKind(kindWith("commit", 3.5)))), false, "a commit longer than the telegraph is rejected")
eq((Hazards.validate(withKind(kindWith("fall", 1.3)))), false,
	"a fall that starts before the lock is rejected (the chunk would drop while the ring still follows the player)")
eq((Hazards.validate(withKind(kindWith("fall", 0)))), false, "a zero-length fall is rejected")
eq((Hazards.validate(withKind(kindWith("hitRadius", 0)))), false, "a zero hit radius is rejected")
eq((Hazards.validate(withKind(kindWith("dropHeight", 0)))), false, "a drop from zero height is rejected")
eq((Hazards.validate(withKind(kindWith("reach", nil)))), false,
	"a kind with no vertical reach is rejected (it would hit a player on the storey above or below)")
eq((Hazards.validate(withKind(kindWith("knock", 45)))), false, "a knock harder than MaxKnock is rejected")
do
	local bad = table.clone(cfg)
	bad.KnockLift = 40
	local ok, err = Hazards.validate(bad)
	eq(ok, false, "a knock that lifts more than MAX_KNOCK_LIFT is rejected")
	truthy(type(err) == "string" and string.find(err, "KnockLift") ~= nil, "for that reason (" .. tostring(err) .. ")")
end
do
	local bad = table.clone(cfg)
	bad.IntervalMin = 0
	eq((Hazards.validate(bad)), false, "a zero interval (hazard spam) is rejected")
	bad.IntervalMin = 200
	eq((Hazards.validate(bad)), false, "IntervalMax below IntervalMin is rejected")
end
do
	local bad = table.clone(cfg)
	bad.PlayerRadius = nil
	eq((Hazards.validate(bad)), false, "a config without PlayerRadius is rejected (the ring would not match the rule)")
	bad = table.clone(cfg)
	bad.MaxTrackSpeed = 0
	eq((Hazards.validate(bad)), false, "a zero MaxTrackSpeed is rejected")
end

--================================================================ rolls

do
	local r = lcg(1)
	local lo, hi = math.huge, -math.huge
	for _ = 1, 5000 do
		local v = Hazards.rollInterval(cfg, r)
		lo = math.min(lo, v); hi = math.max(hi, v)
	end
	truthy(lo >= cfg.IntervalMin and hi <= cfg.IntervalMax,
		string.format("every interval is inside %d..%d s (%.1f..%.1f)", cfg.IntervalMin, cfg.IntervalMax, lo, hi))
end

--================================================================ scheduling on RUN time

local AIM = { x = 0, y = 3, z = 0 }
local function runCtx(over: any?): any
	local c = { paused = false, eligible = true, kinds = { "slab", "icicle" }, aim = AIM }
	for k, v in over or {} do c[k] = v end
	return c
end

-- Measured rarity: 20 hours of uninterrupted, always-eligible run time in 0.1 s frames.
do
	local r = lcg(12345)
	local s = Hazards.newScheduler(cfg, r)
	local dt = 0.1
	local spawns, lastSpawn, minGap, maxGap, maxActive = 0, nil, math.huge, 0, 0
	local t = 0
	for _ = 1, 20 * 3600 * 10 do
		t += dt
		local ev = Hazards.step(s, cfg, dt, runCtx(), r)
		if ev and ev.type == "spawn" then
			spawns += 1
			if lastSpawn then
				minGap = math.min(minGap, t - lastSpawn); maxGap = math.max(maxGap, t - lastSpawn)
			end
			lastSpawn = t
		end
		maxActive = math.max(maxActive, if s.active then 1 else 0)
	end
	local perHour = spawns / 20
	print(string.format("  20 h of run time: %d drops = one per %.1f s; gaps %.1f..%.1f s", spawns, 72000 / spawns, minGap, maxGap))
	truthy(perHour >= 3600 / cfg.IntervalMax and perHour <= 3600 / cfg.IntervalMin,
		string.format("drops per hour of run time (%.1f) sit between %d and %d", perHour, 3600 // cfg.IntervalMax, 3600 // cfg.IntervalMin))
	truthy(minGap >= cfg.IntervalMin - 0.11, "no two drops closer than IntervalMin (" .. minGap .. ")")
	truthy(maxGap <= cfg.IntervalMax + 0.11, "and never longer apart than IntervalMax while eligible (" .. maxGap .. ")")
	eq(maxActive, 1, "never more than one drop at a time")
end

-- Pausing (the hub, between runs) FREEZES the clock and never resets it.
do
	local function firstSpawnAt(pauseAt: number?, pauseFor: number): number
		local r = lcg(777)
		local s = Hazards.newScheduler(cfg, r)
		local runT, wall, dt = 0, 0, 0.1
		while wall < 5000 do
			wall += dt
			local paused = pauseAt ~= nil and runT >= pauseAt and wall < pauseAt + pauseFor
			local ev = Hazards.step(s, cfg, dt, runCtx({ paused = paused }), r)
			if not paused then runT += dt end
			if ev and ev.type == "spawn" then return runT end
		end
		return -1
	end
	local plain = firstSpawnAt(nil, 0)
	local rested = firstSpawnAt(40, 1000)
	approx(rested, plain, "a 1000 s pause after 40 s of run time moves the first drop by zero run-seconds", 0.11)
	truthy(plain >= cfg.IntervalMin and plain <= cfg.IntervalMax, "the first drop lands inside the interval (" .. plain .. ")")
end

-- Paused: no launch even when due. Due while ineligible: HELD (not re-rolled, not skipped) and
-- launched on the first eligible frame.
do
	local r = lcg(9)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt + 5 -- overdue
	local due = s.nextAt
	eq(Hazards.step(s, cfg, 0.1, runCtx({ paused = true }), r), nil, "a due drop never launches while paused")
	eq(s.active, nil, "(nothing in the air)")
	eq(Hazards.step(s, cfg, 0.1, runCtx({ eligible = false }), r), nil, "nor while the player is somewhere it must not land")
	eq(s.nextAt, due, "and waiting does not re-roll it (the player cannot shop for a quiet spot)")
	local ev = Hazards.step(s, cfg, 0.1, runCtx(), r)
	eq(ev and ev.type, "spawn", "it launches on the first eligible frame")
	truthy(s.nextAt >= s.clock + cfg.IntervalMin - 1e-9, "and the next one is a full interval away, not a backlog")
end
do
	local r = lcg(10)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt + 1
	local noAim = runCtx()
	noAim.aim = nil -- (a nil in a table literal is no key at all, so it is cleared here)
	local ev = Hazards.step(s, cfg, 0.1, noAim, r)
	eq(ev, nil, "no aim (no character) holds a due drop too")
end

-- A quiet band (no kinds) re-rolls instead of holding, so the first loud frame is not a burst.
do
	local r = lcg(11)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt + 1
	local ev = Hazards.step(s, cfg, 0.1, runCtx({ kinds = {} }), r)
	eq(ev and ev.type, "skip", "a due drop with no kinds to launch is skipped")
	truthy(s.nextAt > s.clock, "and re-rolled into the future")
end

--================================================================ the plan: hang, lock, drop

do
	local r = lcg(21)
	local p = Hazards.plan(cfg, "slab", { x = 10, y = 3, z = -4 }, r)
	local k = cfg.Kinds.slab
	eq(p.kind, "slab", "the plan names its kind")
	approx(p.arriveAt, k.telegraph, "it lands `telegraph` seconds after launch")
	approx(p.commitAt, k.telegraph - k.commit, "it locks `commit` seconds before that")
	approx(p.fallAt, k.telegraph - k.fall, "and only starts falling `fall` seconds before landing")
	approx(p.duration, k.telegraph + k.pass, "and is done `pass` seconds after landing")
	approx(p.target.y, 3, "the landing height is the aim's height (the player's root)")
	local jx, jz = p.target.x - 10, p.target.z + 4
	truthy(math.sqrt(jx * jx + jz * jz) <= cfg.AimJitter + 1e-9, "the landing point is within AimJitter of the aim")
	local hang = Hazards.positionAt(p, 0)
	approx(hang.y, p.target.y + k.dropHeight, "it starts dropHeight above the landing point")
	approx(Hazards.positionAt(p, p.fallAt - 0.01).y, hang.y, "and HANGS there (shaking is the art's business) until the fall")
	approx(Hazards.positionAt(p, p.arriveAt).y, p.target.y, "it reaches the landing point exactly at arriveAt", 1e-6)
	approx(Hazards.positionAt(p, p.duration).y, p.target.y, "and stays down afterwards (debris on the floor)")
	local prev, mono = math.huge, true
	for i = 0, 100 do
		local y = Hazards.positionAt(p, p.fallAt + (p.arriveAt - p.fallAt) * i / 100).y
		if y > prev + 1e-9 then mono = false end
		prev = y
	end
	truthy(mono, "the fall only ever goes down")
	local a = Hazards.positionAt(p, p.fallAt + 0.05)
	approx(a.x, p.target.x, "it falls straight down (x)")
	approx(a.z, p.target.z, "it falls straight down (z)")
end

--================================================================ tracking, and the lock

do
	local r = lcg(31)
	local p = Hazards.plan(cfg, "slab", { x = 0, y = 3, z = 0 }, r)
	local arrive = p.arriveAt
	local dt = 1 / 30
	-- walk the aim along +x at WalkSpeed-ish 20 studs/s while the warning runs
	local x = 0
	while p.t + dt < p.commitAt do
		p.t += dt
		x += 20 * dt
		Hazards.retarget(cfg, p, { x = x, y = 3, z = 0 }, dt)
	end
	local z = Hazards.zone(p, cfg.PlayerRadius)
	approx(z.x, x, "while the warning runs the ring follows the player (x)", 1e-6)
	approx(z.z, 0, "while the warning runs the ring follows the player (z)", 1e-6)
	eq(p.locked, false, "and it has not locked yet")
	p.t = p.commitAt
	eq(Hazards.retarget(cfg, p, { x = x + 5, y = 3, z = 0 }, dt), false, "at commitAt it refuses to follow")
	eq(p.locked, true, "and is locked")
	local lockedAt = Hazards.zone(p, cfg.PlayerRadius)
	Hazards.retarget(cfg, p, { x = x + 30, y = 3, z = 9 }, dt)
	approx(Hazards.zone(p, cfg.PlayerRadius).x, lockedAt.x, "a locked ring never moves again")
	approx(p.arriveAt, arrive, "and the landing time never moved (the warning never shortens)")
end
do
	local r = lcg(32)
	local p = Hazards.plan(cfg, "slab", { x = 0, y = 3, z = 0 }, r)
	p.t = 0.5
	eq(Hazards.retarget(cfg, p, nil, 1 / 30), false, "no aim (the player went somewhere it must not land) locks it")
	eq(p.locked, true, "locked")
	local r2 = lcg(33)
	local q = Hazards.plan(cfg, "slab", { x = 0, y = 3, z = 0 }, r2)
	q.t = 0.5
	eq(Hazards.retarget(cfg, q, { x = 40, y = 3, z = 0 }, 1 / 30), false,
		"a jump faster than MaxTrackSpeed (a teleport, a fall down the shaft) locks it where it was")
	approx(Hazards.zone(q, cfg.PlayerRadius).x, 0, "and leaves it where it was", 1e-9)
end

--================================================================ the zone IS the rule

do
	local r = lcg(41)
	local p = Hazards.plan(cfg, "slab", { x = 5, y = 3, z = 5 }, r)
	local z = Hazards.zone(p, cfg.PlayerRadius)
	approx(z.x, 5, "the ring is centred where the player stood, not on the jittered landing point (x)")
	approx(z.z, 5, "(z)")
	approx(z.radius, cfg.Kinds.slab.hitRadius + cfg.PlayerRadius, "and its radius is hitRadius + PlayerRadius")
	truthy(Hazards.inZone(p, { x = 5, y = 3, z = 5 }, cfg.PlayerRadius), "the centre is inside")
	eq(Hazards.inZone(p, { x = 5 + z.radius + 0.01, y = 3, z = 5 }, cfg.PlayerRadius), false, "just past the rim is outside")
end

-- The whole telegraph, frame by frame: a player who does nothing is hit exactly once, at the landing.
local function flight(kind: string, seed: number, walk: ((t: number, dt: number, p: any) -> any)?): (boolean, number, any)
	local r = lcg(seed)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt
	local pos = { x = 0, y = 3, z = 0 }
	local dt = 1 / 30
	local hits, lastPlan = 0, nil
	Hazards.step(s, cfg, dt, { paused = false, eligible = true, kinds = { kind }, aim = pos }, r)
	local p = s.active
	lastPlan = p
	while s.active do
		local before = s.active.t
		if walk then pos = walk(s.active.t, dt, s.active) end
		Hazards.step(s, cfg, dt, { paused = false, eligible = true, kinds = { kind }, aim = pos }, r)
		local plan = s.active or p
		if Hazards.checkHit(plan, before, plan.t, pos, cfg.PlayerRadius) then
			plan.hit = true
			hits += 1
		end
		if s.active == nil then break end
	end
	return hits > 0, hits, lastPlan
end

do
	for _, kind in { "slab", "icicle" } do
		local hit, n = flight(kind, 51)
		eq(hit, true, kind .. ": a player who stays put is hit")
		eq(n, 1, kind .. ": exactly once")
	end
	-- walk out of the ring after the lock, in every 10-degree direction, at a stroll (12 studs/s)
	local dodged, total = 0, 0
	for _, kind in { "slab", "icicle" } do
		for deg = 0, 350, 10 do
			total += 1
			local a = math.rad(deg)
			local lockPos = nil
			local hit = flight(kind, 60 + deg, function(t, dt, plan)
				if t < plan.commitAt then
					return { x = 0, y = 3, z = 0 }
				end
				lockPos = lockPos or { x = 0, y = 3, z = 0 }
				local w = (t - plan.commitAt) * 12
				return { x = lockPos.x + math.cos(a) * w, y = 3, z = lockPos.z + math.sin(a) * w }
			end)
			if not hit then dodged += 1 end
		end
	end
	eq(dodged, total, string.format("stepping out of the ring after the lock dodges in EVERY direction (%d of %d)", dodged, total))
	-- a player who keeps running the whole time is never under it when it lands
	local runner = flight("slab", 99, function(t) return { x = 20 * t, y = 3, z = 0 } end)
	eq(runner, false, "a runner who never stops is never hit (the ring stops following at the lock)")
	-- a player standing in the ring but on the storey ABOVE (on a pad, climbing) is not hit
	local above = flight("slab", 98, function(t, dt, plan)
		if t < plan.commitAt then return { x = 0, y = 3, z = 0 } end
		return { x = 0, y = 3 + 18, z = 0 }
	end)
	eq(above, false, "a chunk landing on this storey never hits a player a storey above it")
end

do
	local r = lcg(71)
	local p = Hazards.plan(cfg, "slab", { x = 0, y = 3, z = 0 }, r)
	eq(Hazards.checkHit(p, 0, p.arriveAt - 0.05, { x = 0, y = 3, z = 0 }, cfg.PlayerRadius), false,
		"nothing hits before the chunk lands")
	eq(Hazards.checkHit(p, p.arriveAt + 0.01, p.arriveAt + 0.5, { x = 0, y = 3, z = 0 }, cfg.PlayerRadius), false,
		"and walking into the ring AFTER it landed is harmless (debris on the floor)")
	truthy(Hazards.checkHit(p, p.arriveAt - 0.02, p.arriveAt + 0.02, { x = 0, y = 3, z = 0 }, cfg.PlayerRadius),
		"the frame that contains the landing is the hit")
	p.hit = true
	eq(Hazards.checkHit(p, p.arriveAt - 0.02, p.arriveAt + 0.02, { x = 0, y = 3, z = 0 }, cfg.PlayerRadius), false,
		"a drop hits once")
end

--================================================================ step: spawn, done, cancel

do
	local r = lcg(81)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt
	local ev = Hazards.step(s, cfg, 0.1, runCtx(), r)
	eq(ev and ev.type, "spawn", "a due, eligible, unpaused frame spawns")
	eq(s.spawned, 1, "and counts it")
	local plan = s.active
	local last
	for _ = 1, 100 do
		last = Hazards.step(s, cfg, 0.1, runCtx(), r)
		if last then break end
	end
	eq(last and last.type, "done", "it is done after its duration")
	eq(last and last.plan, plan, "and says which plan")
	s.clock = s.nextAt
	Hazards.step(s, cfg, 0.1, runCtx(), r)
	truthy(s.active ~= nil, "(another one in the air)")
	local clockBefore, nextBefore = s.clock, s.nextAt
	local gone = Hazards.cancel(s)
	truthy(gone ~= nil and s.active == nil, "cancel (the run ended) takes the drop out of the air")
	eq(s.clock, clockBefore, "without touching the clock")
	eq(s.nextAt, nextBefore, "or the next one")
	eq(Hazards.cancel(s), nil, "and cancelling nothing is a no-op")
end
do
	-- ineligible mid-warning: the ring stops where the player last was eligible
	local r = lcg(82)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt
	Hazards.step(s, cfg, 0.1, runCtx({ aim = { x = 0, y = 3, z = 0 } }), r)
	Hazards.step(s, cfg, 0.1, runCtx({ aim = { x = 2, y = 3, z = 0 } }), r)
	local at = Hazards.zone(s.active, cfg.PlayerRadius).x
	Hazards.step(s, cfg, 0.1, runCtx({ aim = { x = 4, y = 3, z = 0 }, eligible = false }), r)
	eq(s.active.locked, true, "a player who walks somewhere a drop must not land locks the drop behind them")
	approx(Hazards.zone(s.active, cfg.PlayerRadius).x, at, "at the last place they were eligible")
end

--================================================================ the knock

do
	local r = lcg(91)
	local p = Hazards.plan(cfg, "slab", { x = 0, y = 3, z = 0 }, r)
	local z = Hazards.zone(p, cfg.PlayerRadius)
	local kv = Hazards.knockVelocity(cfg, p, { x = z.x + 1, y = 3, z = z.z }, nil)
	approx(math.sqrt(kv.x * kv.x + kv.z * kv.z), cfg.Kinds.slab.knock, "the knock's horizontal speed is the kind's knock")
	truthy(kv.x > 0, "and pushes AWAY from where the chunk landed")
	truthy(kv.y <= Hazards.MAX_KNOCK_LIFT and kv.y == cfg.KnockLift, "the lift is KnockLift, never more than the cap")
	local centre = Hazards.knockVelocity(cfg, p, { x = z.x, y = 3, z = z.z }, { x = 0, y = 0, z = -1 })
	approx(centre.z, -cfg.Kinds.slab.knock, "dead centre uses the fallback direction (the way the player faces, reversed)")
	local none = Hazards.knockVelocity(cfg, p, { x = z.x, y = 3, z = z.z }, nil)
	approx(math.sqrt(none.x * none.x + none.z * none.z), cfg.Kinds.slab.knock, "and still pushes with no fallback given")
end

print(string.format("Hazards: %d passed, %d failed", passed, failed))
