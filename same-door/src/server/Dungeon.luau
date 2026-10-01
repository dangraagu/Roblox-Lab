--!strict
-- Dungeon.luau — the daily dungeon: generator, placement, perfect line, record, validation. Pure.
--
-- A ModuleScript in ServerScriptService: it NEVER replicates. The day's layout is not derived from a
-- seed (DESIGN §3): the server mints it once, on the day, from `draw`, a random source passed in as
-- an argument, and stores the result as data (Config.Day.StoreName, key d_<dayIndex>). On the server
-- `draw` XORs two Roblox Randoms and reads the high bits; in tests it is the repo's Rng.
--
--   draw(n) -> an integer in 1..n
--
-- Cells are 0-based indices i = y * W + x. openE[i]: a passage from (x, y) to (x + 1, y);
-- openN[i]: a passage from (x, y) to (x, y + 1). The entrance additionally opens south onto the
-- start line (the antechamber); that opening is part of the fixed lane shell, not of the maze.
--
-- The record (about 300 characters of JSON, only string keys and dense arrays):
--   { v, day, w, h, open = <41 hex digits>, entrance = {x,y}, seals = {{x,y} x3},
--     door = {x,y}, hazards = {{x,y,slot} x3}, perfectMs, mintedAt [, studio = true] }

local Dungeon = {}

local PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
local HEX = "0123456789abcdef"

--======================================================================== maze primitives

function Dungeon.newMaze(W: number, H: number): any
	local m = { W = W, H = H, openE = {}, openN = {} }
	for i = 0, W * H - 1 do
		m.openE[i] = false
		m.openN[i] = false
	end
	return m
end

function Dungeon.neighbours(m: any, i: number): { number }
	local W, H = m.W, m.H
	local x, y = i % W, i // W
	local out = {}
	if x + 1 < W and m.openE[i] then table.insert(out, i + 1) end
	if x - 1 >= 0 and m.openE[i - 1] then table.insert(out, i - 1) end
	if y + 1 < H and m.openN[i] then table.insert(out, i + W) end
	if y - 1 >= 0 and m.openN[i - W] then table.insert(out, i - W) end
	return out
end

-- dist, parent from src over open passages.
function Dungeon.bfs(m: any, src: number): ({ [number]: number }, { [number]: number })
	local dist, parent = { [src] = 0 }, {}
	local q, head = { src }, 1
	while head <= #q do
		local c = q[head]
		head += 1
		for _, n in Dungeon.neighbours(m, c) do
			if dist[n] == nil then
				dist[n] = dist[c] + 1
				parent[n] = c
				table.insert(q, n)
			end
		end
	end
	return dist, parent
end

-- Recursive backtracker from the entrance (labyrint-spill MazeGen), then `loops` extra openings.
function Dungeon.generate(cfg: any, draw: (number) -> number): any
	local g = cfg.Grid
	local W, H = g.W, g.H
	local m = Dungeon.newMaze(W, H)
	local visited = {}
	local sx, sy = g.EntranceX, g.EntranceY
	local stack = { { sx, sy } }
	visited[sy * W + sx] = true
	while #stack > 0 do
		local cur = stack[#stack]
		local cx, cy = cur[1], cur[2]
		local nb = {}
		if cx + 1 < W and not visited[cy * W + cx + 1] then table.insert(nb, { cx + 1, cy }) end
		if cx - 1 >= 0 and not visited[cy * W + cx - 1] then table.insert(nb, { cx - 1, cy }) end
		if cy + 1 < H and not visited[(cy + 1) * W + cx] then table.insert(nb, { cx, cy + 1 }) end
		if cy - 1 >= 0 and not visited[(cy - 1) * W + cx] then table.insert(nb, { cx, cy - 1 }) end
		if #nb > 0 then
			local p = nb[draw(#nb)]
			local nx, ny = p[1], p[2]
			if nx > cx then m.openE[cy * W + cx] = true
			elseif nx < cx then m.openE[cy * W + nx] = true
			elseif ny > cy then m.openN[cy * W + cx] = true
			else m.openN[ny * W + cx] = true end
			visited[ny * W + nx] = true
			table.insert(stack, { nx, ny })
		else
			table.remove(stack)
		end
	end
	local closed = {}
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local i = y * W + x
			if x + 1 < W and not m.openE[i] then table.insert(closed, { "E", i }) end
			if y + 1 < H and not m.openN[i] then table.insert(closed, { "N", i }) end
		end
	end
	for _ = 1, g.Loops do
		if #closed == 0 then break end
		local w = table.remove(closed, draw(#closed)) :: any
		if w[1] == "E" then m.openE[w[2]] = true else m.openN[w[2]] = true end
	end
	return m
end

--======================================================================== placement

-- (placement?) = { entrance, seals = {a, b, c}, door, dE, maxE, d(a, b) }
local function distances(m: any): (number, number) -> number
	local cache = {}
	return function(a: number, b: number): number
		if cache[a] == nil then cache[a] = (Dungeon.bfs(m, a)) end
		return cache[a][b] or math.huge
	end
end

function Dungeon.place(cfg: any, m: any, draw: (number) -> number): any?
	local P = cfg.Place
	local n = m.W * m.H
	local entrance = cfg.Grid.EntranceY * m.W + cfg.Grid.EntranceX
	local dE = Dungeon.bfs(m, entrance)
	local maxE = 0
	for _, d in dE do maxE = math.max(maxE, d) end
	local d = distances(m)
	local function pick(pred: (number) -> boolean): number?
		local c = {}
		for i = 0, n - 1 do
			if pred(i) then table.insert(c, i) end
		end
		if #c == 0 then return nil end
		return c[draw(#c)]
	end
	local a = pick(function(i) return dE[i] ~= nil and dE[i] >= P.SealAMin and dE[i] <= P.SealAMax end)
	if a == nil then return nil end
	local b = pick(function(i) return i ~= a and dE[i] ~= nil and dE[i] >= P.SealMin and d(a :: number, i) >= P.SealSep end)
	if b == nil then return nil end
	local c = pick(function(i)
		return i ~= a and i ~= b and dE[i] ~= nil and dE[i] >= P.SealMin
			and d(a :: number, i) >= P.SealSep and d(b :: number, i) >= P.SealSep
	end)
	if c == nil then return nil end
	local door = pick(function(i)
		return i ~= a and i ~= b and i ~= c and dE[i] ~= nil and dE[i] >= P.DoorFrac * maxE
			and d(a :: number, i) >= P.DoorSealSep and d(b :: number, i) >= P.DoorSealSep and d(c :: number, i) >= P.DoorSealSep
	end)
	if door == nil then return nil end
	return { entrance = entrance, seals = { a, b, c }, door = door, dE = dE, maxE = maxE, d = d }
end

-- Fork cells for the day's hazards: >= MinOpenSides passages, >= MinFromEntrance steps in, never the
-- entrance / a seal / the Door, pairwise >= MinSpacing steps. Slots in order of acceptance.
function Dungeon.pickHazards(cfg: any, m: any, pl: any, draw: (number) -> number): { any }
	local hz = cfg.Hazards
	local banned = { [pl.entrance] = true, [pl.door] = true, [pl.seals[1]] = true, [pl.seals[2]] = true, [pl.seals[3]] = true }
	local cands = {}
	for i = 0, m.W * m.H - 1 do
		if not banned[i] and pl.dE[i] ~= nil and pl.dE[i] >= hz.MinFromEntrance
			and #Dungeon.neighbours(m, i) >= hz.MinOpenSides then
			table.insert(cands, i)
		end
	end
	local out = {}
	while #out < hz.Count and #cands > 0 do
		local c = table.remove(cands, draw(#cands)) :: number
		local ok = true
		for _, o in out do
			if pl.d(o.cell, c) < hz.MinSpacing then ok = false; break end
		end
		if ok then table.insert(out, { cell = c, slot = #out + 1 }) end
	end
	return out
end

--======================================================================== the perfect line

local function triarea2(a: any, b: any, c: any): number
	local ax, ay = b.x - a.x, b.y - a.y
	local bx, by = c.x - a.x, c.y - a.y
	return bx * ay - ax * by
end
local function veq(a: any, b: any): boolean
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < 1e-12
end
local function dist(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- The doorway between consecutive cells a -> b, narrowed by `margin` at both jambs.
local function portal(m: any, a: number, b: number, cell: number, margin: number): (any, any)
	local ax, ay = a % m.W, a // m.W
	local bx, by = b % m.W, b // m.W
	if bx > ax then
		local xb = bx * cell
		return { x = xb, y = (ay + 1) * cell - margin }, { x = xb, y = ay * cell + margin }
	elseif bx < ax then
		local xb = ax * cell
		return { x = xb, y = ay * cell + margin }, { x = xb, y = (ay + 1) * cell - margin }
	elseif by > ay then
		local yb = by * cell
		return { x = ax * cell + margin, y = yb }, { x = (ax + 1) * cell - margin, y = yb }
	end
	local yb = ay * cell
	return { x = (ax + 1) * cell - margin, y = yb }, { x = ax * cell + margin, y = yb }
end

-- Simple stupid funnel (string pulling) through a list of portals { left, right }.
local function stringPull(portals: { any }): (number, { any })
	local pts = {}
	local apex, pl, pr = portals[1][1], portals[1][1], portals[1][2]
	local ai, li, ri = 1, 1, 1
	table.insert(pts, apex)
	local i = 2
	local n = #portals
	while i <= n do
		local left, right = portals[i][1], portals[i][2]
		local restarted = false
		if triarea2(apex, pr, right) <= 0 then
			if veq(apex, pr) or triarea2(apex, pl, right) > 0 then
				pr = right; ri = i
			else
				table.insert(pts, pl)
				apex = pl; ai = li
				pl = apex; pr = apex; li = ai; ri = ai
				i = ai + 1
				restarted = true
			end
		end
		if not restarted then
			if triarea2(apex, pl, left) >= 0 then
				if veq(apex, pl) or triarea2(apex, pr, left) < 0 then
					pl = left; li = i
				else
					table.insert(pts, pr)
					apex = pr; ai = ri
					pl = apex; pr = apex; li = ai; ri = ai
					i = ai + 1
					restarted = true
				end
			end
		end
		if not restarted then i += 1 end
	end
	local last = portals[n][1]
	if not veq(pts[#pts], last) then table.insert(pts, last) end
	local len = 0
	for k = 2, #pts do len += dist(pts[k - 1], pts[k]) end
	return len, pts
end

-- Funnel length (and the pulled points) of a cell sequence from point s to point e. {x, y} with y
-- standing for lane-local z.
function Dungeon.funnel(m: any, cells: { number }, s: any, e: any, cell: number, margin: number): (number, { any })
	local portals = { { s, s } }
	for k = 2, #cells do
		local L, R = portal(m, cells[k - 1], cells[k], cell, margin)
		table.insert(portals, { L, R })
	end
	table.insert(portals, { e, e })
	return stringPull(portals)
end

local function centreOf(m: any, i: number, cell: number): any
	return { x = (i % m.W + 0.5) * cell, y = (i // m.W + 0.5) * cell }
end

-- The shortest string-pulled line from point s (in cell a) to point e (in cell b): the minimum
-- funnel over simple cell paths at most `slack` steps longer than the BFS distance. Searched
-- depth-first in neighbour order and stopped after `maxNodes` expansions, so it is deterministic and
-- every server recomputes the same number. (len, points, cells); math.huge when b is unreachable.
-- Why not one BFS path (as v1's first build did): equal-step paths, and paths a step or two longer,
-- can string-pull shorter (a staircase beats an L). Measured over 200 days: a shorter line than the
-- single-path funnel existed on 54 % of days, p10 3.7 % and worst 8.3 % shorter
-- (design/measure/pgap.luau); slack 4 and slack 8 found the same minimum on all 200.
function Dungeon.shortestLeg(m: any, a: number, b: number, s: any, e: any, cell: number, margin: number,
	slack: number, maxNodes: number): (number, { any }, { number })
	local dist = Dungeon.bfs(m, b)
	if dist[a] == nil then return math.huge, {}, {} end
	local limit = dist[a] + slack
	local best, bestPts, bestCells = math.huge, {} :: { any }, {} :: { number }
	local path, on = { a }, { [a] = true }
	local nodes = 0
	local function dfs(c: number, depth: number)
		if nodes >= maxNodes then return end
		nodes += 1
		if c == b then
			local len, pts = Dungeon.funnel(m, path, s, e, cell, margin)
			if len < best - 1e-9 then
				best, bestPts, bestCells = len, pts, table.clone(path)
			end
			return
		end
		for _, n in Dungeon.neighbours(m, c) do
			local dn = dist[n]
			if not on[n] and dn ~= nil and depth + 1 + dn <= limit then
				on[n] = true
				table.insert(path, n)
				dfs(n, depth + 1)
				table.remove(path)
				on[n] = nil
			end
		end
	end
	dfs(a, 0)
	return best, bestPts, bestCells
end

-- A CENTRE line: from the middle of the start line through the three seal centres (the best of the 6
-- orders) to the Door centre, each leg the shortest string-pulled line between those centres at
-- `margin`. NOT the day's P (that is Dungeon.tightLine): this is how a player who aims at the middle of
-- things plans a route, used by the pacing model (tests/RunnerModel). pl = { entrance, seals = {a, b,
-- c}, door }. (len studs, points {x, z} lane-local, order, cells)
function Dungeon.bestLine(cfg: any, m: any, pl: any, margin: number): (number, { any }, { number }?, { number })
	local cell = cfg.Grid.Cell
	local slack, cap = cfg.Perfect.PathSlack, cfg.Perfect.MaxExpansions
	local e = pl.entrance
	local startPt = { x = (e % m.W + 0.5) * cell, y = (e // m.W) * cell }
	local legs = {}
	local function leg(a: number, b: number, fromStart: boolean): any
		local key = (if fromStart then "S" else tostring(a)) .. ">" .. b
		local l = legs[key]
		if l == nil then
			local s = if fromStart then startPt else centreOf(m, a, cell)
			local len, pts, cells = Dungeon.shortestLeg(m, a, b, s, centreOf(m, b, cell), cell, margin, slack, cap)
			l = { len = len, pts = pts, cells = cells }
			legs[key] = l
		end
		return l
	end
	local best, bestOrder = math.huge, nil
	for _, o in PERMS do
		local seq = { e, pl.seals[o[1]], pl.seals[o[2]], pl.seals[o[3]], pl.door }
		local total = 0
		for k = 1, 4 do total += leg(seq[k], seq[k + 1], k == 1).len end
		if total < best - 1e-9 then best, bestOrder = total, o end
	end
	if bestOrder == nil or best == math.huge then return math.huge, {}, nil, {} end
	local seq = { e, pl.seals[bestOrder[1]], pl.seals[bestOrder[2]], pl.seals[bestOrder[3]], pl.door }
	local points, cells = { { x = startPt.x, z = startPt.y } }, { e }
	for k = 1, 4 do
		local l = leg(seq[k], seq[k + 1], k == 1)
		for j = 2, #l.pts do table.insert(points, { x = l.pts[j].x, z = l.pts[j].y }) end
		for j = 2, #l.cells do table.insert(cells, l.cells[j]) end
	end
	return best, points, bestOrder, cells
end

--======================================================================== the day's P: the tight line
-- REVIEW-1 findings 2 and 5. The whole-run check (RunCheck.finishCheck) holds every run to the TAUT
-- line through the halls it took, at 16 x 1.02: Check.TautMargin off every jamb, each seal taken where
-- the walk first comes within Pickup.Radius of it, the clock from the line crossing to the first point
-- within Pickup.Radius of the Door. P is the shortest line in exactly that geometry, so no walk can
-- beat it and a script can gain at most the check's 2 % on it. (The first build's P ran centre to
-- centre at a 2.5 margin from a fixed start: the server's own taut line of a walk of P was 0.915-0.973
-- of P, so a script on the published line passed at up to 1.11x, and every honest walk of P beat it.)
--
-- Free points: the start anywhere on the line (TautMargin inside the antechamber's walls), each seal
-- touched anywhere within Pickup.Radius - PickupInset of its centre (the inset makes a 60 Hz walk of
-- the published line surely enter the 4-stud circle: between two samples the walk cuts the corner it
-- turns at the touch point), the end ON the Door's pickup circle (where the clock stops).
-- Per leg the corridors are every simple cell path within PathSlack steps of the BFS distance whose
-- centre line is within 2 x (both ends' reach) of the best (a corridor's line moves at most as far as
-- its ends do), and the free points are settled by coordinate descent: each one moves to its best spot
-- for the line's neighbouring corners (the projection on the start line; the closest point of the
-- segment, or the reflection point on the circle, for a seal; the nearest point of the Door's circle),
-- kept only when the funnel total falls. Orders whose centre line cannot win are skipped.
-- tests/Dungeon.spec checks it against an independent sampled search.

local END_INSET = 1e-4 -- the published line ends a hair inside the Door's circle, so walking it finishes

local function closestOnSegment(a: any, b: any, c: any): (any, number)
	local abx, aby = b.x - a.x, b.y - a.y
	local L2 = abx * abx + aby * aby
	local t = if L2 > 0 then math.clamp(((c.x - a.x) * abx + (c.y - a.y) * aby) / L2, 0, 1) else 0
	local p = { x = a.x + abx * t, y = a.y + aby * t }
	return p, dist(p, c)
end

-- The point of the disc (c, r) that minimises |A - p| + |p - B|.
local function discPoint(A: any, B: any, c: any, r: number): any
	local p, d = closestOnSegment(A, B, c)
	if d <= r then return p end
	-- AB misses the disc: the reflection point on the circle, on the arc between the directions to A
	-- and to B (golden-section search; the sum is unimodal there)
	local ta = math.atan2(A.y - c.y, A.x - c.x)
	local tb = math.atan2(B.y - c.y, B.x - c.x)
	local span = tb - ta
	while span > math.pi do span -= 2 * math.pi end
	while span < -math.pi do span += 2 * math.pi end
	local lo, hi = math.min(ta, ta + span), math.max(ta, ta + span)
	local function f(t: number): number
		local q = { x = c.x + r * math.cos(t), y = c.y + r * math.sin(t) }
		return dist(A, q) + dist(q, B)
	end
	local g = (math.sqrt(5) - 1) / 2
	local x1, x2 = hi - g * (hi - lo), lo + g * (hi - lo)
	local f1, f2 = f(x1), f(x2)
	for _ = 1, 60 do
		if f1 <= f2 then
			hi, x2, f2 = x2, x1, f1
			x1 = hi - g * (hi - lo)
			f1 = f(x1)
		else
			lo, x1, f1 = x1, x2, f2
			x2 = lo + g * (hi - lo)
			f2 = f(x2)
		end
	end
	local t = (lo + hi) / 2
	return { x = c.x + r * math.cos(t), y = c.y + r * math.sin(t) }
end

local function onCircle(p: any, c: any, r: number): any
	local dx, dy = p.x - c.x, p.y - c.y
	local L = math.sqrt(dx * dx + dy * dy)
	if L < 1e-9 then return { x = c.x, y = c.y - r } end
	return { x = c.x + dx / L * r, y = c.y + dy / L * r }
end

-- Every simple cell path a -> b at most `slack` steps over the BFS distance whose funnel from sRef to
-- eRef is within `cutoff` of the best one; DFS in neighbour order, stopped after maxNodes expansions,
-- so every server finds the same list. (paths, best length)
function Dungeon.legPaths(m: any, a: number, b: number, sRef: any, eRef: any, cell: number, margin: number,
	slack: number, maxNodes: number, cutoff: number): ({ { number } }, number)
	local dists = Dungeon.bfs(m, b)
	if dists[a] == nil then return {}, math.huge end
	local limit = dists[a] + slack
	local found, best = {}, math.huge
	local path, on = { a }, { [a] = true }
	local nodes = 0
	local function dfs(c: number, depth: number)
		if nodes >= maxNodes then return end
		nodes += 1
		if c == b then
			local len = Dungeon.funnel(m, path, sRef, eRef, cell, margin)
			table.insert(found, { len = len, cells = table.clone(path) })
			if len < best then best = len end
			return
		end
		for _, n in Dungeon.neighbours(m, c) do
			local dn = dists[n]
			if not on[n] and dn ~= nil and depth + 1 + dn <= limit then
				on[n] = true
				table.insert(path, n)
				dfs(n, depth + 1)
				table.remove(path)
				on[n] = nil
			end
		end
	end
	dfs(a, 0)
	local out = {}
	for _, f in found do
		if f.len <= best + cutoff then table.insert(out, f.cells) end
	end
	return out, best
end

-- The day's P. pl = { entrance, seals = {a, b, c}, door }. (len studs, points {x, z} lane-local,
-- order, cells); math.huge when some leg is unreachable.
function Dungeon.tightLine(cfg: any, m: any, pl: any): (number, { any }, { number }?, { number })
	local cell = cfg.Grid.Cell
	local margin = cfg.Check.TautMargin
	local slack, cap = cfg.Perfect.PathSlack, cfg.Perfect.MaxExpansions
	local rs = cfg.Pickup.Radius - cfg.Perfect.PickupInset
	local rd = cfg.Pickup.Radius - END_INSET
	local e = pl.entrance
	local ex, ey = e % m.W, e // m.W
	local lo, hi = ex * cell + margin, (ex + 1) * cell - margin
	local lineY = ey * cell
	local sRef = { x = (lo + hi) / 2, y = lineY }
	local reachS = (hi - lo) / 2

	local legs = {}
	local function legOf(a: number, b: number, fromStart: boolean): any
		local key = (if fromStart then "S" else tostring(a)) .. ">" .. b
		local l = legs[key]
		if l == nil then
			local s = if fromStart then sRef else centreOf(m, a, cell)
			local reach = (if fromStart then reachS else rs) + (if b == pl.door then rd else rs)
			local paths, best = Dungeon.legPaths(m, a, b, s, centreOf(m, b, cell), cell, margin, slack, cap, 2 * reach + 0.5)
			l = { paths = paths, best = best, reach = reach }
			legs[key] = l
		end
		return l
	end
	local function legLen(l: any, p: any, q: any): (number, { any }, { number })
		local best, bestPts, bestCells = math.huge, {} :: { any }, {} :: { number }
		for _, cells in l.paths do
			local len, pts = Dungeon.funnel(m, cells, p, q, cell, margin)
			if len < best - 1e-12 then best, bestPts, bestCells = len, pts, cells end
		end
		return best, bestPts, bestCells
	end

	-- One seal order. Coordinate descent over the 5 free points, each leg taking its best corridor at
	-- the current points. A descent can stall where switching one leg's corridor only pays once BOTH
	-- of its ends have moved to suit it (tests/walk.luau found one: a player's own line on day -a 8 beat
	-- P by 1.9 studs). So after it settles, every other corridor of every leg is tried: that leg is
	-- pinned to it, the points descend again, the pin is lifted, and the result is kept if shorter;
	-- repeated until no switch helps.
	local function solve(seq: { number }): (number, { any }, { any }, { any })
		local ls = { legOf(seq[1], seq[2], true), legOf(seq[2], seq[3], false), legOf(seq[3], seq[4], false), legOf(seq[4], seq[5], false) }
		local centres = { sRef, centreOf(m, seq[2], cell), centreOf(m, seq[3], cell), centreOf(m, seq[4], cell), centreOf(m, seq[5], cell) }
		local pinned: { [number]: any } = {}
		local function leg(k: number, p: any, q: any): (number, { any }, { number })
			if pinned[k] then
				local len, pts = Dungeon.funnel(m, pinned[k], p, q, cell, margin)
				return len, pts, pinned[k]
			end
			return legLen(ls[k], p, q)
		end
		local function descend(v0: { any }): (number, { any }, { any }, { any })
			local v = table.clone(v0)
			local lens, polys, cellsOf = {}, {}, {}
			for k = 1, 4 do lens[k], polys[k], cellsOf[k] = leg(k, v[k], v[k + 1]) end
			local function total(): number return lens[1] + lens[2] + lens[3] + lens[4] end
			if total() == math.huge then return math.huge, v, polys, cellsOf end
			for _ = 1, 100 do
				local before = total()
				for idx = 1, 5 do
					local prop
					if idx == 1 then
						local B = polys[1][2]
						prop = { x = math.clamp(B.x, lo, hi), y = lineY }
					elseif idx == 5 then
						prop = onCircle(polys[4][#polys[4] - 1], centres[5], rd)
					else
						prop = discPoint(polys[idx - 1][#polys[idx - 1] - 1], polys[idx][2], centres[idx], rs)
					end
					local cur = v[idx]
					local t = 1
					for _ = 1, 8 do
						local cand = { x = cur.x + (prop.x - cur.x) * t, y = cur.y + (prop.y - cur.y) * t }
						if idx == 5 then cand = onCircle(cand, centres[5], rd) end
						local oldSum, newSum = 0, 0
						local la, pa, ca, lb, pb, cb
						if idx > 1 then
							la, pa, ca = leg(idx - 1, v[idx - 1], cand)
							oldSum += lens[idx - 1]
							newSum += la
						end
						if idx < 5 then
							lb, pb, cb = leg(idx, cand, v[idx + 1])
							oldSum += lens[idx]
							newSum += lb
						end
						if newSum < oldSum - 1e-9 then
							v[idx] = cand
							if idx > 1 then lens[idx - 1], polys[idx - 1], cellsOf[idx - 1] = la, pa, ca end
							if idx < 5 then lens[idx], polys[idx], cellsOf[idx] = lb, pb, cb end
							break
						end
						t *= 0.5
					end
				end
				if before - total() < 1e-7 then break end
			end
			return total(), v, polys, cellsOf
		end
		local bestT, bestV, bestP, bestC = descend({ sRef, centres[2], centres[3], centres[4], onCircle(sRef, centres[5], rd) })
		if bestT == math.huge then return bestT, bestV, bestP, bestC end
		for _ = 1, 4 do
			local improved = false
			for k = 1, 4 do
				for _, cells in ls[k].paths do
					if cells ~= bestC[k] then
						pinned[k] = cells
						local _, v1 = descend(bestV)
						pinned[k] = nil
						local t2, v2, p2, c2 = descend(v1)
						if t2 < bestT - 1e-6 then
							bestT, bestV, bestP, bestC = t2, v2, p2, c2
							improved = true
						end
					end
				end
			end
			if not improved then break end
		end
		return bestT, bestV, bestP, bestC
	end
	-- orders by their centre line's lower bound; one that cannot beat the best so far is skipped
	-- (each free point moves its two legs by at most its reach)
	local order = {}
	for k, o in PERMS do
		local seq = { e, pl.seals[o[1]], pl.seals[o[2]], pl.seals[o[3]], pl.door }
		local bound = 0
		for j = 1, 4 do
			local l = legOf(seq[j], seq[j + 1], j == 1)
			bound += l.best - l.reach
		end
		table.insert(order, { k = k, o = o, seq = seq, bound = bound })
	end
	table.sort(order, function(a: any, b: any): boolean
		if a.bound ~= b.bound then return a.bound < b.bound end
		return a.k < b.k
	end)
	local best, bestOrder, bestPolys, bestCells, bestStart = math.huge, nil, nil, nil, nil
	for _, it in order do
		if it.bound < best - 1e-9 then
			local len, v, polys, cellsOf = solve(it.seq)
			if len < best - 1e-9 then
				best, bestOrder, bestPolys, bestCells, bestStart = len, it.o, polys, cellsOf, v[1]
			end
		end
	end
	if bestOrder == nil or best == math.huge then return math.huge, {}, nil, {} end
	local points, cells = { { x = bestStart.x, z = bestStart.y } }, { e }
	for k = 1, 4 do
		local pts = bestPolys[k]
		for j = 2, #pts do table.insert(points, { x = pts[j].x, z = pts[j].y }) end
		local cs = bestCells[k]
		for j = 2, #cs do table.insert(cells, cs[j]) end
	end
	return best, points, bestOrder, cells
end

function Dungeon.perfectMs(cfg: any, m: any, pl: any): number
	local len = Dungeon.tightLine(cfg, m, pl)
	return math.floor(len / cfg.Walk.Speed * 1000 + 0.5)
end

--======================================================================== the record

function Dungeon.encodeOpen(m: any): string
	local bits = {}
	for i = 0, m.W * m.H - 1 do
		table.insert(bits, if m.openE[i] then 1 else 0)
		table.insert(bits, if m.openN[i] then 1 else 0)
	end
	while #bits % 4 ~= 0 do table.insert(bits, 0) end
	local out = {}
	for k = 1, #bits, 4 do
		local v = bits[k] * 8 + bits[k + 1] * 4 + bits[k + 2] * 2 + bits[k + 3]
		table.insert(out, string.sub(HEX, v + 1, v + 1))
	end
	return table.concat(out)
end

-- The maze, or nil when the string is malformed or opens a passage through the perimeter.
function Dungeon.decodeOpen(s: any, W: number, H: number): any?
	if type(s) ~= "string" then return nil end
	local nbits = 2 * W * H
	local want = math.ceil(nbits / 4)
	if #s ~= want then return nil end
	local bits = {}
	for k = 1, #s do
		local ch = string.sub(s, k, k)
		local v = string.find(HEX, ch, 1, true)
		if v == nil then return nil end
		v -= 1
		table.insert(bits, bit32.band(bit32.rshift(v, 3), 1))
		table.insert(bits, bit32.band(bit32.rshift(v, 2), 1))
		table.insert(bits, bit32.band(bit32.rshift(v, 1), 1))
		table.insert(bits, bit32.band(v, 1))
	end
	for k = nbits + 1, #bits do
		if bits[k] ~= 0 then return nil end
	end
	local m = Dungeon.newMaze(W, H)
	for i = 0, W * H - 1 do
		m.openE[i] = bits[2 * i + 1] == 1
		m.openN[i] = bits[2 * i + 2] == 1
		local x, y = i % W, i // W
		if (x == W - 1 and m.openE[i]) or (y == H - 1 and m.openN[i]) then return nil end
	end
	return m
end

local function xy(m: any, i: number): any
	return { x = i % m.W, y = i // m.W }
end

-- Mint a day: up to MaxAttempts draws; the first maze whose placement succeeds, whose perfect line
-- falls in the band and which takes 3 hazards is the day. (record?, attempts)
function Dungeon.mint(cfg: any, draw: (number) -> number, day: number, now: number): (any?, number)
	local attempts = 0
	while attempts < cfg.Perfect.MaxAttempts do
		attempts += 1
		local m = Dungeon.generate(cfg, draw)
		local pl = Dungeon.place(cfg, m, draw)
		if pl ~= nil then
			local pms = Dungeon.perfectMs(cfg, m, pl)
			if pms >= cfg.Perfect.MinSeconds * 1000 and pms <= cfg.Perfect.MaxSeconds * 1000 then
				local hz = Dungeon.pickHazards(cfg, m, pl, draw)
				if #hz == cfg.Hazards.Count then
					local hazards = {}
					for _, h in hz do
						local p = xy(m, h.cell)
						table.insert(hazards, { x = p.x, y = p.y, slot = h.slot })
					end
					return {
						v = cfg.Day.RecordVersion,
						day = day,
						w = m.W,
						h = m.H,
						open = Dungeon.encodeOpen(m),
						entrance = xy(m, pl.entrance),
						seals = { xy(m, pl.seals[1]), xy(m, pl.seals[2]), xy(m, pl.seals[3]) },
						door = xy(m, pl.door),
						hazards = hazards,
						perfectMs = pms,
						mintedAt = now,
					}, attempts
				end
			end
		end
	end
	return nil, attempts
end

-- The Studio fallback door (DESIGN §3.5): deterministic from Config.StudioDoorSeed, marked studio,
-- and never ranked (the server refuses to save or post anything from it).
function Dungeon.studioDoor(cfg: any, Rng: any, day: number, now: number): any?
	local r = Rng.new(cfg.StudioDoorSeed)
	local rec = Dungeon.mint(cfg, function(n) return r:below(n) end, day, now)
	if rec then rec.studio = true end
	return rec
end

local function isInt(x: any): boolean
	return type(x) == "number" and x == x and x % 1 == 0
end

-- (ok, err). Everything a server needs before building a day from a stored record. Fails closed.
function Dungeon.validate(cfg: any, rec: any, day: number?): (boolean, string?)
	if type(rec) ~= "table" then return false, "no record" end
	if rec.v ~= cfg.Day.RecordVersion then return false, "unknown record version " .. tostring(rec.v) end
	if day ~= nil and rec.day ~= day then return false, "the record is for day " .. tostring(rec.day) end
	local W, H = cfg.Grid.W, cfg.Grid.H
	if rec.w ~= W or rec.h ~= H then return false, "wrong dimensions" end
	local m = Dungeon.decodeOpen(rec.open, W, H)
	if m == nil then return false, "malformed passage string" end
	local function cellOf(p: any): number?
		if type(p) ~= "table" or not isInt(p.x) or not isInt(p.y) then return nil end
		if p.x < 0 or p.x >= W or p.y < 0 or p.y >= H then return nil end
		return p.y * W + p.x
	end
	local entrance = cellOf(rec.entrance)
	if entrance ~= cfg.Grid.EntranceY * W + cfg.Grid.EntranceX then return false, "wrong entrance" end
	if type(rec.seals) ~= "table" or #rec.seals ~= 3 then return false, "need 3 seals" end
	local seals = {}
	for k = 1, 3 do
		local c = cellOf(rec.seals[k])
		if c == nil then return false, "seal " .. k .. " is off the grid" end
		seals[k] = c
	end
	local door = cellOf(rec.door)
	if door == nil then return false, "the Door is off the grid" end
	local special = { [entrance :: number] = "entrance" }
	for k, c in seals do
		if special[c] then return false, "seal " .. k .. " shares a cell" end
		special[c] = "seal"
	end
	if special[door] then return false, "the Door shares a cell" end
	special[door] = "door"

	local dE = Dungeon.bfs(m, entrance :: number)
	for i = 0, W * H - 1 do
		if dE[i] == nil then return false, "a cell is unreachable" end
	end
	local maxE = 0
	for _, d in dE do maxE = math.max(maxE, d) end
	local d = distances(m)
	local P = cfg.Place
	if dE[seals[1]] < P.SealAMin or dE[seals[1]] > P.SealAMax then return false, "seal A breaks its rule" end
	for k = 2, 3 do
		if dE[seals[k]] < P.SealMin then return false, "a seal is too near the entrance" end
	end
	if d(seals[1], seals[2]) < P.SealSep or d(seals[1], seals[3]) < P.SealSep or d(seals[2], seals[3]) < P.SealSep then
		return false, "seals too close together"
	end
	if dE[door] < P.DoorFrac * maxE then return false, "the Door is too near" end
	for k = 1, 3 do
		if d(seals[k], door) < P.DoorSealSep then return false, "the Door is too near a seal" end
	end

	local hzc = cfg.Hazards
	if type(rec.hazards) ~= "table" or #rec.hazards ~= hzc.Count then return false, "wrong hazard count" end
	local slots, hcells = {}, {}
	for k = 1, hzc.Count do
		local h = rec.hazards[k]
		local c = cellOf(h)
		if c == nil then return false, "hazard " .. k .. " is off the grid" end
		if not isInt(h.slot) or h.slot < 1 or h.slot > hzc.Count or slots[h.slot] then return false, "bad hazard slot" end
		slots[h.slot] = true
		if special[c] then return false, "a hazard sits on the " .. special[c] end
		if dE[c] < hzc.MinFromEntrance then return false, "a hazard is too near the entrance" end
		if #Dungeon.neighbours(m, c) < hzc.MinOpenSides then return false, "a hazard is not on a fork" end
		for _, o in hcells do
			if d(o, c) < hzc.MinSpacing then return false, "hazards too close together" end
		end
		table.insert(hcells, c)
	end

	local pl = { entrance = entrance, seals = seals, door = door, dE = dE, maxE = maxE, d = d }
	local pms = Dungeon.perfectMs(cfg, m, pl)
	if not isInt(rec.perfectMs) or math.abs(pms - rec.perfectMs) > 1 then
		return false, "the perfect line does not match (" .. tostring(pms) .. " vs " .. tostring(rec.perfectMs) .. ")"
	end
	if pms < cfg.Perfect.MinSeconds * 1000 or pms > cfg.Perfect.MaxSeconds * 1000 then
		return false, "the perfect line is outside the band"
	end
	return true, nil
end

-- The in-memory day built from a VALID record.
function Dungeon.fromRecord(cfg: any, rec: any): any
	local W, H = rec.w, rec.h
	local m = Dungeon.decodeOpen(rec.open, W, H)
	local function c(p: any): number return p.y * W + p.x end
	local hazards = {}
	for _, h in rec.hazards do table.insert(hazards, { cell = c(h), slot = h.slot }) end
	table.sort(hazards, function(a: any, b: any): boolean return a.slot < b.slot end)
	local world = {
		maze = m, W = W, H = H,
		entrance = c(rec.entrance),
		seals = { c(rec.seals[1]), c(rec.seals[2]), c(rec.seals[3]) },
		door = c(rec.door),
		hazards = hazards,
		perfectMs = rec.perfectMs,
		day = rec.day,
		studio = rec.studio == true,
		kinds = {},
	}
	for k, s in world.seals do world.kinds[s] = { kind = "seal", slot = k } end
	world.kinds[world.door] = { kind = "door" }
	for _, h in hazards do world.kinds[h.cell] = { kind = "hazard", slot = h.slot } end
	return world
end

-- What the owning client is sent for one REVEALED cell: position, open sides (N1 E2 S4 W8) and
-- what stands in it. Nothing about any other cell.
function Dungeon.cellPayload(world: any, i: number): any
	local m = world.maze
	local W = m.W
	local x, y = i % W, i // W
	local sides = 0
	if y + 1 < m.H and m.openN[i] then sides += 1 end
	if x + 1 < W and m.openE[i] then sides += 2 end
	if (y > 0 and m.openN[i - W]) or i == world.entrance then sides += 4 end
	if x > 0 and m.openE[i - 1] then sides += 8 end
	local k = world.kinds[i]
	return { x = x, y = y, sides = sides, kind = if k then k.kind else nil, slot = if k and k.kind == "hazard" then k.slot else nil }
end

-- Every cell within `steps` open-passage steps of any cell in `from`: { [i] = true }.
function Dungeon.revealFrom(world: any, from: { number }, steps: number): { [number]: boolean }
	local m = world.maze
	local depth, q, head = {}, {}, 1
	for _, c in from do
		if depth[c] == nil then
			depth[c] = 0
			table.insert(q, c)
		end
	end
	while head <= #q do
		local c = q[head]
		head += 1
		if depth[c] < steps then
			for _, n in Dungeon.neighbours(m, c) do
				if depth[n] == nil then
					depth[n] = depth[c] + 1
					table.insert(q, n)
				end
			end
		end
	end
	local out = {}
	for c in depth do out[c] = true end
	return out
end

-- The day's P as lane-local points (Dungeon.tightLine), for walkers and checks (they ADDRESS the
-- route with it; nothing grades itself with it). Walked at 16 studs/s it finishes in P.
function Dungeon.perfectPath(cfg: any, world: any): (number, { any })
	local len, pts = Dungeon.tightLine(cfg, world.maze, { entrance = world.entrance, seals = world.seals, door = world.door })
	return len, pts
end

return Dungeon
