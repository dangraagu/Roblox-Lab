--!strict
-- Watcher.luau — the Nightwatcher's movement, sight and hunt state. PURE LOGIC on plain
-- numbers: no Vector3, no Roblox globals, config passed in as an argument. The server owns the
-- Model and just copies `state.x / state.z / state.fx / state.fz` onto a CFrame every heartbeat.
--
-- No pathfinding AI and no netcode, per the brief. Two behaviours only:
--   PATROL — walk a fixed route of room centres, there and back, forever.
--   HUNT   — having SEEN you, walk straight at a target the server picks (the centre of the
--            next room along Manor.pathBetween), until the hunt timer runs out.
-- Sight is a cone AND a room test the server supplies, so walls block it without a raycast.
--
-- As with every module in src/shared, nothing is `require`d here: a bare `require("./X")`
-- resolves in the luau CLI and is INVALID in Roblox.
export type Point = { x: number, z: number }
export type State = {
	mode: string, -- "PATROL" | "HUNT"
	dist: number, -- how far along the closed route it is, in studs
	x: number,
	z: number,
	fx: number, -- unit facing
	fz: number,
	huntLeft: number, -- seconds of hunt remaining
}
export type StepCtx = {
	cfg: any,
	points: { Point },
	dread: number?,
	watcherSlow: number?,
	spotted: boolean?,
	target: Point?,
}

local Watcher = {}

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- ------------------------------------------------------------------ the route

-- Turn a one-way list of waypoints into a CLOSED loop by walking it back again (1,2,3 -> 1,2,3,2).
-- Without this the watcher would teleport from the far end of the route to the near end every lap.
function Watcher.loopPoints(points: { Point }): { Point }
	local out: { Point } = {}
	for _, p in points do
		table.insert(out, { x = p.x, z = p.z })
	end
	if #points <= 2 then
		return out
	end
	for i = #points - 1, 2, -1 do
		table.insert(out, { x = points[i].x, z = points[i].z })
	end
	return out
end

-- Total length of the CLOSED loop (the last point connects back to the first).
function Watcher.pathLength(points: { Point }): number
	local n = #points
	if n < 2 then
		return 0
	end
	local total = 0
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		total += math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	end
	return total
end

-- Position and unit facing at `dist` studs along the closed loop. Distance wraps in BOTH
-- directions, so no caller has to remember to normalise it first.
function Watcher.positionAt(points: { Point }, dist: number): (number, number, number, number)
	local n = #points
	if n == 0 then
		return 0, 0, 1, 0
	end
	local total = Watcher.pathLength(points)
	if n < 2 or total <= 0 then
		return points[1].x, points[1].z, 1, 0
	end
	local d = dist % total
	if d < 0 then
		d += total
	end
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0 then
			if d <= len then
				local t = d / len
				return a.x + dx * t, a.z + dz * t, dx / len, dz / len
			end
			d -= len
		end
	end
	local last = points[n]
	return last.x, last.z, 1, 0
end

-- Distance along the loop of the point on the route CLOSEST to (x, z). Used to rejoin the
-- patrol after a hunt without snapping back to wherever the watcher left it.
function Watcher.nearestDist(points: { Point }, x: number, z: number): number
	local n = #points
	if n < 2 then
		return 0
	end
	local acc, bestD, bestAt = 0, math.huge, 0
	for i = 1, n do
		local a = points[i]
		local b = points[(i % n) + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 0 then
			t = clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1)
		end
		local px, pz = a.x + dx * t, a.z + dz * t
		local d2 = (x - px) ^ 2 + (z - pz) ^ 2
		if d2 < bestD then
			bestD = d2
			bestAt = acc + t * math.sqrt(len2)
		end
		acc += math.sqrt(len2)
	end
	return bestAt
end

-- ------------------------------------------------------------------ dread and speed

-- How awake the manor is, 0..1. A zero-length night reads as fully awake rather than dividing
-- by zero — a config typo should throw the player out, not produce a nan the HUD renders.
function Watcher.dread(elapsed: number, total: number): number
	if total <= 0 then
		return 1
	end
	return clamp(elapsed / total, 0, 1)
end

-- Studs per second. Never returns zero or less: an upgrade stack that froze the watcher solid
-- would delete the only threat in the game, so the slow is capped and then floored.
function Watcher.speed(cfg: any, dread: number, watcherSlow: number, hunting: boolean): number
	local W = cfg.Watcher
	local s = (W.BaseSpeed + W.SpeedPerDread * clamp(dread, 0, 1)) * (1 - clamp(watcherSlow, 0, 1))
	if hunting then
		s *= W.HuntSpeedMul
	end
	local floor = W.BaseSpeed * 0.15
	if s < floor then
		s = floor
	end
	return s
end

-- ------------------------------------------------------------------ sight

-- Inside the view cone and inside SightRange. Point blank is always seen; a zero facing vector
-- (it has not moved yet) sees NOTHING at range rather than everything, which is what a naive
-- unnormalised dot product would do.
function Watcher.sees(cfg: any, wx: number, wz: number, fx: number, fz: number, px: number, pz: number): boolean
	local W = cfg.Watcher
	local dx, dz = px - wx, pz - wz
	local d2 = dx * dx + dz * dz
	if d2 > W.SightRange * W.SightRange then
		return false
	end
	if d2 <= 1e-12 then
		return true
	end
	local fl = math.sqrt(fx * fx + fz * fz)
	if fl <= 1e-9 then
		return false
	end
	local dot = (dx * fx + dz * fz) / (math.sqrt(d2) * fl)
	return dot >= math.cos(math.rad(W.SightHalfAngleDeg))
end

-- Sight AND the room rule. `roomOk` is supplied by the server: true when the player is in the
-- watcher's room or a room linked to it. That is what makes a wall block line of sight, with
-- no raycast and nothing the emulator cannot model.
function Watcher.spots(cfg: any, wx: number, wz: number, fx: number, fz: number, px: number, pz: number, roomOk: boolean): boolean
	return roomOk and Watcher.sees(cfg, wx, wz, fx, fz, px, pz)
end

-- The Alarm Bell. Distinct from sight on purpose: this is what the BELL notices, so it works
-- through walls, ignores facing, and — with no bell bought (warnRange 0 or less) — never fires.
-- An upgrade whose first level grants something the player already had is an upgrade that does
-- nothing, which is worse than one that is missing.
function Watcher.hears(warnRange: number, wx: number, wz: number, px: number, pz: number): boolean
	if warnRange <= 0 then
		return false
	end
	return (px - wx) ^ 2 + (pz - wz) ^ 2 <= warnRange * warnRange
end

-- Close enough to take your bag. Deliberately independent of facing: being grabbed from behind
-- is the genre.
function Watcher.caught(cfg: any, wx: number, wz: number, px: number, pz: number): boolean
	local r = cfg.Watcher.CatchRadius
	return (px - wx) ^ 2 + (pz - wz) ^ 2 <= r * r
end

-- ------------------------------------------------------------------ the state machine

function Watcher.newState(points: { Point }): State
	local x, z, fx, fz = Watcher.positionAt(points, 0)
	return { mode = "PATROL", dist = 0, x = x, z = z, fx = fx, fz = fz, huntLeft = 0 }
end

-- Advance `state` by `dt` seconds. MUTATES and returns the same table (the server keeps one
-- per player and calls this every heartbeat).
--
-- Being spotted refreshes the hunt timer rather than stacking hunts. When the timer runs out
-- the watcher rejoins its route at the NEAREST point, so it never teleports back to where it
-- was standing when it first saw you.
function Watcher.step(state: State, dt: number, ctx: StepCtx): State
	local cfg, points = ctx.cfg, ctx.points

	if ctx.spotted then
		state.mode = "HUNT"
		state.huntLeft = cfg.Watcher.HuntSeconds
	elseif state.mode == "HUNT" then
		state.huntLeft = math.max(state.huntLeft - dt, 0)
		if state.huntLeft <= 0 then
			state.mode = "PATROL"
			state.dist = Watcher.nearestDist(points, state.x, state.z)
		end
	end

	local speed = Watcher.speed(cfg, ctx.dread or 0, ctx.watcherSlow or 0, state.mode == "HUNT")
	local stepDist = speed * dt

	if state.mode == "HUNT" then
		local tx, tz
		if ctx.target then
			tx, tz = ctx.target.x, ctx.target.z
		else
			-- No target this frame (the server lost track of which room you are in). Keep
			-- walking the way it was already facing rather than freezing mid-hall.
			tx, tz = state.x + state.fx * math.max(stepDist, 1), state.z + state.fz * math.max(stepDist, 1)
		end
		local dx, dz = tx - state.x, tz - state.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1e-9 then
			state.fx, state.fz = dx / d, dz / d
			if stepDist >= d then
				state.x, state.z = tx, tz -- arrive exactly; never orbit the target
			else
				state.x += state.fx * stepDist
				state.z += state.fz * stepDist
			end
		end
	else
		local total = Watcher.pathLength(points)
		state.dist += stepDist
		if total > 0 then
			state.dist %= total
		end
		local x, z, fx, fz = Watcher.positionAt(points, state.dist)
		state.x, state.z, state.fx, state.fz = x, z, fx, fz
	end

	return state
end

return Watcher
