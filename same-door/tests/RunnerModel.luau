--!strict
-- RunnerModel.luau — the pacing model behind the brag-moment minutes (DESIGN §6.3). NOT game code.
--
-- Rebuilt from same-door/design/measure/model.luau, but on the GAME's own generator
-- (src/server/Dungeon.mint, read through the repo's Rng) and the GAME's own hazard schedule and
-- geometry (src/shared/DoorHazards, Config). Numbers from here hold under the written-down player
-- assumptions below, not for real players.
--
-- * First run (exploration): the player walks at effExplore * 16 studs/s and sees 2 cells down
--   straight open corridors. They go for the nearest known seal, then the Door; otherwise to the
--   nearest unvisited known cell (or a random one with probability `wander`). They pause `decide` s
--   at a new fork and `deadEnd` s at a dead end.
-- * Later runs: the best CENTRE line over the passages they KNOW (Dungeon.bestLine at PLAN_MARGIN:
--   every seal order, the shortest string-pulled path per leg between seal centres); run time = its length
--   * (1 + slop) / 16 + fork hesitation that decays per run. Slop follows the power law
--   of practice slopMin + (slop1 - slopMin) * (r - 1)^-alpha with lognormal run-to-run variance and an
--   occasional 1-4 s mistake. With probability qScout a run also scouts scoutCells unknown cells.
-- * Each retry costs RETRY_OVERHEAD s (finish card to the line); the first run FIRST_OVERHEAD s.
local Dungeon = require("../src/server/Dungeon")
local DoorHazards = require("../src/shared/DoorHazards")
local Rng = require("../src/shared/Rng")

local X = {}

X.SIGHT = 2
-- How a player plans: through the middle of each seal, 2.5 studs off a jamb (wall half-thickness 1 +
-- a 1.5 player radius, the first build's P margin). The day's P (REVIEW-1) is the tighter line the
-- server's check measures: 2 studs off the jambs, grazing each pickup circle, from anywhere on the
-- line. The slop below is relative to THIS planned line, as the design model calibrated it.
X.PLAN_MARGIN = 2.5
X.FIRST_OVERHEAD, X.RETRY_OVERHEAD = 10, 8
X.PROFILES = {
	fast = { effExplore = 0.95, decide = 0.3, deadEnd = 0.3, wander = 0.1, slop1 = 0.25, slopMin = 0.06, alpha = 0.6, sigma = 0.35, pMistake = 0.15, hes = 0.5, qScout = 0.35, scoutCells = 6, sessionMin = 30 },
	normal = { effExplore = 0.85, decide = 0.8, deadEnd = 0.6, wander = 0.25, slop1 = 0.35, slopMin = 0.12, alpha = 0.5, sigma = 0.35, pMistake = 0.25, hes = 0.6, qScout = 0.25, scoutCells = 5, sessionMin = 20 },
	slow = { effExplore = 0.75, decide = 1.5, deadEnd = 1.0, wander = 0.4, slop1 = 0.45, slopMin = 0.20, alpha = 0.4, sigma = 0.35, pMistake = 0.35, hes = 0.7, qScout = 0.15, scoutCells = 4, sessionMin = 15 },
}

-- A player-side random source with the same interface the design model used.
function X.rng(seed: number): any
	local r = Rng.new(seed)
	return {
		NextNumber = function(_self: any): number return r:next() end,
		NextInteger = function(_self: any, a: number, b: number): number return a - 1 + r:below(b - a + 1) end,
	}
end

-- One day from the game's own generator. { m, p = {entrance, seals, door, dE, d}, perfect, hazards }
function X.makeDay(cfg: any, seed: number): any
	local r = Rng.new(seed)
	local rec = Dungeon.mint(cfg, function(n) return r:below(n) end, 20726, 0)
	assert(rec ~= nil, "the generator failed to mint a day")
	local world = Dungeon.fromRecord(cfg, rec :: any)
	local m = world.maze
	local cache = {}
	local function d(a: number, b: number): number
		if cache[a] == nil then cache[a] = (Dungeon.bfs(m, a)) end
		return cache[a][b] or math.huge
	end
	local p = { entrance = world.entrance, seals = world.seals, door = world.door, dE = (Dungeon.bfs(m, world.entrance)), d = d }
	return { m = m, p = p, world = world, perfect = rec.perfectMs / 1000, hazards = world.hazards, rec = rec }
end

local function ekey(a: number, b: number): string
	if a < b then return a .. "-" .. b end
	return b .. "-" .. a
end
function X.newMemory(): any
	return { edges = {}, edgeCount = 0, adj = {}, visited = {}, seen = {}, sealAt = {}, doorAt = nil, line = nil }
end
local function learnEdge(mem: any, a: number, b: number)
	local k = ekey(a, b)
	if mem.edges[k] then return end
	mem.edges[k] = true
	mem.edgeCount += 1
	mem.adj[a] = mem.adj[a] or {}; table.insert(mem.adj[a], b)
	mem.adj[b] = mem.adj[b] or {}; table.insert(mem.adj[b], a)
end
local function look(m: any, p: any, mem: any, c: number)
	mem.seen[c] = true
	for _, n in Dungeon.neighbours(m, c) do
		learnEdge(mem, c, n)
		local dx = n - c
		local cur = n
		for _ = 1, X.SIGHT do
			mem.seen[cur] = true
			local nxt = cur + dx
			local ok = false
			for _, nn in Dungeon.neighbours(m, cur) do if nn == nxt then ok = true end end
			if not ok then break end
			learnEdge(mem, cur, nxt)
			cur = nxt
		end
	end
	for s = 1, 3 do if mem.seen[p.seals[s]] then mem.sealAt[s] = true end end
	if mem.seen[p.door] then mem.doorAt = true end
end
local function kbfs(mem: any, src: number): ({ [number]: number }, { [number]: number })
	local dist, parent = { [src] = 0 }, {}
	local q, h = { src }, 1
	while h <= #q do
		local c = q[h]; h += 1
		for _, n in (mem.adj[c] or {}) do
			if dist[n] == nil then dist[n] = dist[c] + 1; parent[n] = c; table.insert(q, n) end
		end
	end
	return dist, parent
end

-- trace = { {cell, tEnter} ... } in run seconds. (time, finished)
function X.explore(cfg: any, m: any, p: any, mem: any, prof: any, rng: any, budget: number?, startCell: number, held0: any, t0: number, trace: any): (number, boolean)
	local t = t0
	local cur = startCell
	local held = held0 or { false, false, false }
	local nHeld = 0
	for s = 1, 3 do if held[s] then nHeld += 1 end end
	local steps = 0
	local stepT = cfg.Grid.Cell / (cfg.Walk.Speed * prof.effExplore)
	local function enter(c: number)
		table.insert(trace, { c, t })
		if not mem.visited[c] then
			mem.visited[c] = true
			local deg = #Dungeon.neighbours(m, c)
			if deg >= 3 then t += prof.decide elseif deg == 1 then t += prof.deadEnd end
		end
		look(m, p, mem, c)
		for s = 1, 3 do if not held[s] and p.seals[s] == c then held[s] = true; nHeld += 1 end end
	end
	enter(cur)
	while true do
		if nHeld == 3 and cur == p.door then return t, true end
		if budget and steps >= budget then return t, false end
		local dist, parent = kbfs(mem, cur)
		local target = nil
		local bestD = math.huge
		for s = 1, 3 do
			if not held[s] and mem.sealAt[s] and dist[p.seals[s]] and dist[p.seals[s]] < bestD then
				bestD = dist[p.seals[s]]; target = p.seals[s]
			end
		end
		if target == nil and nHeld == 3 and mem.doorAt and dist[p.door] then target = p.door end
		if target == nil then
			local fr, fbest = {}, math.huge
			for c, dd in dist do
				if not mem.visited[c] then
					table.insert(fr, { c, dd })
					if dd < fbest then fbest = dd end
				end
			end
			if #fr == 0 then return t, false end
			table.sort(fr, function(a: any, b: any): boolean return a[1] < b[1] end)
			if rng:NextNumber() < prof.wander then
				target = fr[rng:NextInteger(1, #fr)][1]
			else
				local near = {}
				for _, f in fr do if f[2] == fbest then table.insert(near, f[1]) end end
				target = near[rng:NextInteger(1, #near)]
			end
		end
		local c = target :: number
		local nxt = c
		while c ~= cur do nxt = c; c = parent[c] end
		t += stepT
		steps += 1
		cur = nxt
		enter(cur)
	end
end

-- The best centre line over the passages the player KNOWS: the game's own Dungeon.bestLine (every
-- seal order, the shortest string-pulled path per leg, at PLAN_MARGIN) on a maze holding only the
-- known edges. Cached
-- until the player learns a new edge (scouting). { len (studs), cells }, or nil when the known
-- passages do not connect every seal and the Door.
function X.knownLine(cfg: any, m: any, mem: any, p: any): any?
	if mem.line and mem.line.edges == mem.edgeCount then return mem.line.value end
	local km = Dungeon.newMaze(m.W, m.H)
	for k in mem.edges do
		local a, b = string.match(k, "^(%d+)%-(%d+)$")
		local x, y = tonumber(a) :: number, tonumber(b) :: number
		if y == x + 1 then km.openE[x] = true else km.openN[x] = true end
	end
	local len, _, _, cells = Dungeon.bestLine(cfg, km, { entrance = p.entrance, seals = p.seals, door = p.door }, X.PLAN_MARGIN)
	local value = if len < math.huge then { len = len, cells = cells } else nil
	mem.line = { edges = mem.edgeCount, value = value }
	return value
end

-- Near-misses and would-be hits over one run: for every impact of every hazard in [0, tEnd], the
-- runner's position (interpolated between cell centres of the trace) against the hazard centre.
-- near: within NearRadius (12 studs, labyrint's definition). hit: within the ring (4 studs) for a
-- runner who IGNORES warnings (a runner who reacts steps out of the ring and counts a near-miss).
function X.hazardEvents(cfg: any, m: any, trace: any, tEnd: number, hazards: { any }): (number, number)
	local hz = cfg.Hazards
	local c = cfg.Grid.Cell
	local near, hits = 0, 0
	local function posAt(T: number): (number, number)
		local j = 1
		while trace[j + 1] and trace[j + 1][2] <= T do j += 1 end
		local a = trace[j]
		local b = trace[j + 1]
		local ax, az = (a[1] % m.W + 0.5) * c, (a[1] // m.W + 0.5) * c
		if b == nil then return ax, az end
		local bx, bz = (b[1] % m.W + 0.5) * c, (b[1] // m.W + 0.5) * c
		local f = math.clamp((T - a[2]) / math.max(b[2] - a[2], 1e-9), 0, 1)
		return ax + (bx - ax) * f, az + (bz - az) * f
	end
	for _, h in hazards do
		local hx, hz2 = (h.cell % m.W + 0.5) * c, (h.cell // m.W + 0.5) * c
		local n = 0
		while true do
			local T = DoorHazards.impactTime(h.slot, n, hz)
			if T > tEnd then break end
			local x, z = posAt(T)
			local dd = math.sqrt((x - hx) ^ 2 + (z - hz2) ^ 2)
			if dd <= hz.NearRadius then near += 1 end
			if dd <= DoorHazards.ringRadius(hz) then hits += 1 end
			n += 1
		end
	end
	return near, hits
end

-- One day's session. thresholds: seconds. Returns { reached = {clock s per threshold}, runs,
-- running (s), near, hits, firstRun (s), clock }.
function X.day(cfg: any, day: any, prof: any, rng: any, thresholds: { number }, minutes: number): any
	local m, p = day.m, day.p
	local mem = X.newMemory()
	local clock = X.FIRST_OVERHEAD
	local reached, running, near, hits = {}, 0, 0, 0
	local function mark(t: number)
		for i, thr in thresholds do
			if reached[i] == nil and t <= thr then reached[i] = clock end
		end
	end
	local trace = {}
	local t1 = X.explore(cfg, m, p, mem, prof, rng, nil, p.entrance, nil,
		0.5 * cfg.Grid.Cell / (cfg.Walk.Speed * prof.effExplore), trace)
	local n1, h1 = X.hazardEvents(cfg, m, trace, t1, day.hazards)
	near += n1; hits += h1
	clock += t1; running += t1
	mark(t1)
	local r = 1
	while clock < minutes * 60 do
		r += 1
		clock += X.RETRY_OVERHEAD
		local route = X.knownLine(cfg, m, mem, p) :: any
		local slop = prof.slopMin + (prof.slop1 - prof.slopMin) * (r - 1) ^ (-prof.alpha)
		local u1, u2 = math.max(rng:NextNumber(), 1e-9), rng:NextNumber()
		local zz = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
		slop = slop * math.exp(prof.sigma * zz - prof.sigma * prof.sigma / 2)
		local forks = 0
		for _, c in route.cells do if #Dungeon.neighbours(m, c) >= 3 then forks += 1 end end
		local t = route.len * (1 + slop) / cfg.Walk.Speed + forks * prof.decide * prof.hes ^ (r - 1)
		if rng:NextNumber() < prof.pMistake then t += 1 + 3 * rng:NextNumber() end
		local tr = {}
		for j, c in route.cells do table.insert(tr, { c, (j - 1) * t / #route.cells }) end
		if rng:NextNumber() < prof.qScout then
			local idx = rng:NextInteger(1, #route.cells)
			local tScout = X.explore(cfg, m, p, mem, prof, rng, prof.scoutCells, route.cells[idx], { true, true, true }, 0, {})
			t += tScout * 2
		end
		local n2, h2 = X.hazardEvents(cfg, m, tr, t, day.hazards)
		near += n2; hits += h2
		clock += t; running += t
		mark(t)
	end
	return { reached = reached, runs = r, running = running, near = near, hits = hits, firstRun = t1, clock = clock }
end

function X.pct(t: { number }, q: number): number
	local c = table.clone(t)
	table.sort(c)
	if #c == 0 then return 0 / 0 end
	return c[math.max(1, math.floor(#c * q + 0.5))]
end

return X
