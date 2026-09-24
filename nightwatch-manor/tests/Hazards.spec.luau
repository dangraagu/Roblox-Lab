-- Spec for Hazards: a rare, telegraphed, rate-limited, one-at-a-time hazard scheduler.
-- Run: luau tests/Hazards.spec.luau
--
-- Game-agnostic. It schedules on CLIMBING time (a clock that stops while the player rests), plans
-- a straight flight lane aimed at where the player stands, and answers "did it hit?" with a swept
-- test so a fast hazard cannot tunnel through the player between two frames. Vectors are plain
-- { x, y, z } tables and randomness is an injected function, so every rule below runs in the CLI.
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

-- A small deterministic generator for the spec (the module never cares where randomness comes from).
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
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	KnockLift = 10,
	SpreadDegrees = 35,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	AimJitter = 1.2,
	Kinds = {
		bird = { speed = 40, telegraph = 3, commit = 1.5, pass = 3, hitRadius = 2, knock = 45, pitch = 0, pitchSpread = 8 },
		balloon = { speed = 18, telegraph = 3.5, commit = 2, pass = 4, hitRadius = 2.4, knock = 30, pitch = -50, pitchSpread = 10 },
		jet = { speed = 110, telegraph = 3, commit = 1.6, pass = 2, hitRadius = 2.2, knock = 60, pitch = 5, pitchSpread = 5 },
	},
}

--================================================================ validate

truthy((Hazards.validate(cfg)), "a well-formed hazard config validates")
do
	local bad = table.clone(cfg)
	bad.IntervalMax = 100
	eq((Hazards.validate(bad)), false, "IntervalMax below IntervalMin is rejected")
end
do
	local bad = table.clone(cfg)
	-- otherwise valid (commit fits), ONLY the warning is too short
	bad.Kinds = { quick = { speed = 40, telegraph = 2, commit = 1.5, pass = 2, hitRadius = 2, knock = 40, pitch = 0 } }
	local ok, err = Hazards.validate(bad)
	eq(ok, false, "a kind with less warning than MinTelegraphSeconds is rejected (must be easy to see coming)")
	truthy(type(err) == "string" and string.find(err, "quick") ~= nil, "and the error names the kind")
	truthy(type(err) == "string" and string.find(err, "telegraph") ~= nil, "and says it is the telegraph (" .. tostring(err) .. ")")
end
do
	local bad = table.clone(cfg)
	bad.Kinds = { lift = { speed = 40, telegraph = 3, commit = 1.5, pass = 2, hitRadius = 2, knock = 40, pitch = 0 } }
	bad.KnockLift = 50
	local ok, err = Hazards.validate(bad)
	eq(ok, false, "a knock that lifts the player more than MaxKnockLift is rejected")
	truthy(type(err) == "string" and string.find(err, "KnockLift") ~= nil, "for that reason (" .. tostring(err) .. ")")
	bad.KnockLift = 10
	truthy((Hazards.validate(bad)), "and the same kind with a small lift is accepted (the rejection above was the lift)")
end
do
	local bad = table.clone(cfg)
	bad.IntervalMin = 0
	eq((Hazards.validate(bad)), false, "a zero interval (hazard spam) is rejected")
end
do
	local bad = table.clone(cfg)
	bad.Kinds = { late = { speed = 40, telegraph = 3, commit = 0.5, pass = 2, hitRadius = 2, knock = 40, pitch = 0 } }
	eq((Hazards.validate(bad)), false,
		"a lane that locks less than MinCommitSeconds before arrival is rejected (no time to step aside)")
end
do
	local bad = table.clone(cfg)
	bad.Kinds = { early = { speed = 40, telegraph = 3, commit = 4, pass = 2, hitRadius = 2, knock = 40, pitch = 0 } }
	eq((Hazards.validate(bad)), false, "a commit longer than the telegraph is rejected")
end

do
	-- review 2026-09-17: the lane must START on screen, not only toward the camera's heading
	local bad = table.clone(cfg)
	bad.ViewPitchDegrees = nil
	local ok, err = Hazards.validate(bad)
	eq(ok, false, "a config without ViewPitchDegrees is rejected (a hazard could start above or below the screen)")
	truthy(type(err) == "string" and string.find(err, "ViewPitchDegrees") ~= nil, "for that reason (" .. tostring(err) .. ")")
	bad.ViewPitchDegrees = 40
	eq((Hazards.validate(bad)), false, "a ViewPitchDegrees wider than Roblox's vertical half-FOV minus a margin (30) is rejected")
	bad.ViewPitchDegrees = 20
	bad.SpreadDegrees = 50
	eq((Hazards.validate(bad)), false, "a SpreadDegrees past a 4:3 tablet's horizontal half-FOV minus a margin (40) is rejected")
	bad.SpreadDegrees = 35
	truthy((Hazards.validate(bad)), "and the same config inside both limits is accepted")
end

--================================================================ rolls

do
	local r = lcg(1)
	local lo, hi = math.huge, -math.huge
	for _ = 1, 5000 do
		local v = Hazards.rollInterval(cfg, r)
		if v < lo then lo = v end
		if v > hi then hi = v end
	end
	truthy(lo >= cfg.IntervalMin, "an interval is never shorter than IntervalMin (" .. lo .. ")")
	truthy(hi <= cfg.IntervalMax, "and never longer than IntervalMax (" .. hi .. ")")
end

--================================================================ scheduling on climbing time

local function climbingCtx(kinds)
	return { resting = false, grounded = true, kinds = kinds or { "bird", "jet" }, aim = { x = 0, y = 50, z = 0 }, yaw = 0 }
end

-- Measured rarity: 20 hours of uninterrupted climbing in 0.1 s frames.
do
	local r = lcg(12345)
	local s = Hazards.newScheduler(cfg, r)
	local dt = 0.1
	local spawns, lastSpawn = 0, nil
	local minGap, maxGap = math.huge, 0
	local maxActive, t = 0, 0
	local telegraphOk = true
	local HOURS = 20
	for _ = 1, math.floor(HOURS * 3600 / dt) do
		t += dt
		local ev = Hazards.step(s, cfg, dt, climbingCtx(), r)
		if ev and ev.type == "spawn" then
			spawns += 1
			if lastSpawn then
				local gap = t - lastSpawn
				if gap < minGap then minGap = gap end
				if gap > maxGap then maxGap = gap end
			end
			lastSpawn = t
			if ev.plan.arriveAt < cfg.MinTelegraphSeconds then telegraphOk = false end
		end
		local active = if s.active then 1 else 0
		if active > maxActive then maxActive = active end
	end
	local perMinute = spawns / (HOURS * 60)
	print(string.format("  measured: %d hazards in %d h climbing = one per %.1f s (%.3f/min); gaps %.1f..%.1f s",
		spawns, HOURS, HOURS * 3600 / spawns, perMinute, minGap, maxGap))
	truthy(perMinute >= 1 / 3 and perMinute <= 1 / 2,
		"about one hazard per 2-3 minutes of climbing (" .. string.format("%.3f", perMinute) .. "/min)")
	truthy(minGap >= cfg.IntervalMin - 1e-6, "never two hazards closer than IntervalMin (" .. minGap .. ")")
	truthy(maxGap <= cfg.IntervalMax + dt + 1e-6, "never a gap longer than IntervalMax (" .. maxGap .. ")")
	eq(maxActive, 1, "at most ONE hazard in the air at any time")
	truthy(telegraphOk, "every hazard is telegraphed for at least MinTelegraphSeconds")
end

do
	local s = Hazards.newScheduler(cfg, lcg(7))
	truthy(s.nextAt >= cfg.IntervalMin, "the first hazard of a session is at least IntervalMin in (" .. s.nextAt .. ")")
end

-- No hazards in a band that has none, and entering a hazard band does not release a burst.
do
	local r = lcg(99)
	local s = Hazards.newScheduler(cfg, r)
	local spawnsInQuiet = 0
	for _ = 1, 36000 do -- one hour of quiet band
		local ev = Hazards.step(s, cfg, 0.1, climbingCtx({}), r)
		if ev and ev.type == "spawn" then spawnsInQuiet += 1 end
	end
	eq(spawnsInQuiet, 0, "a band with no hazard kinds never spawns one")
	truthy(s.nextAt > s.clock,
		"a due hazard in a quiet band is re-rolled into the future, not held due (" .. s.nextAt .. " > " .. s.clock .. ")")
	-- step into a hazard band: nothing may fire in the first IntervalMin... unless the roll was due.
	local firstAt = nil
	local t = 0
	for _ = 1, 3000 do
		t += 0.1
		local ev = Hazards.step(s, cfg, 0.1, climbingCtx(), r)
		if ev and ev.type == "spawn" then firstAt = t; break end
	end
	truthy(firstAt == nil or firstAt > 0.1 + 1e-9,
		"entering a hazard band does not fire a hazard on the very first frame (backlog burst)")
end

-- Airborne: a due hazard waits for the player to land rather than aiming at a mid-air point.
do
	local r = lcg(3)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt - 0.05
	local ctx = climbingCtx()
	ctx.grounded = false
	local ev = Hazards.step(s, cfg, 0.1, ctx, r)
	eq(ev, nil, "no hazard is launched at an airborne player")
	eq(s.active, nil, "and nothing is in flight")
	ctx.grounded = true
	ev = Hazards.step(s, cfg, 0.1, ctx, r)
	eq(ev and ev.type, "spawn", "it launches on the first grounded frame")
end

--================================================================ rest freezes the clock

do
	local r = lcg(55)
	local s = Hazards.newScheduler(cfg, r)
	local before = s.clock
	local ctx = climbingCtx()
	ctx.resting = true
	local spawns = 0
	for _ = 1, 36000 do -- an hour resting
		local ev = Hazards.step(s, cfg, 0.1, ctx, r)
		if ev and ev.type == "spawn" then spawns += 1 end
	end
	eq(spawns, 0, "a resting player gets no hazards for an hour")
	eq(s.clock, before, "and the hazard clock did not move: rest FREEZES it")
end

-- The exploit this must close: toggling rest must not thin out hazards per minute of climbing.
do
	local function run(restPattern)
		local r = lcg(2024)
		local s = Hazards.newScheduler(cfg, r)
		local climbed, spawns, wall = 0, 0, 0
		local dt = 0.1
		while climbed < 6 * 3600 do
			wall += dt
			local resting = restPattern(wall)
			local ctx = climbingCtx()
			ctx.resting = resting
			local ev = Hazards.step(s, cfg, dt, ctx, r)
			if ev and ev.type == "spawn" then spawns += 1 end
			if not resting then climbed += dt end
		end
		return spawns, wall
	end
	local never, wallNever = run(function() return false end)
	local toggler, wallToggler = run(function(t) return (math.floor(t / 7) % 2) == 1 end)
	local justBefore = run(function(t) return (t % 150) > 110 end)
	print(string.format("  rest-toggle exploit probe: never rests %d, toggles every 7 s %d, rests 40 s of every 150 s %d (same 6 h of climbing; wall %.0f vs %.0f s)",
		never, toggler, justBefore, wallNever, wallToggler))
	eq(toggler, never, "toggling rest every 7 s yields EXACTLY the hazards per climbing-hour of never resting")
	eq(justBefore, never, "resting in a fixed rhythm yields exactly the same count too")
end

-- The edge where a hazard is already DUE while the player is airborne, and they land straight into
-- a rest (a queued rest request resolves on landing): it must not launch at the resting player.
do
	local r = lcg(21)
	local s = Hazards.newScheduler(cfg, r)
	local ctx = climbingCtx()
	ctx.grounded = false
	s.clock = s.nextAt + 5 -- due, but waiting for the player to land
	Hazards.step(s, cfg, 0.1, ctx, r)
	eq(s.active, nil, "set-up: due, airborne, nothing launched")
	ctx.grounded = true
	ctx.resting = true
	local spawned = false
	for _ = 1, 600 do
		local ev = Hazards.step(s, cfg, 0.1, ctx, r)
		if ev and ev.type == "spawn" then spawned = true end
	end
	eq(spawned, false, "a due hazard never launches at a player who landed into a rest")
	ctx.resting = false
	local ev = Hazards.step(s, cfg, 0.1, ctx, r)
	eq(ev and ev.type, "spawn", "and it launches as soon as they climb on (it was frozen, not dropped)")
end

-- A hazard already in flight is not cancelled by rest (rest is not a panic button).
do
	local r = lcg(8)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt
	local ev = Hazards.step(s, cfg, 0.1, climbingCtx(), r)
	eq(ev and ev.type, "spawn", "set-up: a hazard spawns")
	local plan = s.active
	local ctx = climbingCtx()
	ctx.resting = true
	Hazards.step(s, cfg, 0.5, ctx, r)
	eq(s.active, plan, "entering rest mid-flight does not remove the hazard")
	approx(plan.t, 0.5, "and its flight keeps advancing while the player rests")
	local done = nil
	for _ = 1, 200 do
		local e = Hazards.step(s, cfg, 0.1, ctx, r)
		if e and e.type == "done" then done = e; break end
	end
	truthy(done ~= nil, "it finishes its flight and reports done")
	eq(s.active, nil, "and frees the slot")
end

--================================================================ planning a lane

do
	local r = lcg(31)
	local aim = { x = 10, y = 200, z = -40 }
	local worstMiss = 0
	local okAll = true
	for _ = 1, 500 do
		for name, kind in cfg.Kinds do
			local plan = Hazards.plan(cfg, name, aim, 0.7, r)
			local atArrival = Hazards.positionAt(plan, plan.arriveAt)
			local dx, dy, dz = atArrival.x - aim.x, atArrival.y - aim.y, atArrival.z - aim.z
			local miss = math.sqrt(dx * dx + dy * dy + dz * dz)
			if miss > worstMiss then worstMiss = miss end
			local startDist = Hazards.distance(plan.start, plan.target)
			if math.abs(startDist - kind.speed * kind.telegraph) > 1e-6 then okAll = false end
			if plan.duration ~= kind.telegraph + kind.pass then okAll = false end
			if plan.hitRadius ~= kind.hitRadius then okAll = false end
		end
	end
	truthy(worstMiss <= cfg.AimJitter + 1e-6,
		"every lane passes within AimJitter of the aim point at arrival: a NEAR-hit by construction (worst "
			.. string.format("%.3f", worstMiss) .. ")")
	truthy(okAll, "a hazard starts speed*telegraph away, flies telegraph+pass seconds, keeps its kind's hit radius")
end

do
	-- the lane comes from IN FRONT of the camera, so the player can see it coming
	local r = lcg(77)
	local worst = 0
	for _ = 1, 2000 do
		local yaw = r() * math.pi * 2
		local plan = Hazards.plan(cfg, "bird", { x = 0, y = 0, z = 0 }, yaw, r)
		local fx, fz = math.sin(yaw), math.cos(yaw)
		local sx, sz = plan.start.x - plan.target.x, plan.start.z - plan.target.z
		local len = math.sqrt(sx * sx + sz * sz)
		local cosAng = (fx * sx + fz * sz) / len
		local ang = math.deg(math.acos(math.clamp(cosAng, -1, 1)))
		if ang > worst then worst = ang end
	end
	truthy(worst <= cfg.SpreadDegrees + 1e-6,
		"a hazard always starts within SpreadDegrees of the view direction (worst " .. string.format("%.2f", worst) .. " deg)")
end

do
	local r = lcg(5)
	local plan = Hazards.plan(cfg, "balloon", { x = 0, y = 0, z = 0 }, 0, r)
	truthy(plan.start.y < 0, "a negative pitch (weather balloon) comes up from BELOW")
	truthy(plan.velocity.y > 0, "and rises")
	local level = Hazards.plan(cfg, "balloon", { x = 0, y = 0, z = 0 }, 0, lcg(5), 0)
	truthy(level.start.y < 0 and level.velocity.y > 0, "seen by a level camera it still rises from below, just inside the view")
end

--================================================================ in view: horizontally AND vertically

-- The elevation of the start, seen from the target, in degrees.
local function elevationOf(plan)
	local dx, dy, dz = plan.start.x - plan.target.x, plan.start.y - plan.target.y, plan.start.z - plan.target.z
	return math.deg(math.atan2(dy, math.sqrt(dx * dx + dz * dz)))
end

do
	-- plan() bends a kind's pitch into the view window around the camera's pitch
	local r = lcg(88)
	local worst = 0
	for _ = 1, 3000 do
		for name in cfg.Kinds do
			local viewPitch = math.rad(-60 + 120 * r())
			local plan = Hazards.plan(cfg, name, { x = 0, y = 0, z = 0 }, r() * 6.283, r, viewPitch)
			local lo, hi = Hazards.viewWindow(cfg, viewPitch)
			local e = elevationOf(plan)
			local off = math.max(lo - e, e - hi, 0)
			if off > worst then worst = off end
		end
	end
	truthy(worst <= 1e-6, "with a view pitch, every lane starts inside ViewPitchDegrees of it (worst "
		.. string.format("%.4f", worst) .. " deg outside)")
	local lo, hi = Hazards.viewWindow(cfg, math.rad(80))
	truthy(hi <= 85 and lo < hi, "the window never reaches straight up or down, where a heading means nothing")
end

do
	-- pickKind keeps each kind's character where it can: a rising balloon is not bent into a falling one
	local r = lcg(91)
	local up, down, balloonUp, balloonDown = 0, 0, 0, 0
	for _ = 1, 2000 do
		if Hazards.pickKind(cfg, { "balloon", "jet" }, math.rad(35), r) == "balloon" then balloonUp += 1 end
		up += 1
		if Hazards.pickKind(cfg, { "balloon", "jet" }, math.rad(-45), r) == "balloon" then balloonDown += 1 end
		down += 1
	end
	eq(balloonUp, 0, "looking up, the rising balloon is never picked while the jet fits the view")
	truthy(balloonDown > 0, "looking down, the balloon is picked (" .. balloonDown .. "/" .. down .. ")")
	local only = 0
	for _ = 1, 200 do
		if Hazards.pickKind(cfg, { "balloon" }, math.rad(35), r) == "balloon" then only += 1 end
	end
	eq(only, 200, "a band whose only kind does not fit still gets it (bent into view by plan)")
end

-- The property the brief needs: "easy to see coming". A camera behind the player (the player at the
-- centre of the screen), Roblox's default 70-degree vertical FOV, 16:9 and 4:3 screens, a 4-degree
-- margin: the hazard is on screen from launch until its lane locks, at every camera pitch a climber
-- uses, through step() (pickKind + plan + tracking).
local function onScreen(camPos, look, p, aspect, margin)
	local fx, fy, fz = look.x, look.y, look.z
	local rx, rz = fz, -fx
	local rl = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rl, rz / rl
	local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
	local dx, dy, dz = p.x - camPos.x, p.y - camPos.y, p.z - camPos.z
	local depth = dx * fx + dy * fy + dz * fz
	if depth <= 0 then return false end
	local tv = math.tan(math.rad(35 - margin))
	local th = math.tan(math.rad(math.deg(math.atan(math.tan(math.rad(35)) * aspect)) - margin))
	local sx = (dx * rx + dz * rz) / depth
	local sy = math.abs((dx * ux + dy * uy + dz * uz) / depth)
	return math.abs(sx) <= th and sy <= tv
end

do
	local r = lcg(4242)
	local total, bad, worstWhere = 0, 0, nil
	for _, camPitch in { -60, -45, -30, -15, 0, 15, 30, 45, 60 } do
		for _, camDist in { 14, 30 } do
			for _, aspect in { 16 / 9, 4 / 3 } do
				for _ = 1, 150 do
					local yaw = r() * math.pi * 2
					local cp = math.rad(camPitch)
					local look = { x = math.sin(yaw) * math.cos(cp), y = math.sin(cp), z = math.cos(yaw) * math.cos(cp) }
					local aim = { x = 0, y = 500, z = 0 }
					local camPos = { x = aim.x - look.x * camDist, y = aim.y - look.y * camDist, z = aim.z - look.z * camDist }
					local s = Hazards.newScheduler(cfg, r)
					s.clock = s.nextAt
					local ctx = { resting = false, grounded = true, kinds = { "bird", "balloon", "jet" }, aim = aim, yaw = yaw, pitch = cp }
					local ev = Hazards.step(s, cfg, 0.05, ctx, r)
					local plan = ev and ev.plan
					total += 1
					local ok = plan ~= nil
					while ok and plan.t < plan.commitAt do
						if not onScreen(camPos, look, Hazards.positionAt(plan, plan.t), aspect, 4) then ok = false end
						Hazards.step(s, cfg, 0.05, ctx, r)
					end
					if not ok then
						bad += 1
						worstWhere = string.format("%s at camera pitch %d, %d studs, aspect %.2f", plan and plan.kind or "?", camPitch, camDist, aspect)
					end
				end
			end
		end
	end
	eq(bad, 0, "every hazard stays on screen from launch until its lane locks, camera pitch -60..60, 16:9 and 4:3 ("
		.. (total - bad) .. "/" .. total .. (if worstWhere then "; e.g. " .. worstWhere else "") .. ")")
end

--================================================================ tracking, then a visible lock

do
	local r = lcg(61)
	local plan = Hazards.plan(cfg, "bird", { x = 0, y = 100, z = 0 }, 0, r)
	approx(plan.commitAt, plan.arriveAt - cfg.Kinds.bird.commit, "the lane locks `commit` seconds before arrival")
	-- the player walks 6 studs during the tracking window; the hazard follows without jumping
	plan.t = 0.8
	local before = Hazards.positionAt(plan, plan.t)
	local moved = { x = 6, y = 100, z = 0 }
	eq(Hazards.retarget(cfg, plan, moved), true, "before the lock, the lane re-aims at the player")
	local after = Hazards.positionAt(plan, plan.t)
	approx(Hazards.distance(before, after), 0, "re-aiming never teleports the hazard (continuous)", 1e-6)
	local arrive = Hazards.positionAt(plan, plan.arriveAt)
	truthy(Hazards.distance(arrive, moved) <= cfg.AimJitter + 1e-6,
		"and it now arrives at the player's NEW position (within AimJitter)")
	approx(plan.arriveAt, cfg.Kinds.bird.telegraph, "the arrival time does not move, so the warning never shortens")

	plan.t = plan.commitAt + 0.01
	local lane = { sx = plan.start.x, vx = plan.velocity.x }
	eq(Hazards.retarget(cfg, plan, { x = -20, y = 100, z = 0 }), false, "after the lock, it no longer follows")
	eq(plan.start.x, lane.sx, "the locked lane is unchanged")
	eq(plan.velocity.x, lane.vx, "and so is its velocity")
	eq(plan.locked, true, "and the plan says it is locked (the client turns the lane red)")
end
do
	-- a teleport (fall rescue) during tracking must not turn the hazard into a missile
	local r = lcg(62)
	local plan = Hazards.plan(cfg, "bird", { x = 0, y = 100, z = 0 }, 0, r)
	plan.t = 1.0
	Hazards.retarget(cfg, plan, { x = 0, y = 600, z = 400 })
	local sp = math.sqrt(plan.velocity.x ^ 2 + plan.velocity.y ^ 2 + plan.velocity.z ^ 2)
	truthy(sp <= cfg.Kinds.bird.speed * cfg.MaxRetargetSpeed + 1e-6,
		"re-aiming at a teleported player never exceeds MaxRetargetSpeed x the kind's speed (" .. string.format("%.1f", sp) .. ")")
	eq(plan.locked, true, "it locks instead, and flies on along its old lane")
end
do
	-- step() does the tracking itself, from ctx.aim, every frame until the lock
	local r = lcg(63)
	local s = Hazards.newScheduler(cfg, r)
	s.clock = s.nextAt
	local ctx = climbingCtx({ "bird" })
	Hazards.step(s, cfg, 0.05, ctx, r)
	local plan = s.active
	truthy(plan ~= nil, "set-up: a bird launched")
	local moving = { x = 0, y = 50, z = 0 }
	local t = 0
	while plan.t < plan.commitAt - 0.1 do
		moving = { x = moving.x + 0.2, y = 50, z = 0 }
		ctx.aim = moving
		Hazards.step(s, cfg, 0.05, ctx, r)
		t += 0.05
	end
	local arrive = Hazards.positionAt(plan, plan.arriveAt)
	truthy(Hazards.distance(arrive, moving) <= cfg.AimJitter + 0.25,
		"a player walking during the warning is still the target at the lock")
end

--================================================================ hit test

do
	-- straight lane along +X through the origin at 20 studs/s, aimed at a player standing at the origin
	local plan = { start = { x = -60, y = 0, z = 0 }, velocity = { x = 20, y = 0, z = 0 }, hitRadius = 2,
		target = { x = 0, y = 0, z = 0 }, jitter = { x = 0, y = 0, z = 0 },
		duration = 6, arriveAt = 3, t = 0, hit = false }
	eq(Hazards.checkHit(plan, 0, 1, { x = 0, y = 0, z = 0 }, 1.5), false, "far away early: no hit")
	eq(Hazards.checkHit(plan, 2.9, 3.1, { x = 0, y = 0, z = 0 }, 1.5), true, "passing through the player: hit")
	eq(Hazards.checkHit(plan, 2.9, 3.1, { x = 0, y = 3.4, z = 0 }, 1.5), true, "within the combined radius (3.5): hit")
	eq(Hazards.checkHit(plan, 2.9, 3.1, { x = 0, y = 3.6, z = 0 }, 1.5), false, "just outside the combined radius: miss")
	-- tunnelling: one enormous frame that jumps from well before to well after the player
	eq(Hazards.checkHit(plan, 0, 6, { x = 0, y = 0, z = 0 }, 1.5), true,
		"a single long frame that skips over the player still hits (swept, no tunnelling)")
	plan.hit = true
	eq(Hazards.checkHit(plan, 2.9, 3.1, { x = 0, y = 0, z = 0 }, 1.5), false, "a hazard hits at most once")
end
do
	-- aimed at a player at x = 64: the lane would pass through them at t = 6.2, but the flight ends at t = 6
	-- (x = 60, 4 studs short). Clipped to the flight: no hit. Unclipped, the frame 5.9..8 would sweep over them.
	local plan = { start = { x = -60, y = 0, z = 0 }, velocity = { x = 20, y = 0, z = 0 }, hitRadius = 2,
		target = { x = 64, y = 0, z = 0 }, jitter = { x = 0, y = 0, z = 0 },
		duration = 6, arriveAt = 6.2, t = 0, hit = false }
	eq(Hazards.checkHit(plan, 5.9, 8, { x = 64, y = 0, z = 0 }, 1.5), false,
		"no hit past the end of the flight (a despawned hazard cannot reach you)")
	plan.duration = 8
	eq(Hazards.checkHit(plan, 5.9, 8, { x = 64, y = 0, z = 0 }, 1.5), true,
		"control: the same frame with a longer flight does hit (the clip above is what saved them)")
end

--================================================================ the ring IS the danger (review round 2)

-- Review 2026-09-17, round 2: the client draws a ring at the player's feet, but the hit test was the whole
-- flight, a (hitRadius + PlayerRadius)-wide corridor along the lane through the target and far past it.
-- Backing away from the hazard, or stepping out of the ring along the lane, was still a hit (65-100 %
-- measured); only a step at right angles to the lane dodged. The rule now: a hit needs the player INSIDE
-- the zone, the circle the ring draws, as well as the hazard passing within reach. Stepping out of the
-- ring in any direction dodges, and what the player sees is exactly what hits.

local kindNames = {}
for name in cfg.Kinds do table.insert(kindNames, name) end
table.sort(kindNames)

do
	-- where the zone is: centred where the player stood when the lane last aimed at them
	truthy(type(Hazards.zone) == "function", "Hazards.zone exists (the circle the client draws as the ring)")
	if type(Hazards.zone) == "function" then
		local r = lcg(515)
		local worst, radiusOk, lockedOk = 0, true, true
		for _ = 1, 200 do
			for _, name in kindNames do
				local kind = cfg.Kinds[name]
				local aim = { x = r() * 50, y = 100 + r() * 20, z = r() * 50 }
				local plan = Hazards.plan(cfg, name, aim, r() * 6.283, r, math.rad(-30 + 60 * r()))
				local z = Hazards.zone(plan, cfg.PlayerRadius)
				worst = math.max(worst, math.abs(z.x - aim.x), math.abs(z.y - aim.y), math.abs(z.z - aim.z))
				if math.abs(z.radius - (kind.hitRadius + cfg.PlayerRadius)) > 1e-9 then radiusOk = false end
				-- the player walks during the warning and the lane re-aims: the zone follows them
				plan.t = plan.commitAt * 0.5
				local moved = { x = aim.x + 1.5, y = aim.y, z = aim.z - 1 }
				Hazards.retarget(cfg, plan, moved)
				z = Hazards.zone(plan, cfg.PlayerRadius)
				worst = math.max(worst, math.abs(z.x - moved.x), math.abs(z.y - moved.y), math.abs(z.z - moved.z))
				-- once the lane has locked, it stays where it was
				plan.t = plan.commitAt + 0.01
				Hazards.retarget(cfg, plan, { x = moved.x + 6, y = moved.y, z = moved.z })
				local after = Hazards.zone(plan, cfg.PlayerRadius)
				if math.abs(after.x - z.x) > 1e-9 or math.abs(after.z - z.z) > 1e-9 then lockedOk = false end
			end
		end
		approx(worst, 0, "the zone is centred exactly where the player stood when the lane last aimed at them", 1e-6)
		truthy(radiusOk, "its radius is the kind's hitRadius + PlayerRadius")
		truthy(lockedOk, "and after the lock it no longer moves")
	end
end

do
	-- a level lane along +X through a player at the origin, no jitter: R = 2 + 1.5 = 3.5
	local function lane()
		return { start = { x = -60, y = 0, z = 0 }, velocity = { x = 20, y = 0, z = 0 }, hitRadius = 2,
			target = { x = 0, y = 0, z = 0 }, jitter = { x = 0, y = 0, z = 0 }, duration = 6, arriveAt = 3, t = 0, hit = false }
	end
	eq(Hazards.checkHit(lane(), 0, 6, { x = 3.6, y = 0, z = 0 }, 1.5), false,
		"on the lane but just OUTSIDE the ring (3.6 studs on, past the target): no hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = -3.6, y = 0, z = 0 }, 1.5), false,
		"on the lane just outside the ring toward the hazard: no hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = 12, y = 0, z = 0 }, 1.5), false,
		"backed well away along the lane (12 studs): no hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = -3.4, y = 0, z = 0 }, 1.5), true,
		"inside the ring, on the lane (3.4 studs from its centre): hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = 2.4, y = 0, z = 2.4 }, 1.5), true,
		"inside the ring on a diagonal (3.39 studs), within reach of the lane: hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = 0, y = 3.4, z = 0 }, 1.5), true,
		"inside the ring and 3.4 studs above the lane (a hop): hit")
	eq(Hazards.checkHit(lane(), 0, 6, { x = 0, y = 12, z = 0 }, 1.5), false,
		"inside the ring but 12 studs above the lane (a real jump): no hit")
end

do
	-- The player stands still until the lane locks, then walks at WalkSpeed (16 studs/s) in a direction
	-- measured from the lane's horizontal travel (0 = straight away from the hazard, 180 = toward it)
	-- until they are 0.05 studs outside the ring, and stands there. Every kind, every 10 degrees, three
	-- camera pitches. The zone used here is computed by the TEST (where they stood, hitRadius +
	-- PlayerRadius), not by the module, so the rule is checked, not echoed.
	local r = lcg(616)
	local total, hits, worst = 0, 0, nil
	local stoodStillHits, stoodStill = 0, 0
	for _, name in kindNames do
		local kind = cfg.Kinds[name]
		for _, pitchDeg in { -30, 0, 25 } do
			for deg = -10, 350, 10 do -- -10 = stand still (the control); 0, 10 .. 350 = walk
				local aim = { x = 0, y = 100, z = 0 }
				local plan = Hazards.plan(cfg, name, aim, r() * 6.283, r, math.rad(pitchDeg))
				local dt = 1 / 60
				while plan.t < plan.commitAt do
					plan.t += dt
					Hazards.retarget(cfg, plan, aim)
				end
				Hazards.retarget(cfg, plan, aim)
				local vx, vz = plan.velocity.x, plan.velocity.z
				local hl = math.sqrt(vx * vx + vz * vz)
				local ux, uz = 1, 0
				if hl > 1e-6 then ux, uz = vx / hl, vz / hl end
				local a = math.rad(math.max(deg, 0))
				local dx, dz = ux * math.cos(a) - uz * math.sin(a), uz * math.cos(a) + ux * math.sin(a)
				local R = kind.hitRadius + cfg.PlayerRadius
				local pos = { x = aim.x, y = aim.y, z = aim.z }
				local hit = false
				while plan.t < plan.duration do
					local t0 = plan.t
					plan.t += dt
					local ox, oz = pos.x - aim.x, pos.z - aim.z
					if deg >= 0 and ox * ox + oz * oz <= (R + 0.05) ^ 2 then
						pos = { x = pos.x + dx * 16 * dt, y = pos.y, z = pos.z + dz * 16 * dt }
					end
					if not hit and Hazards.checkHit(plan, t0, plan.t, pos, cfg.PlayerRadius) then
						hit = true
						plan.hit = true
					end
				end
				if deg < 0 then
					stoodStill += 1
					if hit then stoodStillHits += 1 end
				else
					total += 1
					if hit then
						hits += 1
						worst = worst or string.format("%s walking %d deg from its travel, camera %+d", name, deg, pitchDeg)
					end
				end
			end
		end
	end
	eq(hits, 0, "walking out of the ring in ANY direction after the lock dodges every kind ("
		.. (total - hits) .. "/" .. total .. " dodged" .. (if worst then "; e.g. " .. worst else "") .. ")")
	eq(stoodStillHits, stoodStill, "and a player who stays put in the ring is hit, every kind (" .. stoodStillHits .. "/" .. stoodStill .. ")")
end

-- Easy to avoid: once the lane locks, stepping half a tile (4 studs) off it dodges every kind.
do
	local r = lcg(404)
	local dodged, total = 0, 0
	for _ = 1, 300 do
		for name in cfg.Kinds do
			local aim = { x = 0, y = 100, z = 0 }
			local plan = Hazards.plan(cfg, name, aim, r() * 6.283, r)
			plan.t = plan.commitAt
			Hazards.retarget(cfg, plan, aim) -- the last re-aim at the lock
			plan.t = 0
			-- the player sees the lane and steps 4 studs horizontally, perpendicular to it, away from it
			local vx, vz = plan.velocity.x, plan.velocity.z
			local hl = math.sqrt(vx * vx + vz * vz)
			local px, pz
			if hl < 1e-6 then px, pz = 1, 0 else px, pz = -vz / hl, vx / hl end
			local side = (plan.target.x - aim.x) * px + (plan.target.z - aim.z) * pz
			if side > 0 then px, pz = -px, -pz end
			local stepped = { x = aim.x + px * 4, y = aim.y, z = aim.z + pz * 4 }
			total += 1
			if not Hazards.checkHit(plan, 0, plan.duration, stepped, cfg.PlayerRadius) then dodged += 1 end
		end
	end
	eq(dodged, total, "a 4-stud sidestep away from the lane dodges every hazard (" .. dodged .. "/" .. total .. ")")
end

--================================================================ knockback

do
	local plan = { start = { x = -60, y = 0, z = 0 }, velocity = { x = 20, y = 0, z = 0 }, hitRadius = 2,
		knock = 45, duration = 6, arriveAt = 3, t = 3, hit = false }
	local v = Hazards.knockVelocity(cfg, plan, { x = 0, y = 0, z = 1 })
	approx(v.z, 45, "the knock pushes the player AWAY from the lane")
	approx(v.x, 0, "and not along it when they are beside it")
	approx(v.y, cfg.KnockLift, "with only the small configured lift")
	local centred = Hazards.knockVelocity(cfg, plan, { x = 0, y = 0, z = 0 })
	approx(math.sqrt(centred.x ^ 2 + centred.z ^ 2), 45, "a dead-centre hit still knocks at full strength (along the travel)")
	truthy(centred.y <= cfg.KnockLift, "and never lifts more than KnockLift")
	local steep = { start = { x = 0, y = -60, z = 0 }, velocity = { x = 0, y = 30, z = 0 }, hitRadius = 2,
		knock = 30, duration = 6, arriveAt = 2, t = 2, hit = false }
	local sv = Hazards.knockVelocity(cfg, steep, { x = 0, y = 0, z = 0 })
	approx(math.sqrt(sv.x ^ 2 + sv.z ^ 2), 30, "a vertical lane still produces a horizontal knock (off the platform)")
	truthy(sv.y <= cfg.KnockLift, "and a rising hazard cannot launch the player upward")
end

--================================================================ bearing (screen-edge warning)

do
	-- Roblox: looking down -Z, +X is to the right
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 0, y = 0, z = -50 }), "ahead", "straight ahead")
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 50, y = 0, z = 0 }), "right", "+X is right when looking down -Z")
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = -50, y = 0, z = 0 }), "left", "-X is left")
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -1 }, { x = 0, y = 0, z = 50 }), "behind", "behind")
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = -50, y = 0, z = 0 }), "right", "looking down +Z, -X is right")
	eq(Hazards.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 5, y = 0, z = 0 }), "ahead",
		"a camera looking straight up has no horizontal forward: fall back to ahead, not NaN")
end

--================================================================ Nightwatch Manor adaptations
-- The template was built for an open sky. A manor has a floor and a 15-stud ceiling, and its hunter is
-- the whole game, so the copy gained three things (2026-09-23), each pinned here before it was written (and a
-- fourth, ctx.held, after review 4; its own section below):
--   * ElevationMin/ElevationMax: a hard clamp on the lane's starting elevation, so a hazard comes at you
--     through the room at chest height instead of out of the floor when the camera looks down;
--   * ctx.paused: a SECOND reason to freeze the clock and hold a launch (the Nightwatcher has seen you,
--     or it is day), separate from rest, so the two can never be confused;
--   * Hazards.cancel: a hazard in flight is called off, with no hit and no knock, the moment the
--     Nightwatcher sees you. A knock must never land during a chase.

do
	local ecfg = table.clone(cfg)
	ecfg.ElevationMin = -3
	ecfg.ElevationMax = 12
	truthy((Hazards.validate(ecfg)), "a config with an elevation clamp validates")
	local lo, hi = Hazards.viewWindow(ecfg, math.rad(-15))
	approx(lo, -3, "a camera looking 15 degrees down: the window's floor is the clamp (-3), not -35")
	approx(hi, 5, "and its top is the view's own (-15 + 20 = 5)")
	lo, hi = Hazards.viewWindow(ecfg, math.rad(10))
	approx(lo, -3, "looking 10 up: floor -3 (the view allows -10)")
	approx(hi, 12, "and ceiling 12 (the view allows 30)")
	-- disjoint: a camera looking steeply down sees nothing inside the band; keep the lane in the band
	lo, hi = Hazards.viewWindow(ecfg, math.rad(-60))
	approx(lo, -3, "a camera looking 60 down: the window collapses onto the clamp's floor")
	approx(hi, -3, "to a single elevation, never outside the room's height band")
	lo, hi = Hazards.viewWindow(ecfg, math.rad(70))
	approx(lo, 12, "a camera looking 70 up: collapses onto the clamp's ceiling")
	approx(hi, 12, "likewise")
	-- without the clamp nothing changed (the template's behaviour is kept)
	lo, hi = Hazards.viewWindow(cfg, math.rad(-15))
	approx(lo, -35, "CONTROL: without the clamp the window is the template's (-35)")
	approx(hi, 5, "CONTROL: ...to 5")

	local bad = table.clone(ecfg)
	bad.ElevationMin, bad.ElevationMax = 10, 5
	eq((Hazards.validate(bad)), false, "an elevation clamp whose floor is above its ceiling is rejected")
	bad.ElevationMin, bad.ElevationMax = -89, 5
	eq((Hazards.validate(bad)), false, "an elevation clamp past MAX_ELEVATION is rejected")

	-- every planned lane starts inside the clamp, for every kind and camera pitch
	local r = lcg(99)
	local worstLo, worstHi = math.huge, -math.huge
	for _, name in { "bird", "balloon", "jet" } do
		for pd = -80, 80, 10 do
			for _ = 1, 20 do
				local plan = Hazards.plan(ecfg, name, { x = 0, y = 0, z = 0 }, 0, r, math.rad(pd))
				local d = plan.start
				local el = math.deg(math.atan2(d.y - plan.target.y, math.sqrt((d.x - plan.target.x) ^ 2 + (d.z - plan.target.z) ^ 2)))
				worstLo = math.min(worstLo, el)
				worstHi = math.max(worstHi, el)
			end
		end
	end
	truthy(worstLo >= -3 - 1e-6 and worstHi <= 12 + 1e-6, string.format(
		"every lane of every kind at every camera pitch starts within the clamp (%.2f..%.2f)", worstLo, worstHi))
end

do
	-- paused: frozen clock, no launch, and it resumes where it stopped (never reset)
	local s = Hazards.newScheduler(cfg, lcg(5))
	local due = s.nextAt
	local ctx = { resting = false, paused = true, grounded = true, kinds = { "bird" }, aim = { x = 0, y = 0, z = 0 }, yaw = 0, pitch = 0 }
	for _ = 1, 3000 do
		Hazards.step(s, cfg, 0.1, ctx, lcg(6))
	end
	eq(s.clock, 0, "paused for 300 s: the clock did not move")
	eq(s.active, nil, "and nothing launched")
	ctx.paused = false
	local launched = nil
	local steps = 0
	while launched == nil and steps < 5000 do
		local ev = Hazards.step(s, cfg, 0.1, ctx, lcg(7))
		steps += 1
		if ev and ev.type == "spawn" then launched = s.clock end
	end
	truthy(launched ~= nil and math.abs((launched :: number) - due) < 0.11, string.format(
		"unpaused, the hazard comes when the frozen clock reaches its old due time (%.1f vs %.1f)", launched or -1, due))

	-- paused while a hazard is in flight: it keeps flying (pausing is not cancelling)
	local plan = s.active
	ctx.paused = true
	Hazards.step(s, cfg, 0.5, ctx, lcg(8))
	eq(s.active, plan, "pausing does not remove a hazard already in flight")
	truthy(plan ~= nil and plan.t > 0.4, "and it keeps moving")

	-- cancel: called off, no hit, no knock, and the schedule is untouched
	local nextAt = s.nextAt
	local gone = Hazards.cancel(s)
	eq(gone, plan, "cancel hands back the plan it called off")
	eq(s.active, nil, "and nothing is in flight afterwards")
	eq(s.nextAt, nextAt, "the next due time is not moved by a cancel (it cannot be farmed to thin hazards)")
	eq(Hazards.cancel(s), nil, "cancelling with nothing in flight is a no-op")
	truthy(plan ~= nil and plan.hit == false, "a cancelled hazard never hit anybody")
end

--================================================================ held: the clock runs, the launch waits
-- Review 4 (2026-09-24): pausing the clock for every chase made hazards come MORE often per minute in the
-- manor the better a player hid (one every 33 s of unhunted time: 1.2 per manor-minute for the model's
-- normal player, 1.35 for a stealthier one). A fourth addition, ctx.held: the clock keeps running while the
-- Nightwatcher hunts you, but a hazard that falls due waits until it has let you go. So the rate is per minute
-- of NIGHT, the same for a player who is seen often and one who is never seen, and still nothing launches
-- into a chase. `paused` (the day) still freezes the clock.

do
	local s = Hazards.newScheduler(cfg, lcg(5))
	local due = s.nextAt
	local ctx = { resting = false, paused = false, held = true, grounded = true, kinds = { "bird" }, aim = { x = 0, y = 0, z = 0 }, yaw = 0, pitch = 0 }
	local steps = math.ceil((due + 50) / 0.1)
	for _ = 1, steps do
		Hazards.step(s, cfg, 0.1, ctx, lcg(6))
	end
	approx(s.clock, steps * 0.1, "held: the clock keeps running (it is not frozen like a pause)", 1e-6)
	eq(s.active, nil, "held: nothing launches, though the hazard fell due 50 s ago")
	eq(s.spawned, 0, "...not one")
	eq(s.nextAt, due, "and the due hazard is neither dropped nor re-rolled while it waits (a chase cannot thin hazards)")
	ctx.held = false
	local ev = Hazards.step(s, cfg, 0.1, ctx, lcg(7))
	eq(ev and ev.type, "spawn", "released: the waiting hazard launches on the first free frame")
	truthy(s.nextAt >= s.clock + cfg.IntervalMin - 1e-9, string.format(
		"and ONE hazard, not a backlog: the next is a whole interval after this launch (%.1f >= %.1f)", s.nextAt, s.clock + cfg.IntervalMin))
	local plan = s.active
	ctx.held = true
	Hazards.step(s, cfg, 0.5, ctx, lcg(8))
	eq(s.active, plan, "holding does not remove a hazard already in flight (that is cancel's job)")
	local c0 = s.clock
	ctx.paused = true
	Hazards.step(s, cfg, 1, ctx, lcg(9))
	approx(s.clock, c0, "held AND paused: paused wins, the clock is frozen (the day)")
end

-- The property the change exists for: holding for chases only DELAYS a hazard (by at most the hold it fell due in),
-- it never drops one, so the count per hour of clock barely depends on how often a player is held; and it never
-- bunches two closer than IntervalMin. Six hours of clock, held in random stretches of 15-55 s (a chase plus its
-- quiet window, generously long) for over half of it, against never held, and against the same stretches FROZEN
-- (the old rule), which is what the bound below must tell apart.
do
	local MAX_HOLD = 55
	local function run(holdFraction: number, how: string)
		local r = lcg(777)
		local hr = lcg(4321)
		local s = Hazards.newScheduler(cfg, r)
		local spawns, heldFor, t = 0, 0, 0
		local last, minGap = nil, math.huge
		local holdLeft, freeLeft = 0, 0
		local dt = 0.1
		while t < 6 * 3600 do
			t += dt
			if holdLeft <= 0 and freeLeft <= 0 then
				if hr() < holdFraction then holdLeft = 15 + (MAX_HOLD - 15) * hr() else freeLeft = 20 + 40 * hr() end
			end
			local stopped = holdLeft > 0
			if stopped then holdLeft -= dt; heldFor += dt else freeLeft -= dt end
			local ev = Hazards.step(s, cfg, dt, { resting = false, paused = stopped and how == "paused", held = stopped and how == "held",
				grounded = true, kinds = { "bird" }, aim = { x = 0, y = 0, z = 0 }, yaw = 0, pitch = 0 }, r)
			if ev and ev.type == "spawn" then
				spawns += 1
				if last then minGap = math.min(minGap, t - last) end
				last = t
			end
		end
		return spawns, heldFor / t, minGap
	end
	local never = run(0, "held")
	local often, heldShare, gap = run(0.6, "held")
	local frozen = run(0.6, "paused")
	local mean = (cfg.IntervalMin + cfg.IntervalMax) / 2
	local floor = never * mean / (mean + MAX_HOLD)
	print(string.format("  held probe: never held %d hazards in 6 h; held %.0f%% of the time %d (closest two %.1f s apart); the same stretches frozen %d",
		never, 100 * heldShare, often, gap, frozen))
	truthy(heldShare > 0.5, "CONTROL: the probe really held the clock for over half of the time")
	truthy(often >= floor and often <= never, string.format(
		"held %.0f%% of the time, a player still gets at least %.0f hazards (never held x mean / (mean + longest hold)); got %d of %d: a hold delays, it never drops",
		100 * heldShare, floor, often, never))
	truthy(frozen < floor, string.format("CONTROL: the old frozen clock falls below that bound (%d < %.0f): the bound tells the two apart", frozen, floor))
	truthy(gap >= cfg.IntervalMin - 1e-6, string.format("and two hazards are never closer than IntervalMin (%.1f s)", gap))
end

print(string.format("Hazards: %d passed, %d failed", passed, failed))
assert(failed == 0, "Hazards tests failed")
