-- Spec for Hazards. Run: luau tests/Hazards.spec.luau
--
-- Copied from plus1-jump/tests/Hazards.spec.luau (md5 2f42278c...) with the module (md5 f36a9ac2...). Everything
-- above the line "SIGNAL LOST'S ADAPTATIONS" is the template's spec, unchanged but for this header: it runs the
-- template's own bird / balloon / jet config through the adapted module, whose step() reads the template's ctx
-- (`resting`, `grounded`) exactly as before when the new fields are absent. Below that line, DESIGN.md §5.1's five
-- adaptations are specified against this game's real Config.Hazards.
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

--================================================================ how long the ring and the banner stay up
-- Second review, night of 2026-09-27 (LOW finding 1): the client hid the ring and the banner at `arriveAt`,
-- but checkHit runs until `duration`. A player standing at the far side of the ring from a jittered target
-- is reached AFTER arriveAt, so 6-22 of 400 players per kind were hit 0.02-0.15 s after the ring had gone.
-- The rule now: Hazards.threatLive(plan, playerRadius, fromT) is true while the rest of the flight (from
-- fromT, default plan.t) can still hit SOMEONE standing inside the zone, at any height. The client draws
-- the ring and the banner exactly that long. It only ever keeps them up longer, never shorter.
do
	truthy(type(Hazards.threatLive) == "function", "Hazards.threatLive exists (how long the ring and the banner stay up)")
	if type(Hazards.threatLive) == "function" then
		local r = lcg(2709)
		local dt = 1 / 60
		local hitsAfterArrival, hitsWhileNotLive, hits, trials = 0, 0, 0, 0
		local lingerMax, goneBeforeEnd, plans = 0, 0, 0
		local soundBad = nil
		local liveAfterEnd = 0
		for _, name in kindNames do
			local kind = cfg.Kinds[name]
			local R = kind.hitRadius + cfg.PlayerRadius
			for i = 1, 400 do
				local aim = { x = 0, y = 100, z = 0 }
				local plan = Hazards.plan(cfg, name, aim, r() * 6.283, r, math.rad(-30 + 60 * r()))
				while plan.t < plan.commitAt do
					plan.t += dt
					Hazards.retarget(cfg, plan, aim)
				end
				Hazards.retarget(cfg, plan, aim)
				-- at the lock the player steps to a random point inside the ring and stays there
				local rr, ra = R * math.sqrt(r()), r() * 6.283
				local pos = { x = aim.x + rr * math.cos(ra), y = aim.y, z = aim.z + rr * math.sin(ra) }
				trials += 1
				local goneAt = nil
				while plan.t < plan.duration do
					local t0 = plan.t
					plan.t += dt
					local live = Hazards.threatLive(plan, cfg.PlayerRadius, t0)
					-- when the RING goes (geometry only: after a hit the plan is over anyway)
					local wasHit = plan.hit
					plan.hit = false
					if goneAt == nil and not Hazards.threatLive(plan, cfg.PlayerRadius, t0) then goneAt = t0 end
					plan.hit = wasHit
					if Hazards.checkHit(plan, t0, plan.t, pos, cfg.PlayerRadius) then
						plan.hit = true
						hits += 1
						if t0 > plan.arriveAt then hitsAfterArrival += 1 end
						if not live then hitsWhileNotLive += 1 end
					end
				end
				if Hazards.threatLive(plan, cfg.PlayerRadius) then liveAfterEnd += 1 end
				-- soundness: from the moment the rule says "over", no point inside the zone, at any height from
				-- 10 below to 70 above the aim, can be hit by the rest of the flight (the unhit copy of the plan)
				if goneAt ~= nil then
					plans += 1
					if goneAt < plan.duration - 1e-9 then goneBeforeEnd += 1 end
					lingerMax = math.max(lingerMax, goneAt - plan.arriveAt)
					local fresh = table.clone(plan)
					fresh.hit = false
					local z = Hazards.zone(fresh, cfg.PlayerRadius)
					for k = 1, 60 do
						local qr, qa = z.radius * math.sqrt(r()), r() * 6.283
						local q = { x = z.x + qr * math.cos(qa), y = aim.y - 10 + 80 * r(), z = z.z + qr * math.sin(qa) }
						if Hazards.checkHit(fresh, goneAt, fresh.duration, q, cfg.PlayerRadius) then
							soundBad = soundBad or string.format("%s: a point inside the ring is hit %.2f s after the ring would go", name, fresh.duration - goneAt)
						end
					end
				end
			end
		end
		print(string.format("  ring rule: %d random points inside the ring, %d hit; %d of the hits came after arriveAt (the old rule's ring was gone); ring gone %.2f s after arrival at most, before the flight's end in %d of %d",
			trials, hits, hitsAfterArrival, lingerMax, goneBeforeEnd, plans))
		truthy(hitsAfterArrival > 0, "set-up: some players inside the ring ARE reached after arriveAt (" .. hitsAfterArrival .. ")")
		eq(hitsWhileNotLive, 0, "no player is hit once threatLive says the hazard can no longer hit")
		eq(soundBad, nil, "and no point anywhere inside the ring can be hit after that")
		eq(liveAfterEnd, 0, "nothing is live once the flight is over")
		eq(goneBeforeEnd, plans, "the ring does not linger to the end of the flight: it goes once the hazard is out of reach")
		truthy(lingerMax < 1.5, string.format("and within 1.5 s of arrival for these kinds (%.2f s)", lingerMax))
		-- before the lock the lane tracks the player, so the threat is live from launch
		local p2 = Hazards.plan(cfg, "bird", { x = 0, y = 0, z = 0 }, 0, lcg(5))
		eq(Hazards.threatLive(p2, cfg.PlayerRadius), true, "a hazard just launched is live")
		p2.hit = true
		eq(Hazards.threatLive(p2, cfg.PlayerRadius), false, "a hazard that has hit is over (it hits once)")
	end
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

--================================================================ SIGNAL LOST'S ADAPTATIONS (DESIGN.md §5.1)
-- Against this game's real Config.Hazards. Every kind drifts slowly (zero-g debris), the clock runs only while
-- the caller says the player is ELIGIBLE (a vacuum module, a band with hazards, past the arrival grace, AIR >= 10,
-- not resting), a due hazard waits for a still player, a lane starts inside the module, leaving the module locks
-- its lane, and leaving the sector calls it off.
local SL = require("../src/shared/Config")
local Hz = SL.Hazards
local ALL = {}
for name in Hz.Kinds do table.insert(ALL, name) end
table.sort(ALL)

-- A module-shaped box: the 30-stud interior of a 32-stud module centred on the origin, floor top at y = 0.
local INNER = SL.Station.CellSize / 2 - SL.Station.WallThickness
local BOX = { minX = -INNER, maxX = INNER, minY = 0, maxY = SL.Station.CeilingHeight, minZ = -INNER, maxZ = INNER }
local function stationCtx(over)
	local c = { eligible = true, grounded = true, still = true, kinds = { "crate" }, aim = { x = 0, y = 2.51, z = 0 },
		yaw = 0, pitch = math.rad(-15), module = 7, box = BOX }
	for k, v in over or {} do c[k] = v end
	return c
end

do -- the real config validates, and its own promises are enforced
	local ok, err = Hazards.validateStation(Hz)
	truthy(ok, "Config.Hazards passes validateStation (" .. tostring(err) .. ")")
	local function without(field, value)
		local c = table.clone(Hz)
		c.Kinds = table.clone(Hz.Kinds)
		c[field] = value
		return c
	end
	eq((Hazards.validateStation(without("FirstIntervalSeconds", 0))), false, "a first interval of 0 is refused")
	eq((Hazards.validateStation(without("WaitForStillSeconds", -1))), false, "a negative wait is refused")
	eq((Hazards.validateStation(without("KnockLift", 3))), false, "a template lift above LiftMax (1) is refused")
	local slow = table.clone(Hz)
	slow.Kinds = table.clone(Hz.Kinds)
	slow.Kinds.crate = table.clone(Hz.Kinds.crate)
	slow.Kinds.crate.hitRadius = 8 -- ring 9.5: 9.5 / 7.8 + 0.5 = 1.72 s > the 1.5 s commit
	local okE, errE = Hazards.validateStation(slow)
	eq(okE, false, "a ring the slowest walker cannot leave between the lock and the arrival is refused")
	truthy(type(errE) == "string" and string.find(errE, "escape", 1, true) ~= nil, "for that reason (" .. tostring(errE) .. ")")
	local hard = table.clone(Hz)
	hard.Kinds = table.clone(Hz.Kinds)
	hard.Kinds.slag = table.clone(Hz.Kinds.slag)
	hard.Kinds.slag.knock = 26
	eq((Hazards.validateStation(hard)), false, "a knock above KnockMax (20) is refused")
	local lifty = table.clone(Hz)
	lifty.Kinds = table.clone(Hz.Kinds)
	lifty.Kinds.orb = table.clone(Hz.Kinds.orb)
	lifty.Kinds.orb.lift = 2
	eq((Hazards.validateStation(lifty)), false, "a kind lift above LiftMax (1) is refused")
	local long = table.clone(Hz)
	long.Kinds = table.clone(Hz.Kinds)
	long.Kinds.globe = table.clone(Hz.Kinds.globe)
	long.Kinds.globe.speed = 12 -- 12 x 3.2 = 38 studs, longer than the 27-stud interior
	eq((Hazards.validateStation(long)), false, "a lane longer than a module's interior is refused")
	local worst = 0
	for _, name in ALL do
		local k = Hz.Kinds[name]
		worst = math.max(worst, (k.hitRadius + Hz.PlayerRadius) / Hz.EscapeSpeed + Hz.ReactionSeconds)
	end
	truthy(worst <= Hz.MinCommitSeconds, string.format("every ring is left in %.2f s at 7.8 studs/s + 0.5 s reaction (commit 1.5)", worst))
end

do -- adaptation 5: the first hazard of a session after FirstIntervalSeconds of eligible time, then 55..85
	local r = lcg(3030)
	local s = Hazards.newScheduler(Hz, r)
	eq(s.nextAt, Hz.FirstIntervalSeconds, "the first hazard is due after " .. Hz.FirstIntervalSeconds .. " s of eligible time")
	local t, first, gaps, last = 0, nil, {}, nil
	for _ = 1, 36000 do
		t += 0.1
		local ev = Hazards.step(s, Hz, 0.1, stationCtx(), r)
		if ev and ev.type == "spawn" then
			if not first then first = t end
			if last then table.insert(gaps, t - last) end
			last = t
		end
	end
	truthy(first ~= nil and math.abs(first - Hz.FirstIntervalSeconds) <= 0.11, "the first lands at 30 s (" .. tostring(first) .. ")")
	local lo, hi = math.huge, 0
	for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g) end
	truthy(lo >= 55 - 1e-6 and hi <= 85 + 0.2, string.format("then one every 55..85 s (%.1f..%.1f)", lo, hi))
	local perMin = #gaps / ((last - first) / 60)
	print(string.format("  measured: %d hazards in 1 h of eligible time, one per %.1f s after the first", #gaps + 1, (last - first) / #gaps))
	-- REVIEW-1 finding 5: 80..120 s gave one warning per 3.3-3.6 min of play on the real client path, not the 2-3 the
	-- standard asks; 55..85 gives one per 2.32-3.08 min, median 2.54 (check_signallost_campaign measures it through the real client)
	truthy(perMin > 1 / 1.4 and perMin < 1 / 1.0, "about one per 70 s of eligible time (" .. string.format("%.2f", perMin) .. "/min)")
end

do -- adaptation 1: the clock runs only while eligible, freezes otherwise, never resets
	local r = lcg(77)
	local s = Hazards.newScheduler(Hz, r)
	local spawns = 0
	for _ = 1, 36000 do
		local ev = Hazards.step(s, Hz, 0.1, stationCtx({ eligible = false }), r)
		if ev and ev.type == "spawn" then spawns += 1 end
	end
	eq(spawns, 0, "an hour never eligible (air modules, the Docking Ring, low air, the arrival grace): no hazard")
	eq(s.clock, 0, "and the clock did not move")
	local function run(pattern)
		local rr = lcg(99)
		local ss = Hazards.newScheduler(Hz, rr)
		local eligibleT, n, wall = 0, 0, 0
		while eligibleT < 6 * 3600 do
			wall += 0.1
			local e = pattern(wall)
			local ev = Hazards.step(ss, Hz, 0.1, stationCtx({ eligible = e }), rr)
			if ev and ev.type == "spawn" then n += 1 end
			if e then eligibleT += 0.1 end
		end
		return n
	end
	local always = run(function() return true end)
	local shuttle = run(function(t) return (math.floor(t / 9) % 2) == 0 end) -- 9 s in vacuum, 9 s in air, forever
	eq(shuttle, always, "shuttling between vacuum and air yields EXACTLY the hazards per eligible hour of never leaving (" .. always .. ")")
end

do -- adaptation 3: a due hazard waits for a still player, at most WaitForStillSeconds
	local r = lcg(5150)
	local s = Hazards.newScheduler(Hz, r)
	s.clock = s.nextAt
	local waited = 0
	local ev
	repeat
		ev = Hazards.step(s, Hz, 0.1, stationCtx({ still = false }), r)
		waited += 0.1
	until (ev and ev.type == "spawn") or waited > 60
	truthy(ev and ev.type == "spawn", "a player who never stops still gets the hazard")
	truthy(math.abs(waited - Hz.WaitForStillSeconds - 0.1) <= 0.11, string.format("after waiting %.1f s of eligible time for them to stop (15)", waited))
	local s2 = Hazards.newScheduler(Hz, r)
	s2.clock = s2.nextAt - 0.05
	local ev2 = Hazards.step(s2, Hz, 0.1, stationCtx({ still = false }), r)
	eq(ev2, nil, "due, moving: it waits")
	ev2 = Hazards.step(s2, Hz, 0.1, stationCtx({ still = true }), r)
	eq(ev2 and ev2.type, "spawn", "the moment they stand still, it comes")
	local s3 = Hazards.newScheduler(Hz, r)
	s3.clock = s3.nextAt
	for _ = 1, 50 do Hazards.step(s3, Hz, 0.1, stationCtx({ still = false }), r) end
	Hazards.step(s3, Hz, 0.1, stationCtx({ eligible = false, still = false }), r)
	eq(s3.active, nil, "set-up: 5 s of waiting, then the player reached air")
	local w0 = s3.waited
	for _ = 1, 100 do Hazards.step(s3, Hz, 0.1, stationCtx({ eligible = false, still = false }), r) end
	eq(s3.waited, w0, "the wait counts eligible time only: 10 s in air adds nothing to it")
end

do -- adaptation 4 (REVIEW-1 finding 4): leaving its module LOCKS the lane, and the flight finishes through the ring
	-- the player left. Calling it off there made 111 of 112 warnings vanish mid-telegraph on the real client path: a
	-- player in vacuum keeps walking, and the next hatch is 2-3 s away. Leaving the SECTOR still calls it off.
	local r = lcg(4)
	local s = Hazards.newScheduler(Hz, r)
	s.clock = s.nextAt
	local ev = Hazards.step(s, Hz, 0.1, stationCtx({ module = 7, sector = 3 }), r)
	eq(ev and ev.type, "spawn", "set-up: a hazard in module 7")
	eq(s.active and s.active.module, 7, "it belongs to module 7")
	ev = Hazards.step(s, Hz, 0.1, stationCtx({ module = 7, sector = 3 }), r)
	eq(s.active ~= nil, true, "still there while the player stays")
	local plan = s.active
	local z0 = Hazards.zone(plan, Hz.PlayerRadius)
	local away = { x = 20, y = 2.51, z = 0 } -- through the hatch, in module 8
	local function inEight() return stationCtx({ module = 8, sector = 3, eligible = false, aim = away }) end
	ev = Hazards.step(s, Hz, 0.1, inEight(), r)
	eq(ev, nil, "the player walks into module 8: the hazard is NOT called off")
	eq(plan.locked, true, "its lane locks: it never follows a player into another module")
	local hit, done, t0 = false, nil, plan.t
	for _ = 1, 100 do
		local e = Hazards.step(s, Hz, 0.1, inEight(), r)
		if Hazards.checkHitStation(Hz, plan, t0, plan.t, away, Hz.PlayerRadius) then hit = true end
		t0 = plan.t
		if e then done = e break end
	end
	local z1 = Hazards.zone(plan, Hz.PlayerRadius)
	truthy(math.abs(z1.x - z0.x) < 1e-9 and math.abs(z1.z - z0.z) < 1e-9, "the ring stays where the player left it")
	eq(done and done.type, "done", "it finishes its flight through the ring the player left (a near-miss, not a vanishing warning)")
	eq(hit, false, "and the player who left the ring is not hit")
	local s2 = Hazards.newScheduler(Hz, r)
	s2.clock = s2.nextAt
	Hazards.step(s2, Hz, 0.1, stationCtx({ module = 7, sector = 3 }), r)
	local ev2 = Hazards.step(s2, Hz, 0.1, stationCtx({ module = false, eligible = false }), r)
	eq(ev2 and ev2.type, "cancel", "leaving the sector (a blackout, the transit) calls it off")
	local s3 = Hazards.newScheduler(Hz, r)
	s3.clock = s3.nextAt
	Hazards.step(s3, Hz, 0.1, stationCtx({ module = 7, sector = 3 }), r)
	local ev3 = Hazards.step(s3, Hz, 0.1, stationCtx({ module = 7, sector = 4 }), r)
	eq(ev3 and ev3.type, "cancel", "a new sector calls it off even where a module id repeats")
end

do -- adaptation 2: the lane starts inside the module; clamped lanes keep their arrival time
	local r = lcg(2222)
	local total, outside, arrivalMoved, shorter, clampedFaster, refused = 0, 0, 0, 0, 0, 0
	local m = Hz.InteriorMargin
	for _ = 1, 3000 do
		local name = ALL[1 + math.floor(r() * #ALL)]
		local aim = { x = -12 + 24 * r(), y = 2.51 + r() * 6, z = -12 + 24 * r() }
		local plan = Hazards.plan(Hz, name, aim, r() * 6.283, r, math.rad(-30 + 30 * r()))
		local kind = Hz.Kinds[name]
		local full = Hazards.distance(plan.start, plan.target)
		if Hazards.clampLane(Hz, plan, BOX) then
			total += 1
			local st = plan.start
			if st.x < BOX.minX + m - 1e-6 or st.x > BOX.maxX - m + 1e-6 or st.y < BOX.minY + m - 1e-6
				or st.y > BOX.maxY - m + 1e-6 or st.z < BOX.minZ + m - 1e-6 or st.z > BOX.maxZ - m + 1e-6 then
				outside += 1
			end
			local arrive = Hazards.positionAt(plan, plan.arriveAt)
			if Hazards.distance(arrive, plan.target) > 1e-6 or math.abs(plan.arriveAt - kind.telegraph) > 1e-9 then arrivalMoved += 1 end
			local len = Hazards.distance(plan.start, plan.target)
			if len < full - 1e-6 then
				shorter += 1
				local sp = math.sqrt(plan.velocity.x ^ 2 + plan.velocity.y ^ 2 + plan.velocity.z ^ 2)
				if sp > kind.speed + 1e-6 then clampedFaster += 1 end
			end
			if len < Hz.MinLaneStuds - 1e-6 then outside += 1 end
		else
			refused += 1
		end
	end
	eq(outside, 0, "every lane starts inside the module (InteriorMargin off every wall, the floor and the ceiling) and is >= MinLaneStuds long")
	eq(arrivalMoved, 0, "a clamped lane still arrives at the player exactly `telegraph` seconds after it starts: the warning never shortens")
	eq(clampedFaster, 0, "a clamped lane drifts slower, never faster")
	truthy(shorter > 100, "and the clamp does bind for players near a wall (" .. shorter .. " of " .. total .. " lanes shortened)")
	print(string.format("  lanes: %d fit (%d shortened), %d waited for a better view (too short near a wall)", total, shorter, refused))
end

do -- WHY adaptation 6 exists: slow debris is within reach before arrival. With the template's swept hit, a player
	-- who steps out of the ring TOWARD the incoming debris walks into it (measured while building, 2026-10-01:
	-- 342 of 363 hit at 150-180 degrees from the lane's travel, 0 at 0-120, with 6 studs/s crates)
	local r = lcg(9090)
	local towardHitsTemplate, towardHitsStation, n = 0, 0, 0
	for _ = 1, 200 do
		local aim = { x = 0, y = 2.51, z = 0 }
		local plan = Hazards.plan(Hz, "crate", aim, r() * 6.283, r, math.rad(-15))
		while plan.t < plan.commitAt do plan.t += 1 / 60; Hazards.retarget(Hz, plan, aim) end
		local vx, vz = plan.velocity.x, plan.velocity.z
		local hl = math.sqrt(vx * vx + vz * vz)
		local dx, dz = -vx / hl, -vz / hl -- straight toward the debris
		local R = Hz.Kinds.crate.hitRadius + Hz.PlayerRadius
		local lockT = plan.t
		for pass = 1, 2 do
			plan.t = lockT
			plan.hit = false
			local pos = { x = 0, y = 2.51, z = 0 }
			local hit = false
			local waited = 0
			while plan.t < plan.duration do
				local t0 = plan.t
				plan.t += 1 / 60
				waited += 1 / 60
				if waited > Hz.ReactionSeconds and pos.x * pos.x + pos.z * pos.z <= (R + 0.05) ^ 2 then
					pos = { x = pos.x + dx * Hz.EscapeSpeed / 60, y = 2.51, z = pos.z + dz * Hz.EscapeSpeed / 60 }
				end
				local h = if pass == 1 then Hazards.checkHit(plan, t0, plan.t, pos, Hz.PlayerRadius)
					else Hazards.checkHitStation(Hz, plan, t0, plan.t, pos, Hz.PlayerRadius)
				if not hit and h then hit = true; plan.hit = true end
			end
			if hit then
				if pass == 1 then towardHitsTemplate += 1 else towardHitsStation += 1 end
			end
		end
		n += 1
	end
	print(string.format("  stepping out TOWARD the debris after a 0.5 s reaction: template hit %d/%d, adapted %d/%d", towardHitsTemplate, n, towardHitsStation, n))
	truthy(towardHitsTemplate > n / 2, "set-up: the template's swept test hits most players who step out toward slow debris")
	eq(towardHitsStation, 0, "the adapted hit (from HitLeadSeconds before arrival) lets every one of them dodge")
	eq(Hz.AimJitter, 0, "and the lane is aimed at the ring's exact centre (no jitter), so anyone left in the ring is reached")
end

do -- the ring is still exactly the hit zone, on clamped lanes, for every kind
	local r = lcg(616)
	local total, hits, stoodHit, stood = 0, 0, 0, 0
	for _, name in ALL do
		local kind = Hz.Kinds[name]
		for i = 1, 60 do
			local aim = { x = -10 + 20 * r(), y = 2.51, z = -10 + 20 * r() }
			local plan = Hazards.plan(Hz, name, aim, r() * 6.283, r, math.rad(-15))
			if Hazards.clampLane(Hz, plan, BOX) then
				local dt = 1 / 60
				while plan.t < plan.commitAt do
					plan.t += dt
					Hazards.retarget(Hz, plan, aim)
				end
				Hazards.retarget(Hz, plan, aim)
				local R = kind.hitRadius + Hz.PlayerRadius
				local a = r() * 6.283
				local walk = i % 4 ~= 0
				local pos = { x = aim.x, y = aim.y, z = aim.z }
				local hit = false
				while plan.t < plan.duration do
					local t0 = plan.t
					plan.t += dt
					local ox, oz = pos.x - aim.x, pos.z - aim.z
					if walk and plan.t > plan.commitAt + Hz.ReactionSeconds and ox * ox + oz * oz <= (R + 0.05) ^ 2 then
						pos = { x = pos.x + math.cos(a) * Hz.EscapeSpeed * dt, y = pos.y, z = pos.z + math.sin(a) * Hz.EscapeSpeed * dt }
					end
					if not hit and Hazards.checkHitStation(Hz, plan, t0, plan.t, pos, Hz.PlayerRadius) then hit = true; plan.hit = true end
				end
				if walk then total += 1; if hit then hits += 1 end else stood += 1; if hit then stoodHit += 1 end end
			end
		end
	end
	eq(hits, 0, "walking out of the ring at 7.8 studs/s, 0.5 s after the lock, in ANY direction, dodges every kind (" .. total .. " tries)")
	eq(stoodHit, stood, "and standing still in it is always a hit (" .. stoodHit .. "/" .. stood .. ")")
end

do -- the knock: horizontal, at most KnockMax, lift at most the kind's (<= 1)
	local r = lcg(8)
	local worstH, worstLift = 0, 0
	for _, name in ALL do
		for _ = 1, 100 do
			local plan = Hazards.plan(Hz, name, { x = 0, y = 2.51, z = 0 }, r() * 6.283, r, math.rad(-15))
			plan.t = plan.arriveAt
			local v = Hazards.knockVelocity(Hz, plan, { x = r() - 0.5, y = 2.51, z = r() - 0.5 })
			worstH = math.max(worstH, math.sqrt(v.x * v.x + v.z * v.z))
			worstLift = math.max(worstLift, v.y)
			if v.y > (Hz.Kinds[name].lift or 0) + 1e-9 then worstLift = 99 end
		end
	end
	truthy(worstH <= Hz.KnockMax + 1e-9, string.format("the shove is at most %d studs/s (%.1f)", Hz.KnockMax, worstH))
	truthy(worstLift <= Hz.LiftMax + 1e-9, string.format("and lifts at most the kind's lift, <= %d stud/s (%.2f)", Hz.LiftMax, worstLift))
	local rise = 1 / (2 * 196.2 * SL.Move.VacGravityFactor)
	truthy(rise < 0.02, string.format("a 1 stud/s lift under 20 %% gravity rises %.3f studs", rise))
end

do -- one hazard at a time
	local r = lcg(31337)
	local s = Hazards.newScheduler(Hz, r)
	local maxActive = 0
	for _ = 1, 72000 do
		Hazards.step(s, Hz, 0.1, stationCtx({ kinds = { "globe", "orb" } }), r)
		if s.active then maxActive = math.max(maxActive, 1) end
	end
	eq(maxActive, 1, "never more than one hazard at a time over 2 h")
end

print(string.format("Hazards: %d passed, %d failed", passed, failed))
assert(failed == 0, "Hazards tests failed")
