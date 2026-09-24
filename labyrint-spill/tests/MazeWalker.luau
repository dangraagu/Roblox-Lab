--!strict
-- MazeWalker.luau — TEST-SIDE model of a player walking the labyrinth. Not shipped (tests/ only).
--
-- Why a model: there is no telemetry yet, so "how long until the ice cellar" and "how often does
-- an icicle nearly hit you" are answered by walking the game's OWN mazes (MazeGen, the server's
-- generator) with a player whose human part is written down, not hidden in a number:
--
--   * the maze is MazeGen.generate at the level's size from MazeGen.getDifficulty (the live curve);
--   * traps are drawn the way the server draws them: a Fisher-Yates-shuffled pool of every cell but
--     start and exit, coins and gems taken first, then the traps;
--   * the walker moves at WalkSpeed along cell centres and the passages between them (9 studs a
--     step, CellSize), exploring depth-first. At every fork it heads toward the exit corner with
--     probability `bias` (the exit is always the far corner, and players learn that) and otherwise
--     picks at random; it pauses `decide` seconds at a fork and `deadEnd` seconds at a dead end.
--   * a run ends on reaching the exit. Deaths and retries are NOT modelled (monsters and traps are
--     server-side and unchanged by this work); the pacing numbers are therefore a lower bound.
--
-- Everything is deterministic from the seed: the RNG is a MINSTD LCG read through its high bits
-- (the repo checklist: never `state % span` for small spans).

local MazeWalker = {}

-- A copy of MazeGame.server CONFIG.Curve (the server keeps it inside the script, out of reach of
-- the CLI). robloxemu/check_labyrintspill_biomes.luau parses the real server source and fails if
-- this copy drifts.
MazeWalker.CURVE = {
	StartSize = 6, SizeEveryNLevels = 10, MaxSize = 30,
	FirstTrapLevel = 6, TrapEveryNLevels = 16, MaxTraps = 12,
	FirstMonsterLevel = 4, MonsterEveryNLevels = 25, MaxMonsters = 10,
	MonsterSpeedStart = 7, MonsterSpeedPerLevel = 0.02, MonsterSpeedMax = 15,
	CoinDensity = 0.10, MinCoins = 3,
	StartGems = 3, GemsPerLevels = 125,
	StartButtons = 3, ButtonsPerLevels = 170,
	StartSight = 60, SightTightenPerLevel = 0.05, MinSight = 35,
}

-- The human part, written down. speed = CONFIG.PlayerWalkSpeed, cellSize = CONFIG.CellSize.
--   bias:    at a fork, heads for the exit corner with this probability (else a random way)
--   decide:  seconds standing at a fork;  deadEnd: seconds to turn round at a dead end
MazeWalker.PROFILES = {
	normal = { bias = 0.7, decide = 0.8, deadEnd = 0.6, speed = 16, cellSize = 9 },
	fast = { bias = 0.85, decide = 0.3, deadEnd = 0.3, speed = 16, cellSize = 9 },
	slow = { bias = 0.55, decide = 1.5, deadEnd = 1.0, speed = 16, cellSize = 9 },
}

export type Rng = { NextInteger: (any, number, number) -> number, NextNumber: (any) -> number, state: number }

function MazeWalker.rng(seed: number): Rng
	local s = math.floor(math.abs(seed)) % 2147483646 + 1
	local r = { state = s }
	function r.NextNumber(self: any): number
		self.state = (self.state * 48271) % 2147483647
		return (self.state - 1) / 2147483646
	end
	function r.NextInteger(self: any, a: number, b: number): number
		local u = self:NextNumber()
		local n = a + math.floor(u * (b - a + 1))
		if n > b then n = b end
		return n
	end
	return (r :: any) :: Rng
end

-- One level as the server would build it. `MazeGen` and the curve are passed in (tests/ has no
-- ReplicatedStorage). Returns cells/fine grid and the trap cells as a set of "cx,cy".
function MazeWalker.level(MazeGen: any, curve: any, L: number, seed: number): any
	local diff = MazeGen.getDifficulty(L, curve)
	local rng = MazeWalker.rng(seed * 7919 + L * 104729)
	local cols, rows = diff.size, diff.size
	local grid, gCols, gRows = MazeGen.generate(cols, rows, rng)
	local pool = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			if not ((cx == 0 and cy == 0) or (cx == cols - 1 and cy == rows - 1)) then
				table.insert(pool, { cx, cy })
			end
		end
	end
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local function take(n: number): { any }
		local out = {}
		for _ = 1, math.min(n, #pool) do table.insert(out, table.remove(pool)) end
		return out
	end
	take(diff.coins)
	take(diff.gems)
	local traps = {}
	for _, c in take(diff.traps) do traps[c[1] .. "," .. c[2]] = true end
	return {
		level = L, cols = cols, rows = rows, grid = grid, gCols = gCols, gRows = gRows,
		traps = traps, diff = diff,
	}
end

-- World position (x, z) of a fine-grid cell, origin at the maze centre (the server's gridToWorld).
function MazeWalker.fineToWorld(lv: any, fx: number, fy: number, cellSize: number): (number, number)
	return (fx - (lv.gCols - 1) / 2) * cellSize, (fy - (lv.gRows - 1) / 2) * cellSize
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Open neighbour cells of (cx, cy): the wall between them is open in the fine grid.
local function openNeighbours(lv: any, cx: number, cy: number): { { number } }
	local out = {}
	for _, d in DIRS do
		local nx, ny = cx + d[1], cy + d[2]
		if nx >= 0 and nx < lv.cols and ny >= 0 and ny < lv.rows then
			if lv.grid[2 * cy + 1 + d[2]][2 * cx + 1 + d[1]] == false then
				table.insert(out, { nx, ny })
			end
		end
	end
	return out
end
MazeWalker.openNeighbours = openNeighbours

-- A walk: a list of timed waypoints { x, z, t } (world studs, seconds). Between two waypoints the
-- walker moves in a straight line; two waypoints at the same spot are a pause.
--   profile = { bias, decide, deadEnd, speed, cellSize }
function MazeWalker.explore(lv: any, rng: Rng, profile: any): any
	local S = profile.cellSize
	local speed = profile.speed
	local stepT = S / speed
	local ex, ey = lv.cols - 1, lv.rows - 1
	local visited = {}
	local function key(cx: number, cy: number): string return cx .. "," .. cy end
	local pts = {}
	local t = 0
	local function push(fx: number, fy: number)
		local x, z = MazeWalker.fineToWorld(lv, fx, fy, S)
		table.insert(pts, { x = x, z = z, t = t })
	end
	local function pause(seconds: number)
		if seconds <= 0 then return end
		local last = pts[#pts]
		t += seconds
		table.insert(pts, { x = last.x, z = last.z, t = t })
	end
	-- move from cell a to neighbouring cell b through the passage between them: two fine steps
	local function walk(ax: number, ay: number, bx: number, by: number)
		local mx, my = (2 * ax + 1 + 2 * bx + 1) / 2, (2 * ay + 1 + 2 * by + 1) / 2
		t += stepT
		push(mx, my)
		t += stepT
		push(2 * bx + 1, 2 * by + 1)
	end
	local stack = { { 0, 0 } }
	visited[key(0, 0)] = true
	push(1, 1)
	local steps = 0
	while #stack > 0 do
		local cur = stack[#stack]
		local cx, cy = cur[1], cur[2]
		if cx == ex and cy == ey then break end
		local nbrs = openNeighbours(lv, cx, cy)
		local fresh = {}
		for _, n in nbrs do
			if not visited[key(n[1], n[2])] then table.insert(fresh, n) end
		end
		if #nbrs >= 3 then pause(profile.decide) end
		if #fresh > 0 then
			local pick
			if #fresh > 1 and rng:NextNumber() < profile.bias then
				local best, bestD = {}, math.huge
				for _, n in fresh do
					local d = math.abs(ex - n[1]) + math.abs(ey - n[2])
					if d < bestD then best, bestD = { n }, d
					elseif d == bestD then table.insert(best, n) end
				end
				pick = best[rng:NextInteger(1, #best)]
			else
				pick = fresh[rng:NextInteger(1, #fresh)]
			end
			visited[key(pick[1], pick[2])] = true
			walk(cx, cy, pick[1], pick[2])
			table.insert(stack, pick)
		else
			if #nbrs == 1 then pause(profile.deadEnd) end
			table.remove(stack)
			local back = stack[#stack]
			if back then walk(cx, cy, back[1], back[2]) end
		end
		steps += 1
		if steps > 200000 then break end
	end
	return { points = pts, duration = t }
end

-- The shortest route start -> exit (the par route), as timed waypoints at `speed`, no pauses.
function MazeWalker.parRoute(lv: any, dist: any, profile: any): any
	local S = profile.cellSize
	local stepT = S / profile.speed
	local tx, ty = 2 * (lv.cols - 1) + 1, 2 * (lv.rows - 1) + 1
	local d = dist(lv.grid, lv.gCols, lv.gRows, tx, ty)
	local x, y = 1, 1
	local pts = {}
	local t = 0
	local wx, wz = MazeWalker.fineToWorld(lv, x, y, S)
	table.insert(pts, { x = wx, z = wz, t = 0 })
	local guard = 0
	while not (x == tx and y == ty) do
		local here = d[x .. "," .. y]
		local moved = false
		for _, dd in DIRS do
			local nx, ny = x + dd[1], y + dd[2]
			local v = d[nx .. "," .. ny]
			if v ~= nil and here ~= nil and v == here - 1 then
				x, y = nx, ny
				moved = true
				break
			end
		end
		if not moved then break end
		t += stepT
		wx, wz = MazeWalker.fineToWorld(lv, x, y, S)
		table.insert(pts, { x = wx, z = wz, t = t })
		guard += 1
		if guard > 100000 then break end
	end
	return { points = pts, duration = t }
end

-- World centres of a level's hazard cells, for the simulation.
function MazeWalker.hazardsFor(lv: any, CellHazards: any, seed: number, cfg: any): { any }
	local list = CellHazards.pick(lv.level, lv.cols, lv.rows, lv.traps, seed, cfg)
	local out = {}
	for _, hz in list do
		local x, z = MazeWalker.fineToWorld(lv, 2 * hz.cx + 1, 2 * hz.cy + 1, cfg.CellSize)
		table.insert(out, { hz = hz, centre = { x = x, y = 0, z = z } })
	end
	return out
end

-- Replay a walk against a level's hazards on the level clock (frames of dt = 0.05 s; movement
-- carries leftover frame time across waypoints, and each impact is judged at its exact instant with
-- the player's position interpolated inside the frame).
--   policy "ignore": walks on regardless; a hit knocks it down for KnockSeconds.
--   policy "react":  a normal player. Seeing a warning on the cell it is about to enter, it waits in
--                    the passage — the safe spot — until the impact has passed, and it never dawdles
--                    (decision pauses) inside a hazard cell.
--   policy "runner": a speedrunner on the par route. Waits only if it would otherwise be inside the
--                    zone at the impact instant; no other caution.
-- Returns { duration, hits, near, waited, maxWait }. A near-hit is an impact within NearRadius of
-- the player that did not hit them.
function MazeWalker.simulate(walk: any, hazards: { any }, cfg: any, policy: string, CellHazards: any): any
	local pts = walk.points
	local dt = 0.05
	local T = 0
	local i = 1
	local segT = 0
	local knockLeft = 0
	local hits, near, waited, maxWait, curWait = 0, 0, 0, 0, 0
	local R = cfg.StrikeRadius + cfg.PlayerRadius
	local speed = cfg.WalkSpeed
	-- zone crossing, from the passage 9 studs out: enter after (S - R)/v, leave after (S + R)/v
	local enterAfter = (cfg.CellSize - R) / speed
	local leaveAfter = (cfg.CellSize + R) / speed
	local nextImp = {}
	for k, h in hazards do nextImp[k] = CellHazards.firstImpact(h.hz, cfg) end
	local posX, posZ = pts[1].x, pts[1].z
	local function zoneAt(x: number, z: number): number?
		for k, h in hazards do
			local dx, dz = x - h.centre.x, z - h.centre.z
			if dx * dx + dz * dz <= R * R then return k end
		end
		return nil
	end
	-- true when the walker, standing at the start of segment i at time `now`, should not set off yet
	local function mustWait(now: number): boolean
		if policy == "ignore" then return false end
		local a, b = pts[i], pts[i + 1]
		if a.x == b.x and a.z == b.z then return false end
		local k = zoneAt(b.x, b.z)
		if k == nil then return false end
		local Timp = CellHazards.nextImpact(hazards[k].hz, now + 1e-9, cfg)
		if policy == "react" then
			return Timp - now <= cfg.WarnSeconds + leaveAfter
		end
		return Timp >= now + enterAfter - 0.05 and Timp <= now + leaveAfter + 0.05
	end
	local finishAt = nil
	local guard = 0
	while i < #pts do
		guard += 1
		if guard > 4000000 then break end
		local x0, z0 = posX, posZ
		local budget = dt
		if knockLeft > 0 then
			knockLeft -= dt
			budget = 0
		end
		local waitedThisFrame = false
		while budget > 1e-12 and i < #pts do
			local a, b = pts[i], pts[i + 1]
			if segT == 0 then
				if policy == "react" and a.x == b.x and a.z == b.z and zoneAt(a.x, a.z) ~= nil then
					-- a reacting player does not stop to think under a hazard: skip the pause
					i += 1
					continue
				end
				if mustWait(T + (dt - budget)) then
					waited += budget
					curWait += budget
					waitedThisFrame = true
					budget = 0
					break
				end
			end
			local remain = (b.t - a.t) - segT
			if budget >= remain then
				budget -= remain
				segT = 0
				i += 1
				posX, posZ = b.x, b.z
			else
				segT += budget
				budget = 0
				local d = b.t - a.t
				local f = if d > 0 then segT / d else 1
				posX, posZ = a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
			end
		end
		if i >= #pts and finishAt == nil then finishAt = T + (dt - budget) end
		if not waitedThisFrame and curWait > 0 then
			maxWait = math.max(maxWait, curWait)
			curWait = 0
		end
		local T0 = T
		T += dt
		for k, h in hazards do
			while nextImp[k] <= T do
				local f = math.clamp((nextImp[k] - T0) / dt, 0, 1)
				local px, pz = x0 + (posX - x0) * f, z0 + (posZ - z0) * f
				local dx, dz = px - h.centre.x, pz - h.centre.z
				local dd = math.sqrt(dx * dx + dz * dz)
				if dd <= R then
					hits += 1
					knockLeft = cfg.KnockSeconds
				elseif dd <= cfg.NearRadius then
					near += 1
				end
				nextImp[k] += cfg.Period
			end
		end
	end
	-- the last frame's leftover time is not play time: report the moment the walk ended
	return { duration = finishAt or T, hits = hits, near = near, waited = waited, maxWait = math.max(maxWait, curWait) }
end

return MazeWalker
