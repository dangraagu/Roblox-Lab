--!strict
-- RunCheck.luau — the server's movement guard for one run (DESIGN §11). Pure; ServerScriptService.
--
-- Fed every Heartbeat sample of the runner's root (lane-local x/z, y over the floor top) with the run
-- clock (the sum of the server's own Heartbeat dt). A failed check returns a reason a player can
-- read, and the caller voids the run. What it checks:
--   * continuity: every sample is in the same cell as the last, an open-passage neighbour, or a
--     diagonal with a 2-step open path. After a gap > GapSeconds the open-path allowance grows to
--     ceil(gap * speed * GapFactor / cell) + 1 steps. The antechamber is a node joined only to the
--     entrance;
--   * burst: displacement in any BurstWindow (0.5 s) <= speed * 0.5 * 1.5 + 3 = 15 studs;
--   * sustained: displacement in any SustainWindow (3 s) <= speed * 3 * 1.05 + 4.5 = 54.9 studs
--     (both slacks carry a 0.4 s replication stall on a straight hall; Config.Check);
--   * whole run (at the finish): the time may not beat the TAUT LINE through the cells the runner
--     actually passed (string-pulled, TautMargin from the jambs) at speed * 1.02. DESIGN §11 said
--     "path length sampled every 0.25 s / time"; measured on the spec's day, 0.25 s chords cut the
--     corners and under-measured a real 477.9-stud walk as 468.0 (-2.1 %), so a whole run at 1.03x
--     read 16.08 studs/s and passed. The taut line is a LOWER bound on any real walk through those
--     cells, and network jitter cannot lengthen it, so an honest runner can never fail it;
--   * height: root between MinRootY and MaxRootY over the floor top (the ceiling is at 14);
--   * the lane: a root outside the grid and the antechamber is out.
-- Every limit is provisional until Studio measures honest runs (needs-Studio list, item 1).

local RunCheck = {}

local ANTE = -1

local function nodeOf(cfg: any, x: number, z: number): number?
	local g = cfg.Grid
	local c = g.Cell
	if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then return nil end
	local cx, cy = math.floor(x / c), math.floor(z / c)
	if cx >= 0 and cx < g.W and cy >= 0 and cy < g.H then return cy * g.W + cx end
	if cx == g.EntranceX and cy == -1 and z >= -cfg.World.AntechamberDepth then return ANTE end
	return nil
end

local function neighbours(guard: any, n: number): { number }
	local world = guard.world
	if n == ANTE then return { world.entrance } end
	local m = world.maze
	local W, H = m.W, m.H
	local x, y = n % W, n // W
	local out = {}
	if x + 1 < W and m.openE[n] then table.insert(out, n + 1) end
	if x - 1 >= 0 and m.openE[n - 1] then table.insert(out, n - 1) end
	if y + 1 < H and m.openN[n] then table.insert(out, n + W) end
	if y - 1 >= 0 and m.openN[n - W] then table.insert(out, n - W) end
	if n == world.entrance then table.insert(out, ANTE) end
	return out
end

-- Open-path steps from a to b, or math.huge when more than `limit`.
local function pathDist(guard: any, a: number, b: number, limit: number): number
	if a == b then return 0 end
	local depth = { [a] = 0 }
	local q, head = { a }, 1
	while head <= #q do
		local c = q[head]
		head += 1
		if depth[c] < limit then
			for _, n in neighbours(guard, c) do
				if depth[n] == nil then
					depth[n] = depth[c] + 1
					if n == b then return depth[n] end
					table.insert(q, n)
				end
			end
		end
	end
	return math.huge
end

local function coords(guard: any, n: number): (number, number)
	if n == ANTE then return guard.cfg.Grid.EntranceX, -1 end
	local W = guard.world.maze.W
	return n % W, n // W
end

-- funnel: Dungeon.funnel (passed in: this module requires nothing).
function RunCheck.new(cfg: any, world: any, funnel: any): any
	return {
		cfg = cfg, world = world, funnel = funnel,
		node = ANTE, x = nil, z = nil, t = 0,
		hist = {}, -- { {t, x, z} } within the sustain window
		pathOn = false, cells = {}, waypoints = {}, startX = 0, startZ = 0,
	}
end

-- The cells strictly between a and b on a shortest open path (BFS in neighbour order, so the same
-- inputs always give the same cells), or {} when they are joined directly or not at all.
local function between(guard: any, a: number, b: number): { number }
	local parent = { [a] = a }
	local q, head = { a }, 1
	while head <= #q do
		local c = q[head]
		head += 1
		if c == b then break end
		for _, n in neighbours(guard, c) do
			if parent[n] == nil and n ~= ANTE then
				parent[n] = c
				table.insert(q, n)
			end
		end
	end
	if parent[b] == nil then return {} end
	local out = {}
	local c = parent[b]
	while c ~= a do
		table.insert(out, 1, c)
		c = parent[c]
	end
	return out
end

-- Append a grid cell to the run's corridor. Consecutive corridor cells ALWAYS share an open passage
-- (Dungeon.funnel's portals assume it): a diagonal step, or a longer gap the continuity check let
-- through (a server hitch widens its allowance), is filled with the cells of a shortest open path,
-- so the taut line follows the halls and never cuts a wall (REVIEW-1 finding 1).
local function passCell(guard: any, n: number)
	if n == ANTE then return end
	local cells = guard.cells
	local last = cells[#cells]
	if last == n then return end
	if last ~= nil then
		for _, c in between(guard, last, n) do table.insert(cells, c) end
	end
	table.insert(cells, n)
end

-- The run's first sample: the character has just been moved into the antechamber by the server.
function RunCheck.arrive(guard: any, x: number, z: number, t: number)
	guard.node = nodeOf(guard.cfg, x, z) or ANTE
	guard.x, guard.z, guard.t = x, z, t
	guard.hist = { { t, x, z } }
end

-- For specs only: pretend the guard last saw the root at (x, z) in `node` at time t.
function RunCheck.debugPlace(guard: any, node: number, x: number, z: number, t: number)
	guard.node = node
	guard.x, guard.z, guard.t = x, z, t
	guard.hist = { { t, x, z } }
end

local function fmt(d: number): string
	return string.format("%.1f", d)
end

-- (ok, reason)
function RunCheck.sample(guard: any, t: number, x: number, y: number, z: number): (boolean, string?)
	local cfg = guard.cfg
	local C = cfg.Check
	local speed = cfg.Walk.Speed
	if type(y) ~= "number" or y ~= y or y < C.MinRootY or y > C.MaxRootY then
		return false, "Run not ranked: your height left the halls (" .. fmt(tonumber(y) or 0) .. " studs over the floor). Nothing was posted."
	end
	local node = nodeOf(cfg, x, z)
	if node == nil then
		return false, "Run not ranked: you left the dungeon. Nothing was posted."
	end
	if guard.x == nil then
		RunCheck.arrive(guard, x, z, t)
		return true, nil
	end
	local gap = t - guard.t
	local jump = math.sqrt((x - guard.x) ^ 2 + (z - guard.z) ^ 2)
	-- continuity
	if node ~= guard.node then
		local ax, ay = coords(guard, guard.node)
		local bx, by = coords(guard, node)
		local limit = 1
		if math.abs(ax - bx) == 1 and math.abs(ay - by) == 1 then limit = 2 end
		if gap > C.GapSeconds then
			limit = math.max(limit, math.ceil(gap * speed * C.GapFactor / cfg.Grid.Cell) + 1)
		end
		local d = pathDist(guard, guard.node, node, limit)
		if d > limit then
			if math.abs(ax - bx) + math.abs(ay - by) == 1 then
				return false, "Run not ranked: you passed through a wall. Nothing was posted."
			end
			return false, string.format("Run not ranked: position jumped %s studs in %.2f s (connection hiccup?). Nothing was posted.",
				fmt(jump), gap)
		end
	end
	-- windows
	table.insert(guard.hist, { t, x, z })
	local keepFrom = t - C.SustainWindow - 0.5
	local drop = 0
	for i, h in guard.hist do
		if h[1] < keepFrom then drop = i else break end
	end
	if drop > 0 then
		local kept = {}
		for i = drop + 1, #guard.hist do table.insert(kept, guard.hist[i]) end
		guard.hist = kept
	end
	local function window(w: number, factor: number, slack: number): string?
		for _, h in guard.hist do
			if h[1] >= t - w - 1e-9 then
				local d = math.sqrt((x - h[2]) ^ 2 + (z - h[3]) ^ 2)
				local lim = speed * w * factor + slack
				if d > lim then
					return string.format("Run not ranked: moved %s studs in %.1f s, faster than walking allows (%s). Nothing was posted.",
						fmt(d), t - h[1], fmt(lim))
				end
				return nil
			end
		end
		return nil
	end
	local r = window(C.BurstWindow, C.BurstFactor, C.BurstSlack) or window(C.SustainWindow, C.SustainFactor, C.SustainSlack)
	if r then return false, r end
	if guard.pathOn and node ~= guard.node then passCell(guard, node) end
	guard.node, guard.x, guard.z, guard.t = node, x, z, t
	return true, nil
end

-- The clock started at (x, z) at time t (the line, in the entrance cell): the corridor starts here.
function RunCheck.startPath(guard: any, t: number, x: number, z: number)
	guard.pathOn = true
	guard.cells = {}
	guard.waypoints = {}
	guard.startX, guard.startZ = x, z
	passCell(guard, guard.world.entrance)
	if guard.node ~= ANTE then passCell(guard, guard.node) end
end

-- A seal was taken at (x, z), inside `cell`: the taut line must pass through this point.
function RunCheck.waypoint(guard: any, cell: number, x: number, z: number)
	local at = #guard.cells
	for i = #guard.cells, 1, -1 do
		if guard.cells[i] == cell then at = i; break end
	end
	table.insert(guard.waypoints, { index = at, x = x, z = z })
end

-- The taut line (studs) from the start point, through every pickup point, to (x, z), each leg
-- string-pulled through the corridor of cells the runner actually passed between those points.
-- A lower bound on any real walk that took those seals at those points: it follows the cells passed
-- and ignores how the runner moved inside them, so jitter and wandering can only make it shorter
-- than the truth, never longer.
function RunCheck.tautLine(guard: any, x: number, z: number): (number, { any })
	local cfg = guard.cfg
	local total = 0
	local points = { { x = guard.startX, z = guard.startZ } }
	local fromIdx, fx, fz = 1, guard.startX, guard.startZ
	local legs = table.clone(guard.waypoints or {})
	table.insert(legs, { index = #guard.cells, x = x, z = z })
	for _, wp in legs do
		local slice = {}
		for i = fromIdx, math.max(wp.index, fromIdx) do table.insert(slice, guard.cells[i]) end
		local len, pts = guard.funnel(guard.world.maze, slice, { x = fx, y = fz }, { x = wp.x, y = wp.z },
			cfg.Grid.Cell, cfg.Check.TautMargin)
		total += len
		for j = 2, #pts do table.insert(points, { x = pts[j].x, z = pts[j].y }) end
		fromIdx, fx, fz = math.max(wp.index, fromIdx), wp.x, wp.z
	end
	return total, points
end

function RunCheck.tautLength(guard: any, x: number, z: number): number
	return (RunCheck.tautLine(guard, x, z))
end

-- At the finish point (x, z) at time t, with the clock started at t0. (ok, reason)
function RunCheck.finishCheck(guard: any, t: number, x: number, z: number, t0: number): (boolean, string?)
	local cfg = guard.cfg
	local elapsed = t - t0
	if elapsed <= 0 then return false, "Run not ranked: no time passed. Nothing was posted." end
	local taut = RunCheck.tautLength(guard, x, z)
	local rate = taut / elapsed
	local lim = cfg.Walk.Speed * cfg.Check.WholeRunFactor
	if rate > lim then
		return false, string.format("Run not ranked: the shortest line through the halls you took is %s studs, and you covered it at %s studs/s (the limit is %s). Nothing was posted.",
			string.format("%.1f", taut), string.format("%.2f", rate), string.format("%.2f", lim))
	end
	return true, nil
end

return RunCheck
