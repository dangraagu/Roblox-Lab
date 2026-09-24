--!strict
-- Hazards.luau — rare, telegraphed, one-at-a-time ENVIRONMENTAL hazards for FACILITY. Pure.
--
-- Adapted from plus1-jump/src/shared/Hazards.luau. Kept from the template:
--   * WHEN: a clock that runs only while the player is exposed to hazards (on a sublevel, in a LIT
--     room whose band has hazards, not resting) and FREEZES otherwise — it is never reset, so walking
--     in and out of a dark room cannot thin hazards out. One hazard every IntervalMin..IntervalMax
--     seconds of that time, never two at once. A due hazard waits for a legal spot; it never piles up.
--   * THE ZONE RULE: the ring the client draws is exactly what hits. A hit needs the player inside the
--     zone while the hazard bursts; stepping out of the ring in any direction dodges.
-- Different in FACILITY: nothing flies. A hazard comes down from the ceiling (a leak, an arcing cable,
-- a burst pipe, a steam valve, a spore pod, a rift) onto the spot the player stood on when it started,
-- so the zone is a fixed circle on one room's floor. It only starts on a LEGAL spot: the room's interior
-- (at least SpotMinWallDistance off every wall, so never in a doorway and never able to push anyone
-- through one) and off the car's or lift's pad. A room that starts to flicker calls its hazard off: the
-- dark is the game's threat and its 2 s warning outranks everything; a hazard never adds to it.
--
-- What it does NOT do: build Parts, read Roblox, grant or remove anything. Vectors are plain
-- { x, y, z } tables, rooms are opaque ids, randomness is an injected rand(): [0, 1).

local Hazards = {}

-- A hazard is a stagger, never a launch: a horizontal shove and at most a hop.
Hazards.MAX_KNOCK = 30
Hazards.MAX_LIFT = 4

type Vec = { x: number, y: number, z: number }

function Hazards.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no hazard config" end
	local function num(v: any): boolean
		return type(v) == "number" and v == v
	end
	if not num(cfg.IntervalMin) or cfg.IntervalMin <= 0 then return false, "IntervalMin must be > 0" end
	if not num(cfg.IntervalMax) or cfg.IntervalMax < cfg.IntervalMin then return false, "IntervalMax must be >= IntervalMin" end
	if not num(cfg.MinTelegraphSeconds) or cfg.MinTelegraphSeconds <= 0 then return false, "MinTelegraphSeconds must be > 0" end
	if not num(cfg.ReactionSeconds) or cfg.ReactionSeconds < 0 then return false, "ReactionSeconds must be >= 0" end
	if not num(cfg.PlayerRadius) or cfg.PlayerRadius <= 0 then return false, "PlayerRadius must be > 0" end
	if not num(cfg.EscapeSpeed) or cfg.EscapeSpeed <= 0 then return false, "EscapeSpeed must be > 0" end
	if not num(cfg.SpotMinWallDistance) or cfg.SpotMinWallDistance <= 0 then return false, "SpotMinWallDistance must be > 0" end
	if not num(cfg.PadKeepOut) or cfg.PadKeepOut < 0 then return false, "PadKeepOut must be >= 0" end
	if not num(cfg.FixtureKeepOut) or cfg.FixtureKeepOut < 0 then return false, "FixtureKeepOut must be >= 0" end
	if not num(cfg.ArrivalGraceSeconds) or cfg.ArrivalGraceSeconds < 0 then return false, "ArrivalGraceSeconds must be >= 0" end
	if type(cfg.Kinds) ~= "table" then return false, "no Kinds" end
	for name, k in cfg.Kinds do
		local function bad(why: string): (boolean, string?)
			return false, "hazard kind " .. tostring(name) .. ": " .. why
		end
		if not num(k.telegraph) or k.telegraph < cfg.MinTelegraphSeconds then
			return bad("telegraph shorter than MinTelegraphSeconds")
		end
		if not num(k.burst) or k.burst <= 0 then return bad("burst must be > 0") end
		if not num(k.hitRadius) or k.hitRadius <= 0 then return bad("hitRadius must be > 0") end
		local radius = k.hitRadius + cfg.PlayerRadius
		if radius > cfg.SpotMinWallDistance - 1 then
			return bad("the zone (" .. radius .. ") would reach within a stud of a wall, and a doorway is in every wall")
		end
		if k.telegraph < cfg.ReactionSeconds + radius / cfg.EscapeSpeed then
			return bad("the warning is too short to escape: react in " .. cfg.ReactionSeconds .. " s and walk "
				.. radius .. " studs at " .. cfg.EscapeSpeed .. " studs/s")
		end
		if not num(k.knock) or k.knock < 0 or k.knock > Hazards.MAX_KNOCK then
			return bad("knock must be within 0.." .. Hazards.MAX_KNOCK)
		end
		local lift = k.lift or 0
		if not num(lift) or lift < 0 or lift > Hazards.MAX_LIFT then
			return bad("lift must be within 0.." .. Hazards.MAX_LIFT)
		end
	end
	return true, nil
end

function Hazards.rollInterval(cfg: any, rand: () -> number): number
	return cfg.IntervalMin + (cfg.IntervalMax - cfg.IntervalMin) * rand()
end

-- May a hazard start `secondsOnFloor` after the player arrived on this sublevel (nil: not on one)? The
-- clock carries over between sublevels, so a hazard can fall due while the player stands on the powered
-- lift's pad at the choice (no hazard starts on a pad). It then waits, and without a grace it came the
-- moment the player stepped off the next sublevel's car, over THE POWER IS FAILING (the dark's own warning,
-- shown on arrival) and the arrival hint. Callers treat a floor
-- inside the grace as not eligible: the clock freezes there, as everywhere else a hazard may not start.
function Hazards.arrivalOk(cfg: any, secondsOnFloor: number?): boolean
	if type(secondsOnFloor) ~= "number" then return false end
	return secondsOnFloor >= cfg.ArrivalGraceSeconds - 1e-9
end

-- clock: exposed seconds so far. nextAt: exposed second of the next launch. active: the plan in play.
function Hazards.newScheduler(cfg: any, rand: () -> number): any
	return { clock = 0, nextAt = Hazards.rollInterval(cfg, rand), active = nil, spawned = 0 }
end

-- Is a room-local point (floor-top origin at the room's centre) a legal spot? `inner` is the distance
-- from the room's centre to a wall's inner face. `hasPad`: the room holds the entry car or the exit
-- lift (both visible on the client the moment the room is), whose roof would be in the way. Every room
-- has its light fixture in the middle of the ceiling, so nothing comes down from there either.
function Hazards.spotOk(cfg: any, inner: number, lx: number, lz: number, hasPad: boolean): boolean
	local lim = inner - cfg.SpotMinWallDistance
	if math.abs(lx) > lim + 1e-9 or math.abs(lz) > lim + 1e-9 then
		return false
	end
	local keep = if hasPad then cfg.PadKeepOut else cfg.FixtureKeepOut
	if math.abs(lx) <= keep and math.abs(lz) <= keep then
		return false
	end
	return true
end

function Hazards.plan(cfg: any, kindName: string, spot: Vec, room: any): any
	local k = cfg.Kinds[kindName]
	assert(k ~= nil, "Hazards.plan: unknown kind " .. tostring(kindName))
	return {
		kind = kindName,
		room = room,
		x = spot.x,
		y = spot.y,
		z = spot.z,
		hitRadius = k.hitRadius,
		radius = k.hitRadius + cfg.PlayerRadius,
		burstAt = k.telegraph,
		endsAt = k.telegraph + k.burst,
		knock = k.knock,
		lift = k.lift or 0,
		t = 0,
		hit = false,
	}
end

-- "warn" before the burst, "burst" during it, "after" once it is over.
function Hazards.phase(plan: any, t: number?): string
	local now = t or plan.t
	if now < plan.burstAt - 1e-9 then return "warn" end
	if now < plan.endsAt - 1e-9 then return "burst" end
	return "after"
end

-- Horizontal distance only: it comes down on you whether you are jumping or not.
function Hazards.inZone(plan: any, pos: Vec): boolean
	local dx, dz = pos.x - plan.x, pos.z - plan.z
	return dx * dx + dz * dz <= plan.radius * plan.radius
end

-- Did the burst catch the player in (t0, t1]? Once per hazard, same room only, inside the zone.
function Hazards.checkHit(plan: any, t0: number, t1: number, pos: Vec, sameRoom: boolean): boolean
	if plan.hit or not sameRoom then return false end
	if t1 < plan.burstAt - 1e-9 or t0 > plan.endsAt + 1e-9 then return false end
	return Hazards.inZone(plan, pos)
end

-- One frame. Returns nil or { type = "spawn" | "burst" | "done" | "cancel", plan }.
--   ctx = { eligible: boolean (on a sublevel, in a lit room, not resting), kinds: { string } (the kinds of
--           the band dressing the room the player is in), spot: Vec? (where the player stands when that
--           is a legal spot, else nil), room: any, activeRoomLit: boolean? (false = the active hazard's
--           room has started to flicker or is dark) }
function Hazards.step(state: any, cfg: any, dt: number, ctx: any, rand: () -> number): any
	local ev = nil
	local plan = state.active
	if plan then
		if ctx.activeRoomLit == false then
			state.active = nil
			return { type = "cancel", plan = plan }
		end
		local before = plan.t
		plan.t += dt
		if before < plan.burstAt and plan.t >= plan.burstAt then
			ev = { type = "burst", plan = plan }
		elseif plan.t >= plan.endsAt then
			state.active = nil
			ev = { type = "done", plan = plan }
		end
	end
	local kinds = ctx.kinds or {}
	if ctx.eligible and #kinds > 0 then
		state.clock += dt
	end
	if ev ~= nil or state.active ~= nil or state.clock < state.nextAt then
		return ev
	end
	if not ctx.eligible or #kinds == 0 or ctx.spot == nil then
		return nil -- due, and it waits: exactly one launches at the next legal moment
	end
	local kind = kinds[math.clamp(1 + math.floor(rand() * #kinds), 1, #kinds)]
	local newPlan = Hazards.plan(cfg, kind, ctx.spot, ctx.room)
	state.active = newPlan
	state.spawned += 1
	state.nextAt = state.clock + Hazards.rollInterval(cfg, rand)
	return { type = "spawn", plan = newPlan }
end

-- The shove for a hit player: horizontal, away from the zone's centre, |h| = plan.knock (capped); at
-- the very centre it goes along `fallback` (the caller passes "backwards" for the camera).
function Hazards.knockVelocity(cfg: any, plan: any, pos: Vec, fallback: Vec): Vec
	local dx, dz = pos.x - plan.x, pos.z - plan.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.3 then
		dx, dz = fallback.x, fallback.z
		len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-6 then
			dx, dz, len = 1, 0, 1
		end
	end
	local mag = math.min(plan.knock, Hazards.MAX_KNOCK)
	local lift = math.min(plan.lift or 0, Hazards.MAX_LIFT)
	return { x = dx / len * mag, y = lift, z = dz / len * mag }
end

return Hazards
