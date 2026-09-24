--!strict
-- Hazards.luau (VAULT EDITION) — rare, telegraphed, one-at-a-time DROPS. Pure, no Roblox.
--
-- ADAPTED FROM +1 JUMP'S TEMPLATE (plus1-jump/src/shared/Hazards.luau, review round 2). Kept as the
-- template has them: the scheduler (a clock that only runs while the player plays, frozen and never
-- reset while paused, one hazard in the air at a time, a due hazard HELD while the player stands
-- somewhere it must not fire, a quiet band re-rolled instead of bursting later), the ZONE rule (the
-- ring the client draws IS the danger: stepping out of it in any direction dodges) and the capped
-- knock. What changed is the FLIGHT, and why:
--
--   +1 Jump is open sky, so a hazard flies a straight lane in from wherever the camera looks. A vault
--   storey is a maze of 12-stud corridors with walls on every side and the next storey's floor 16
--   studs overhead: a lane would fly through the walls. So a vault hazard is a CHUNK OF CEILING. It
--   hangs `dropHeight` above the player, and while the warning runs the ring under their feet
--   follows them (the ceiling is visibly cracking where they stand). `commit` seconds before it
--   lands it LOCKS, and in its last `fall` seconds it drops. A player who keeps running is never
--   under it when it lands; a player who stopped to read the maze gets `commit` seconds of
--   "MOVE!" to step out of a ring a few studs wide.
--
-- The GAME decides where a drop may land (VaultEnv.hazardEligible: never in the climb shaft, never
-- near the hole in the floor, never in the first seconds of a run or the last before the seal); this
-- module only honours it: `eligible = false` holds a due drop, and a warning already running LOCKS
-- where the player last stood eligible instead of following them into the shaft.
--
-- It builds no Parts, reads no Roblox, grants and removes nothing. Vectors are { x, y, z } tables,
-- randomness is an injected rand() in [0, 1). Like every module in src/shared it requires NOTHING.

local Hazards = {}

-- A hazard is a nudge, never a launch pad. Configs asking for more lift are rejected.
Hazards.MAX_KNOCK_LIFT = 15

type Vec = { x: number, y: number, z: number }

local function v(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end

local function num(x: any): boolean
	return type(x) == "number" and x == x
end

function Hazards.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no hazard config" end
	if not num(cfg.IntervalMin) or cfg.IntervalMin <= 0 then return false, "IntervalMin must be > 0" end
	if not num(cfg.IntervalMax) or cfg.IntervalMax < cfg.IntervalMin then
		return false, "IntervalMax must be >= IntervalMin"
	end
	if not num(cfg.MinTelegraphSeconds) or cfg.MinTelegraphSeconds <= 0 then
		return false, "MinTelegraphSeconds must be > 0"
	end
	if not num(cfg.MinCommitSeconds) or cfg.MinCommitSeconds <= 0 then
		return false, "MinCommitSeconds must be > 0"
	end
	if not num(cfg.MaxTrackSpeed) or cfg.MaxTrackSpeed <= 0 then return false, "MaxTrackSpeed must be > 0" end
	if not num(cfg.PlayerRadius) or cfg.PlayerRadius <= 0 then
		return false, "PlayerRadius must be > 0: the ring is hitRadius + PlayerRadius, and the rule reads the same number"
	end
	if not num(cfg.MaxKnock) or cfg.MaxKnock <= 0 then return false, "MaxKnock must be > 0" end
	local lift = cfg.KnockLift or 0
	if not num(lift) or lift < 0 or lift > Hazards.MAX_KNOCK_LIFT then
		return false, "KnockLift must be within 0.." .. Hazards.MAX_KNOCK_LIFT
	end
	if type(cfg.Kinds) ~= "table" then return false, "no Kinds" end
	for name, k in cfg.Kinds do
		local function bad(why: string): (boolean, string?)
			return false, "hazard kind " .. tostring(name) .. ": " .. why
		end
		if not num(k.telegraph) or k.telegraph < cfg.MinTelegraphSeconds then
			return bad("telegraph shorter than MinTelegraphSeconds (it must be easy to see coming)")
		end
		if not num(k.commit) or k.commit < cfg.MinCommitSeconds then
			return bad("commit shorter than MinCommitSeconds (no time to step out of the locked ring)")
		end
		if k.commit > k.telegraph then return bad("commit longer than telegraph") end
		if not num(k.fall) or k.fall <= 0 then return bad("fall must be > 0") end
		if k.fall >= k.commit then
			return bad("fall must be shorter than commit: the chunk may only drop once the ring has stopped following")
		end
		if not num(k.pass) or k.pass <= 0 then return bad("pass must be > 0") end
		if not num(k.hitRadius) or k.hitRadius <= 0 then return bad("hitRadius must be > 0") end
		if not num(k.dropHeight) or k.dropHeight <= 0 then return bad("dropHeight must be > 0") end
		if not num(k.reach) or k.reach <= 0 then
			return bad("reach must be > 0: without it a chunk on this storey could hit a player on the next")
		end
		if not num(k.knock) or k.knock < 0 or k.knock > cfg.MaxKnock then
			return bad("knock must be within 0..MaxKnock")
		end
	end
	return true, nil
end

function Hazards.rollInterval(cfg: any, rand: () -> number): number
	return cfg.IntervalMin + (cfg.IntervalMax - cfg.IntervalMin) * rand()
end

-- clock: seconds of RUN time so far (frozen while paused). nextAt: run second of the next drop.
function Hazards.newScheduler(cfg: any, rand: () -> number): any
	return { clock = 0, nextAt = Hazards.rollInterval(cfg, rand), active = nil, spawned = 0 }
end

-- A drop aimed at `aim` (the player's root). The landing point carries a small horizontal jitter so
-- two drops never look pasted; the ZONE is centred on the aim without it (Hazards.zone).
function Hazards.plan(cfg: any, kindName: string, aim: Vec, rand: () -> number): any
	local k = cfg.Kinds[kindName]
	assert(k ~= nil, "Hazards.plan: unknown kind " .. tostring(kindName))
	local jr = (cfg.AimJitter or 0) * rand()
	local ja = rand() * math.pi * 2
	local jitter = v(jr * math.cos(ja), 0, jr * math.sin(ja))
	return {
		kind = kindName,
		target = v(aim.x + jitter.x, aim.y, aim.z + jitter.z),
		jitter = jitter,
		dropHeight = k.dropHeight,
		arriveAt = k.telegraph,
		commitAt = k.telegraph - k.commit,
		fallAt = k.telegraph - k.fall,
		duration = k.telegraph + k.pass,
		hitRadius = k.hitRadius,
		reach = k.reach,
		knock = k.knock,
		locked = false,
		t = 0,
		hit = false,
	}
end

-- Hangs dropHeight above the landing point until fallAt, then falls (accelerating, as a dropped
-- thing does) to reach it exactly at arriveAt, and lies there afterwards.
function Hazards.positionAt(plan: any, t: number): Vec
	local tg = plan.target
	if t <= plan.fallAt then
		return v(tg.x, tg.y + plan.dropHeight, tg.z)
	end
	if t >= plan.arriveAt then
		return v(tg.x, tg.y, tg.z)
	end
	local u = (t - plan.fallAt) / (plan.arriveAt - plan.fallAt)
	return v(tg.x, tg.y + plan.dropHeight * (1 - u * u), tg.z)
end

-- Follow the player while the warning runs. Returns true when it followed; false (and LOCKED) at
-- commitAt, when there is no aim (the player went where a drop must not land), or when following
-- would move the ring faster than MaxTrackSpeed (a teleport, a fall down the shaft). The landing
-- time never moves, so the warning never shortens.
function Hazards.retarget(cfg: any, plan: any, aim: Vec?, dt: number): boolean
	if plan.locked then return false end
	if plan.t >= plan.commitAt or aim == nil then
		plan.locked = true
		return false
	end
	local cx, cz = plan.target.x - plan.jitter.x, plan.target.z - plan.jitter.z
	local dx, dz = aim.x - cx, aim.z - cz
	if math.sqrt(dx * dx + dz * dz) > cfg.MaxTrackSpeed * math.max(dt, 1 / 240) then
		plan.locked = true
		return false
	end
	plan.target = v(aim.x + plan.jitter.x, aim.y, aim.z + plan.jitter.z)
	return true
end

-- The ZONE: the circle the client draws as the ring at the player's feet, centred where the player
-- stood when the drop last followed them (the landing point without its jitter).
function Hazards.zone(plan: any, playerRadius: number): any
	local j = plan.jitter or v(0, 0, 0)
	return {
		x = plan.target.x - (j.x or 0),
		y = plan.target.y,
		z = plan.target.z - (j.z or 0),
		radius = plan.hitRadius + playerRadius,
	}
end

function Hazards.inZone(plan: any, playerPos: Vec, playerRadius: number): boolean
	local z = Hazards.zone(plan, playerRadius)
	local dx, dz = playerPos.x - z.x, playerPos.z - z.z
	return dx * dx + dz * dz <= z.radius * z.radius
end

-- Did the drop hit during flight time (t0, t1]? Only the frame that contains the landing can hit,
-- only a player inside the zone, and only one within `reach` of the landing height (the same
-- storey). A drop hits once; walking into its ring after it landed is harmless.
function Hazards.checkHit(plan: any, t0: number, t1: number, playerPos: Vec, playerRadius: number): boolean
	if plan.hit then return false end
	if not (t0 < plan.arriveAt and t1 >= plan.arriveAt) then return false end
	if math.abs(playerPos.y - plan.target.y) > plan.reach then return false end
	return Hazards.inZone(plan, playerPos, playerRadius)
end

-- One frame. Returns nil or { type = "spawn" | "done" | "skip", plan }.
--   ctx = { paused: boolean, eligible: boolean, kinds: { string }, aim: Vec? }
--   paused   = no run is going (the hub): the clock is frozen and nothing launches.
--   eligible = the game says a drop may land where the player is (VaultEnv.hazardEligible).
function Hazards.step(state: any, cfg: any, dt: number, ctx: any, rand: () -> number): any
	if state.active then
		local plan = state.active
		plan.t += dt
		if plan.t >= plan.duration then
			state.active = nil
			return { type = "done", plan = plan }
		end
		Hazards.retarget(cfg, plan, if ctx.eligible then ctx.aim else nil, dt)
	end
	if not ctx.paused then
		state.clock += dt
	end
	if state.active ~= nil or state.clock < state.nextAt then
		return nil
	end
	local kinds = ctx.kinds or {}
	if #kinds == 0 then
		state.nextAt = state.clock + Hazards.rollInterval(cfg, rand)
		return { type = "skip" }
	end
	if ctx.paused or not ctx.eligible or ctx.aim == nil then
		return nil
	end
	local kind = kinds[math.min(#kinds, 1 + math.floor(rand() * #kinds))]
	local plan = Hazards.plan(cfg, kind, ctx.aim, rand)
	state.active = plan
	state.spawned += 1
	state.nextAt = state.clock + Hazards.rollInterval(cfg, rand)
	return { type = "spawn", plan = plan }
end

-- The run ended (escape, collapse, reset): take the drop out of the air. The clock is untouched.
function Hazards.cancel(state: any): any
	local plan = state.active
	state.active = nil
	return plan
end

-- Knock velocity for a hit player: horizontal, away from where the chunk landed, |h| = plan.knock,
-- lift capped. Dead centre uses `away` (a horizontal unit vector, e.g. the way the player faces,
-- reversed), or +x when none is given.
function Hazards.knockVelocity(cfg: any, plan: any, playerPos: Vec, away: Vec?): Vec
	local z = Hazards.zone(plan, 0)
	local ax, az = playerPos.x - z.x, playerPos.z - z.z
	local len = math.sqrt(ax * ax + az * az)
	if len < 0.05 then
		if away ~= nil then
			ax, az = away.x, away.z
			len = math.sqrt(ax * ax + az * az)
		end
		if len < 1e-6 then
			ax, az, len = 1, 0, 1
		end
	end
	local lift = math.min(cfg.KnockLift or 0, Hazards.MAX_KNOCK_LIFT)
	return v(ax / len * plan.knock, lift, az / len * plan.knock)
end

return Hazards
