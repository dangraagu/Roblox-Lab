--!strict
-- Hazards.luau — rare, telegraphed, rate-limited, one-at-a-time hazards. Game-agnostic, pure.
--
-- What it decides:
--   * WHEN: on a clock that only runs while the player is climbing (resting freezes it, it is
--     never reset), one hazard every IntervalMin..IntervalMax seconds, never two in the air.
--   * WHERE: a straight lane that starts ON SCREEN: at most SpreadDegrees left/right of the camera's
--     heading and at most ViewPitchDegrees above/below the camera's pitch (a kind whose natural
--     pitch would put it off screen is either swapped for a kind that fits the view, or bent into
--     it). The camera sits behind the player, so a start on screen stays on screen all the way in.
--     While the warning runs, the lane keeps re-aiming
--     at the player (it visibly comes FOR you); `commit` seconds before arrival it LOCKS and flies
--     straight. A near-hit by construction: a player who does nothing is hit, a player who steps
--     out of the ZONE (the ring the client draws where they stood) is not, in any direction. The
--     arrival time never moves, so the warning never shortens.
--   * WHETHER IT HIT: the player inside the zone AND a swept segment test (so a fast hazard in a long
--     frame cannot tunnel). Without the zone the danger was a corridor along the whole lane.
--   * HOW HARD: horizontal knock away from the lane plus a small, capped lift. A hit can push a
--     player off a ledge; it can never launch them upward onto something.
--
-- Nightwatch Manor's copy (2026-09-23/24) adds four things, each pinned in tests/Hazards.spec.luau:
--   * ElevationMin / ElevationMax: a hard clamp on where a lane may START (degrees above the player).
--     A manor has a floor and a 15-stud ceiling; with the camera pitched down the template's window
--     would start lanes under the floor. When the view and the clamp do not overlap, the clamp wins.
--   * ctx.paused: a second reason to freeze the clock and hold a launch (it is day, or the night has
--     just ended). It never removes a hazard already in flight; that is Hazards.cancel's job.
--   * ctx.held (review 4): the clock RUNS, but a hazard that falls due waits until the hold lifts (the
--     Nightwatcher sees you, or has only just lost you). Freezing the clock for chases made hazards come
--     more often per minute in the manor the better a player hid; holding keeps the rate per minute of
--     night, and still never launches into a chase. One waiting hazard, never a backlog.
--   * Hazards.cancel: call off the hazard in flight with no hit and no knock. The client calls it the
--     moment the Nightwatcher sees the player, so a knock never lands during a chase.
--
-- What it does NOT do: build Parts, read Roblox, grant or remove anything. Vectors are plain
-- { x, y, z } tables and randomness is an injected `rand(): number in [0, 1)`, so the whole
-- module runs in the luau CLI. The caller renders `state.active` and applies the knock.

local Hazards = {}

-- A hazard is a nudge, never a launch pad. Configs asking for more lift are rejected.
Hazards.MAX_KNOCK_LIFT = 15

-- "Easy to see coming" means the lane STARTS on screen. Roblox's default camera has a 70-degree
-- vertical field of view (35 each way) and a 4:3 tablet shows about 43 degrees each way horizontally;
-- both limits keep a margin inside that.
Hazards.MAX_VIEW_PITCH = 30
Hazards.MAX_SPREAD = 40
-- A lane never starts straight above or below the player, where "the camera's heading" means nothing.
Hazards.MAX_ELEVATION = 85

type Vec = { x: number, y: number, z: number }

local function v(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end

function Hazards.distance(a: Vec, b: Vec): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Hazards.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no hazard config" end
	if type(cfg.IntervalMin) ~= "number" or cfg.IntervalMin <= 0 then
		return false, "IntervalMin must be > 0"
	end
	if type(cfg.IntervalMax) ~= "number" or cfg.IntervalMax < cfg.IntervalMin then
		return false, "IntervalMax must be >= IntervalMin"
	end
	if type(cfg.MinTelegraphSeconds) ~= "number" or cfg.MinTelegraphSeconds <= 0 then
		return false, "MinTelegraphSeconds must be > 0"
	end
	if type(cfg.MinCommitSeconds) ~= "number" or cfg.MinCommitSeconds <= 0 then
		return false, "MinCommitSeconds must be > 0"
	end
	if type(cfg.MaxRetargetSpeed) ~= "number" or cfg.MaxRetargetSpeed < 1 then
		return false, "MaxRetargetSpeed must be >= 1"
	end
	if type(cfg.ViewPitchDegrees) ~= "number" or cfg.ViewPitchDegrees <= 0 or cfg.ViewPitchDegrees > Hazards.MAX_VIEW_PITCH then
		return false, "ViewPitchDegrees must be within (0, " .. Hazards.MAX_VIEW_PITCH .. "]: a lane must start on screen vertically"
	end
	local spread = cfg.SpreadDegrees or 0
	if type(spread) ~= "number" or spread < 0 or spread > Hazards.MAX_SPREAD then
		return false, "SpreadDegrees must be within 0.." .. Hazards.MAX_SPREAD .. ": a lane must start on screen horizontally"
	end
	if cfg.KindFitDegrees ~= nil and (type(cfg.KindFitDegrees) ~= "number" or cfg.KindFitDegrees < 0) then
		return false, "KindFitDegrees must be >= 0"
	end
	if cfg.ElevationMin ~= nil or cfg.ElevationMax ~= nil then
		local lo, hi = cfg.ElevationMin, cfg.ElevationMax
		if type(lo) ~= "number" or type(hi) ~= "number" or lo > hi
			or lo < -Hazards.MAX_ELEVATION or hi > Hazards.MAX_ELEVATION then
			return false, "ElevationMin/ElevationMax must both be set, ordered, and within +-" .. Hazards.MAX_ELEVATION
		end
	end
	local lift = cfg.KnockLift or 0
	if lift < 0 or lift > Hazards.MAX_KNOCK_LIFT then
		return false, "KnockLift must be within 0.." .. Hazards.MAX_KNOCK_LIFT
	end
	if type(cfg.Kinds) ~= "table" then return false, "no Kinds" end
	for name, k in cfg.Kinds do
		local function bad(why: string)
			return false, "hazard kind " .. tostring(name) .. ": " .. why
		end
		if type(k.speed) ~= "number" or k.speed <= 0 then return bad("speed must be > 0") end
		if type(k.telegraph) ~= "number" or k.telegraph < cfg.MinTelegraphSeconds then
			return bad("telegraph shorter than MinTelegraphSeconds")
		end
		if type(k.commit) ~= "number" or k.commit < cfg.MinCommitSeconds then
			return bad("commit shorter than MinCommitSeconds (no time to step off the locked lane)")
		end
		if k.commit > k.telegraph then return bad("commit longer than telegraph") end
		if type(k.pass) ~= "number" or k.pass <= 0 then return bad("pass must be > 0") end
		if type(k.hitRadius) ~= "number" or k.hitRadius <= 0 then return bad("hitRadius must be > 0") end
		if type(k.knock) ~= "number" or k.knock < 0 then return bad("knock must be >= 0") end
		if type(k.pitch) ~= "number" then return bad("pitch must be a number") end
	end
	return true, nil
end

function Hazards.rollInterval(cfg: any, rand: () -> number): number
	return cfg.IntervalMin + (cfg.IntervalMax - cfg.IntervalMin) * rand()
end

-- clock: climbing seconds so far. nextAt: climbing second of the next launch. active: the plan in flight.
function Hazards.newScheduler(cfg: any, rand: () -> number): any
	return { clock = 0, nextAt = Hazards.rollInterval(cfg, rand), active = nil, spawned = 0 }
end

-- (lo, hi) in degrees: the elevations a lane may start at for a camera pitched `viewPitch` radians
-- (positive = looking up). The camera is behind the player, so an elevation measured from the player
-- inside this window is inside the view from the camera too.
function Hazards.viewWindow(cfg: any, viewPitch: number): (number, number)
	local centre = math.deg(viewPitch)
	if centre ~= centre then centre = 0 end
	centre = math.clamp(centre, -Hazards.MAX_ELEVATION, Hazards.MAX_ELEVATION)
	local half = cfg.ViewPitchDegrees or 0
	local lo = math.max(-Hazards.MAX_ELEVATION, centre - half)
	local hi = math.min(Hazards.MAX_ELEVATION, centre + half)
	-- the room's height band, when the game has one: the lane must stay inside it even if that means
	-- leaving the view (a camera looking straight down at the floor sees no lane start at all)
	local eMin, eMax = cfg.ElevationMin, cfg.ElevationMax
	if type(eMin) == "number" and type(eMax) == "number" then
		if hi < eMin then
			return eMin, eMin
		elseif lo > eMax then
			return eMax, eMax
		end
		lo, hi = math.max(lo, eMin), math.min(hi, eMax)
	end
	return lo, hi
end

-- Which of `kinds` to launch. With a view pitch, prefer kinds whose natural pitch range lies within
-- KindFitDegrees of the view window (a weather balloon rises from below; seen by a player looking up
-- it would have to be bent into a falling balloon, so a kind that fits is taken instead). When none
-- fits, the closest ones are candidates and plan() bends the lane into view. One rand() either way.
function Hazards.pickKind(cfg: any, kinds: { string }, viewPitch: number?, rand: () -> number): string
	local candidates = kinds
	if viewPitch ~= nil and #kinds > 1 then
		local lo, hi = Hazards.viewWindow(cfg, viewPitch)
		local slack = cfg.KindFitDegrees or 25
		local best, bestGap = {}, math.huge
		for _, name in kinds do
			local k = cfg.Kinds[name]
			local spread = k.pitchSpread or 0
			local gap = math.max((lo - slack) - (k.pitch + spread), (k.pitch - spread) - (hi + slack), 0)
			if gap < bestGap - 1e-9 then
				best, bestGap = { name }, gap
			elseif math.abs(gap - bestGap) <= 1e-9 then
				table.insert(best, name)
			end
		end
		candidates = best
	end
	return candidates[math.min(#candidates, 1 + math.floor(rand() * #candidates))]
end

-- A straight lane toward `aim` from roughly the direction the camera faces.
--   yaw: view heading, forward = (sin yaw, 0, cos yaw)
--   viewPitch (optional, radians, + = up): the start's elevation is kept inside viewWindow().
function Hazards.plan(cfg: any, kindName: string, aim: Vec, yaw: number, rand: () -> number, viewPitch: number?): any
	local k = cfg.Kinds[kindName]
	assert(k ~= nil, "Hazards.plan: unknown kind " .. tostring(kindName))
	local spread = math.rad(cfg.SpreadDegrees or 0)
	local heading = yaw + (rand() * 2 - 1) * spread
	local pitchDeg = k.pitch + (rand() * 2 - 1) * (k.pitchSpread or 0)
	if viewPitch ~= nil then
		local lo, hi = Hazards.viewWindow(cfg, viewPitch)
		pitchDeg = math.clamp(pitchDeg, lo, hi)
	end
	local pitch = math.rad(pitchDeg)
	local jr = (cfg.AimJitter or 0) * rand()
	local ja = rand() * math.pi * 2
	local jitter = v(jr * math.cos(ja), 0, jr * math.sin(ja))
	local target = v(aim.x + jitter.x, aim.y, aim.z + jitter.z)
	-- unit vector from the target back to where the hazard starts
	local dx = math.sin(heading) * math.cos(pitch)
	local dy = math.sin(pitch)
	local dz = math.cos(heading) * math.cos(pitch)
	local dist = k.speed * k.telegraph
	return {
		kind = kindName,
		target = target,
		start = v(target.x + dx * dist, target.y + dy * dist, target.z + dz * dist),
		velocity = v(-dx * k.speed, -dy * k.speed, -dz * k.speed),
		jitter = jitter,
		baseSpeed = k.speed,
		arriveAt = k.telegraph,
		commitAt = k.telegraph - k.commit,
		locked = false,
		duration = k.telegraph + k.pass,
		hitRadius = k.hitRadius,
		knock = k.knock,
		t = 0,
		hit = false,
	}
end

function Hazards.positionAt(plan: any, t: number): Vec
	return v(plan.start.x + plan.velocity.x * t, plan.start.y + plan.velocity.y * t, plan.start.z + plan.velocity.z * t)
end

-- Re-aim an unlocked lane at the player's current position, keeping the hazard where it is and
-- the arrival time where it was. Locks (and returns false) at commitAt, or if following the player
-- would need more than MaxRetargetSpeed x the kind's speed (a teleport, a fall rescue).
function Hazards.retarget(cfg: any, plan: any, aim: Vec): boolean
	if plan.locked then return false end
	if plan.t >= plan.commitAt then
		plan.locked = true
		return false
	end
	local remaining = plan.arriveAt - plan.t
	if remaining <= 0 then
		plan.locked = true
		return false
	end
	local pos = Hazards.positionAt(plan, plan.t)
	local target = v(aim.x + plan.jitter.x, aim.y + plan.jitter.y, aim.z + plan.jitter.z)
	local vel = v((target.x - pos.x) / remaining, (target.y - pos.y) / remaining, (target.z - pos.z) / remaining)
	local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
	if speed > plan.baseSpeed * cfg.MaxRetargetSpeed then
		plan.locked = true
		return false
	end
	plan.velocity = vel
	plan.start = v(pos.x - vel.x * plan.t, pos.y - vel.y * plan.t, pos.z - vel.z * plan.t)
	plan.target = target
	return true
end

-- Distance from point p to segment ab.
function Hazards.segmentDistance(a: Vec, b: Vec, p: Vec): number
	local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
	local len2 = abx * abx + aby * aby + abz * abz
	local s = 0
	if len2 > 0 then
		s = ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / len2
		s = math.clamp(s, 0, 1)
	end
	return Hazards.distance(v(a.x + abx * s, a.y + aby * s, a.z + abz * s), p)
end

-- The ZONE: the circle the client draws as the ring at the player's feet. It is centred where the player
-- stood when the lane last aimed at them (the plan's target without its jitter), so it follows them while
-- the warning tracks and stays put once the lane locks. Radius = the kind's hitRadius + playerRadius.
-- { x, y, z, radius }: y is the aim height (the player's root), the client draws the ring 3 studs lower.
function Hazards.zone(plan: any, playerRadius: number): any
	local j = plan.jitter or v(0, 0, 0)
	return {
		x = plan.target.x - (j.x or 0),
		y = plan.target.y - (j.y or 0),
		z = plan.target.z - (j.z or 0),
		radius = plan.hitRadius + playerRadius,
	}
end

-- Is the player's root inside the zone's circle (horizontal distance only)?
function Hazards.inZone(plan: any, playerPos: Vec, playerRadius: number): boolean
	local z = Hazards.zone(plan, playerRadius)
	local dx, dz = playerPos.x - z.x, playerPos.z - z.z
	return dx * dx + dz * dz <= z.radius * z.radius
end

-- Swept hit test over flight time [t0, t1], clipped to the flight. A hazard hits once.
-- A hit needs BOTH: the player inside the zone (the ring the client draws) and the hazard passing within
-- hitRadius + playerRadius of them. Review 2026-09-17 round 2: with the flight alone, the danger was a
-- corridor along the whole lane, so backing away or stepping out of the drawn ring along the lane was
-- still a hit and only a step at right angles dodged. Now stepping out of the ring in any direction
-- dodges, and what the player sees is exactly what hits.
function Hazards.checkHit(plan: any, t0: number, t1: number, playerPos: Vec, playerRadius: number): boolean
	if plan.hit then return false end
	if not Hazards.inZone(plan, playerPos, playerRadius) then return false end
	local a0 = math.max(0, t0)
	local a1 = math.min(plan.duration, t1)
	if a1 < a0 then return false end
	local d = Hazards.segmentDistance(Hazards.positionAt(plan, a0), Hazards.positionAt(plan, a1), playerPos)
	return d <= plan.hitRadius + playerRadius
end

-- One frame. Returns nil or an event { type = "spawn" | "done" | "skip", plan = ... }.
--   ctx = { resting: boolean, paused: boolean?, held: boolean?, grounded: boolean, kinds: { string },
--           aim: Vec?, yaw: number, pitch: number (camera pitch, radians, + = looking up; nil is level) }
function Hazards.step(state: any, cfg: any, dt: number, ctx: any, rand: () -> number): any
	if state.active then
		local plan = state.active
		plan.t += dt
		if plan.t >= plan.duration then
			state.active = nil
			return { type = "done", plan = plan }
		end
		if ctx.aim ~= nil then
			Hazards.retarget(cfg, plan, ctx.aim)
		end
	end
	if not ctx.resting and not ctx.paused then
		state.clock += dt
	end
	if state.active ~= nil or state.clock < state.nextAt then
		return nil
	end
	local kinds = ctx.kinds or {}
	if #kinds == 0 then
		-- quiet band: re-roll instead of holding a due hazard for the next band (no backlog burst)
		state.nextAt = state.clock + Hazards.rollInterval(cfg, rand)
		return { type = "skip" }
	end
	-- held (review 4): the clock above kept running, but a due hazard waits; it is neither dropped nor re-rolled
	if ctx.resting or ctx.paused or ctx.held or not ctx.grounded or ctx.aim == nil then
		return nil
	end
	local viewPitch = ctx.pitch or 0
	local kind = Hazards.pickKind(cfg, kinds, viewPitch, rand)
	local plan = Hazards.plan(cfg, kind, ctx.aim, ctx.yaw or 0, rand, viewPitch)
	state.active = plan
	state.spawned += 1
	state.nextAt = state.clock + Hazards.rollInterval(cfg, rand)
	return { type = "spawn", plan = plan }
end

-- Call off the hazard in flight: no hit, no knock, and the schedule untouched (so cancelling can never be
-- used to thin hazards out). Returns the plan that was called off, or nil.
function Hazards.cancel(state: any): any
	local plan = state.active
	state.active = nil
	return plan
end

-- Knock velocity for a hit player: horizontal, away from the lane, |h| = plan.knock, lift capped.
function Hazards.knockVelocity(cfg: any, plan: any, playerPos: Vec): Vec
	local vel = plan.velocity
	local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
	local ux, uy, uz = 0, 0, 0
	if speed > 0 then ux, uy, uz = vel.x / speed, vel.y / speed, vel.z / speed end
	local here = Hazards.positionAt(plan, plan.t or 0)
	local rx, ry, rz = playerPos.x - here.x, playerPos.y - here.y, playerPos.z - here.z
	local along = rx * ux + ry * uy + rz * uz
	-- perpendicular offset from the lane, flattened to the ground plane
	local ax, az = rx - ux * along, rz - uz * along
	local len = math.sqrt(ax * ax + az * az)
	if len < 0.05 then
		ax, az = ux, uz
		len = math.sqrt(ax * ax + az * az)
		if len < 1e-6 then
			ax, az, len = 1, 0, 1 -- a perfectly vertical lane dead-centre: any horizontal push will do
		end
	end
	local lift = math.min(cfg.KnockLift or 0, Hazards.MAX_KNOCK_LIFT)
	return v(ax / len * plan.knock, lift, az / len * plan.knock)
end

-- Where is `target` relative to a camera, in the ground plane: "ahead" | "left" | "right" | "behind".
function Hazards.bearing(camPos: Vec, look: Vec, target: Vec): string
	local fx, fz = look.x, look.z
	local fl = math.sqrt(fx * fx + fz * fz)
	local tx, tz = target.x - camPos.x, target.z - camPos.z
	local tl = math.sqrt(tx * tx + tz * tz)
	if fl < 1e-6 or tl < 1e-6 then return "ahead" end
	fx, fz, tx, tz = fx / fl, fz / fl, tx / tl, tz / tl
	local dot = fx * tx + fz * tz
	local cross = fx * tz - fz * tx
	local ang = math.deg(math.atan2(cross, dot))
	if math.abs(ang) <= 35 then return "ahead" end
	if math.abs(ang) >= 145 then return "behind" end
	return if ang > 0 then "right" else "left"
end

return Hazards
