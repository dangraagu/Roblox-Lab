--!strict
-- Trace2D.luau - where the SERVER thinks a raider is. Pure logic, pocket-local XZ studs.
--
-- Adapted from vault-runners/src/shared/Trace.luau, in 2D with walls (DESIGN.md section 5, "The
-- trusted position"). In Roblox the client owns its character's physics, so the root position the
-- server reads is a CLAIM. This module does not try to detect cheating; it removes what cheating
-- is worth. Each tick:
--   1. allowance = speed x TrustedSpeedFactor x min(dt, MaxTrustedTickSeconds). NOTHING carries over
--      from one tick to the next. DESIGN.md had a 0.5 s bank (10.8 studs saved up by standing still);
--      REVIEW-1 R1-4 measured it crossing a net the tick after it was painted ON, uncaught 4 of 4
--      times: Heist.caught times a tick's segment over that tick, so a 10.8-stud segment spends
--      0.056 s inside a 6-stud net, all of it inside the 0.2 s latency grace. With no bank, no
--      segment is faster than the cap. A server hitch still credits at most 0.5 s, and that
--      segment is timed over the whole hitch, so its speed stays under the cap too;
--   2. move toward the claim in a straight line by at most the allowance;
--   3. if that segment leaves the walkable map, stop at the boundary, then SLIDE along it with what
--      is left of the allowance: along each axis in turn, toward the claim's coordinate on that axis,
--      stopping at the map's edge again. No route is planned: a slide only ever follows the wall the
--      position is pressed against, which is what a body in the engine does.
--      REVIEW-1.md B1: without the slide, a replication freeze of about half a second while an
--      honest raider turned into a fence gap left the trusted position on the fence's margin, from
--      where every straight line to the raider left the map; it never moved again, and every grab
--      and escape was refused for the rest of the raid (7 of 25 freeze phases at 0.5 s).
--   4. if all of that made no progress while the claim is more than Raid.StuckStuds away, count the
--      time in `t.stuck`. The server pulls the character back to `Trace2D.settle` after
--      Raid.StuckSeconds: whatever geometry a freeze leaves behind, a raider is never locked out.
-- `t.path` is the tick's path as a flat list x0, z0, x1, z1, ... (the straight leg, then each slide
-- leg); the catch test runs along every leg (Heist.caughtPath), so a slide cannot skip a trap.
-- Every raid rule reads this position, never the claim.
--
-- The walkable map is Layout.freeRects: each floor cell grown by WallShrinkStuds. An honest root
-- can never be within 1 stud of a wall (R15 root half-width), so honest movement never clamps; a
-- noclipper gains that 1 stud and nothing else. Layout.dangerRect covers that stud on a trap.
-- Where two walls touch only at a corner, the grown cells on the other diagonal overlap; the second
-- value of Layout.freeRects is a BARRIER segment across each such corner that no leg may cross
-- (REVIEW-1.md A6).
--
-- Pure: cfg + plain rect tables + numbers. No Roblox global, no clock. Requires NOTHING.

local Trace2D = {}

function Trace2D.new(cfg: any, x: number, z: number): any
	return {
		x = x,
		z = z,
		budget = 0,
		-- diagnostics only; nothing in the game reads these
		throttled = 0,
		clamped = 0,
		drift = 0,
		-- seconds without progress toward a claim more than Raid.StuckStuds away (step 4)
		stuck = 0,
		path = { x, z },
	}
end

-- The parameter interval of segment A->B inside closed rect r, or nil.
local function clip(r: any, ax: number, az: number, bx: number, bz: number): (number?, number?)
	local dx, dz = bx - ax, bz - az
	local s0, s1 = 0, 1
	local ps = { -dx, dx, -dz, dz }
	local qs = { ax - r.x0, r.x1 - ax, az - r.z0, r.z1 - az }
	for i = 1, 4 do
		local p, q = ps[i], qs[i]
		if p == 0 then
			if q < 0 then return nil, nil end
		else
			local u = q / p
			if p < 0 then
				if u > s1 then return nil, nil end
				if u > s0 then s0 = u end
			else
				if u < s0 then return nil, nil end
				if u < s1 then s1 = u end
			end
		end
	end
	if s0 > s1 then return nil, nil end
	return s0, s1
end

function Trace2D.inside(rects: { any }, x: number, z: number): boolean
	for _, r in rects do
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then return true end
	end
	return false
end

-- Where A->B first touches a barrier segment (0..1), or nil.
local function barrierHit(barriers: { any }?, ax: number, az: number, bx: number, bz: number): number?
	if barriers == nil then return nil end
	local best = nil
	local dx, dz = bx - ax, bz - az
	for _, b in barriers do
		local ex, ez = b.bx - b.ax, b.bz - b.az
		local den = dx * ez - dz * ex
		if den ~= 0 then
			-- A + s (B - A) = P + u (Q - P)
			local s = ((b.ax - ax) * ez - (b.az - az) * ex) / den
			local u = ((b.ax - ax) * dz - (b.az - az) * dx) / den
			-- inclusive, with a tolerance: a claim landing exactly ON a barrier computes s = 1 + 2e-16
			if s >= -1e-9 and s <= 1 + 1e-9 and u >= -1e-9 and u <= 1 + 1e-9 and (best == nil or s < best) then
				best = math.max(0, s)
			end
		end
	end
	return best
end

-- How far along A->B (0..1) the walkable map reaches without a break, starting from A, and never
-- across a barrier: a leg stops 0.001 studs short of one, so no position is ever ON a barrier.
local function reach(rects: { any }, ax: number, az: number, bx: number, bz: number, barriers: { any }?): number
	local limit = 1
	local hit = barrierHit(barriers, ax, az, bx, bz)
	if hit ~= nil then
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		limit = if len > 0 then math.max(0, hit - 0.001 / len) else 0
	end
	local spans = {}
	for _, r in rects do
		local s0, s1 = clip(r, ax, az, bx, bz)
		if s0 then table.insert(spans, { s0, s1 }) end
	end
	local cur = 0
	while cur < 1 do
		local best = cur
		for _, sp in spans do
			if sp[1] <= cur + 1e-9 and sp[2] > best then best = sp[2] end
		end
		if best <= cur then break end
		cur = best
	end
	return math.min(cur, limit)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- One tick. `claimX, claimZ` is where the client's root says it is (pocket-local), `dt` the seconds
-- since the last tick, `speed` the WalkSpeed the server wrote (16, or 12 while carrying),
-- `barriers` the second value of Layout.freeRects. Returns the trusted x, z.
function Trace2D.step(cfg: any, t: any, rects: { any }, claimX: any, claimZ: any, dt: number, speed: number, barriers: { any }?): (number, number)
	t.path = { t.x, t.z }
	if not finite(claimX) or not finite(claimZ) then return t.x, t.z end
	if type(dt) ~= "number" or dt ~= dt or dt < 0 then dt = 0 end
	local rate = speed * cfg.Raid.TrustedSpeedFactor
	t.budget = rate * math.min(dt, cfg.Raid.MaxTrustedTickSeconds)

	local dx, dz = claimX - t.x, claimZ - t.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= 1e-9 then
		t.stuck = 0
		return t.x, t.z
	end

	local allowed = math.min(dist, t.budget)
	if allowed + 1e-9 < dist then
		t.throttled += 1
		t.drift = math.max(t.drift, dist - allowed)
	end
	local ux, uz = dx / dist, dz / dist
	local s = reach(rects, t.x, t.z, t.x + ux * allowed, t.z + uz * allowed, barriers)
	local moved = allowed * s
	t.x += ux * moved
	t.z += uz * moved
	if moved > 0 then
		table.insert(t.path, t.x)
		table.insert(t.path, t.z)
	end
	local remaining = allowed - moved
	local progress = moved
	if s < 1 then
		t.clamped += 1
		-- step 3: slide along the boundary, the axis with farther to go first
		local order = if math.abs(claimX - t.x) >= math.abs(claimZ - t.z) then { 1, 2 } else { 2, 1 }
		for _, axis in order do
			if remaining <= 1e-9 then break end
			local d = if axis == 1 then claimX - t.x else claimZ - t.z
			if math.abs(d) > 1e-9 then
				local want = math.min(remaining, math.abs(d))
				local sign = if d > 0 then 1 else -1
				local sx = if axis == 1 then sign * want else 0
				local sz = if axis == 2 then sign * want else 0
				local f = reach(rects, t.x, t.z, t.x + sx, t.z + sz, barriers)
				if f > 0 then
					t.x += sx * f
					t.z += sz * f
					remaining -= want * f
					progress += want * f
					table.insert(t.path, t.x)
					table.insert(t.path, t.z)
				end
			end
		end
	end
	t.budget = remaining
	-- step 4
	local left = math.sqrt((claimX - t.x) ^ 2 + (claimZ - t.z) ^ 2)
	if progress <= 1e-6 and left > cfg.Raid.StuckStuds then
		t.stuck += math.min(dt, cfg.Raid.MaxTrustedTickSeconds)
	else
		t.stuck = 0
	end
	return t.x, t.z
end

-- Where a character pulled back to trusted position (x, z) should stand: the point moved into the
-- standable part of the floor cell it belongs to, 2 x WallShrinkStuds inside the cell's grown rect
-- (the wall margin, then the root's half-width). Of the cells whose grown rect holds the point and
-- whose centre it reaches in a straight legal line, the one needing the smallest move wins.
function Trace2D.settle(cfg: any, rects: { any }, barriers: { any }?, x: number, z: number): (number, number)
	local g = 2 * cfg.Raid.WallShrinkStuds
	local bestX, bestZ, bestD = x, z, math.huge
	for _, r in rects do
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
			if reach(rects, x, z, cx, cz, barriers) >= 1 then
				local sx = math.clamp(x, r.x0 + g, r.x1 - g)
				local sz = math.clamp(z, r.z0 + g, r.z1 - g)
				local d = (sx - x) ^ 2 + (sz - z) ^ 2
				if d < bestD then bestX, bestZ, bestD = sx, sz, d end
			end
		end
	end
	return bestX, bestZ
end

return Trace2D
