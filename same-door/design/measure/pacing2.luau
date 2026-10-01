--!strict
-- THROWAWAY pacing model for the design spec (the real one goes in same-door/tests/ later).
local M = require("./maze")
local CELL, WALK, MARGIN = 16, 16, 2.5
local RULES = { sealAMin = 3, sealAMax = 6, sealMin = 6, sealSep = 6, doorFrac = 0.6, doorSealSep = 4 }

local W, H, LOOPS = tonumber((...)) or 9, tonumber((select(2, ...))) or 9, tonumber((select(3, ...))) or 8
local SIGHT = 2 -- cells seen along a straight open corridor (built + lit)

-- human part, written down
local PROFILES = {
	fast = { effExplore = 0.95, decide = 0.3, deadEnd = 0.3, wander = 0.1, slop1 = 0.25, slopMin = 0.06, alpha = 0.6, hes = 0.5, qScout = 0.35, scoutCells = 6 },
	normal = { effExplore = 0.85, decide = 0.8, deadEnd = 0.6, wander = 0.25, slop1 = 0.35, slopMin = 0.12, alpha = 0.5, hes = 0.6, qScout = 0.25, scoutCells = 5 },
	slow = { effExplore = 0.75, decide = 1.5, deadEnd = 1.0, wander = 0.4, slop1 = 0.45, slopMin = 0.20, alpha = 0.4, hes = 0.7, qScout = 0.15, scoutCells = 4 },
}
local FIRST_OVERHEAD, RETRY_OVERHEAD = 10, 8
local SESSION_MINUTES = 90

local function ekey(a: number, b: number): string
	if a < b then return a .. "-" .. b end
	return b .. "-" .. a
end

-- memory: known passages (edges) + visited/seen cells + known contents
local function newMemory(): any
	return { edges = {}, adj = {}, visited = {}, seen = {}, sealAt = {}, doorAt = nil }
end
local function learnEdge(mem: any, a: number, b: number)
	local k = ekey(a, b)
	if mem.edges[k] then return end
	mem.edges[k] = true
	mem.adj[a] = mem.adj[a] or {}; table.insert(mem.adj[a], b)
	mem.adj[b] = mem.adj[b] or {}; table.insert(mem.adj[b], a)
end
local function look(m: any, p: any, mem: any, c: number)
	mem.seen[c] = true
	for _, n in M.neighbours(m, c) do
		learnEdge(mem, c, n)
		-- straight line
		local dx = n - c
		local prev, cur = c, n
		for _ = 1, SIGHT do
			mem.seen[cur] = true
			local nxt = cur + dx
			local ok = false
			for _, nn in M.neighbours(m, cur) do if nn == nxt then ok = true end end
			-- row wrap guard
			if math.abs(dx) == 1 and (nxt // m.W) ~= (cur // m.W) then ok = false end
			if not ok then break end
			learnEdge(mem, cur, nxt)
			prev, cur = cur, nxt
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
local function degree(m: any, c: number): number
	return #M.neighbours(m, c)
end

-- walk cell by cell along `path` (list incl. current as first), accumulating time; returns time, cells
local function exploreRun(m: any, p: any, mem: any, prof: any, rng: any, budgetCells: number?, startCell: number, sealsIn: any): (number, number, any, boolean)
	local t = 0
	local cur = startCell
	local held = sealsIn or { false, false, false }
	local nHeld = 0
	for s = 1, 3 do if held[s] then nHeld += 1 end end
	local steps = 0
	local stepT = CELL / (WALK * prof.effExplore)
	local function enter(c: number)
		if not mem.visited[c] then
			mem.visited[c] = true
			local d = degree(m, c)
			if d >= 3 then t += prof.decide elseif d == 1 then t += prof.deadEnd end
		end
		look(m, p, mem, c)
		for s = 1, 3 do if not held[s] and p.seals[s] == c then held[s] = true; nHeld += 1 end end
	end
	enter(cur)
	while true do
		if nHeld == 3 and cur == p.door then return t, steps, held, true end
		if budgetCells and steps >= budgetCells then return t, steps, held, false end
		local dist, parent = kbfs(mem, cur)
		local target = nil
		-- known uncollected seal?
		local bestD = math.huge
		for s = 1, 3 do
			if not held[s] and mem.sealAt[s] and dist[p.seals[s]] and dist[p.seals[s]] < bestD then
				bestD = dist[p.seals[s]]; target = p.seals[s]
			end
		end
		if target == nil and nHeld == 3 and mem.doorAt and dist[p.door] then target = p.door end
		if target == nil then
			-- nearest unvisited known cell (frontier), with some wandering
			local fr = {}
			local fbest = math.huge
			for c, d in dist do
				if not mem.visited[c] then
					table.insert(fr, { c, d })
					if d < fbest then fbest = d end
				end
			end
			if #fr == 0 then return t, steps, held, false end -- nothing left (should not happen)
			if rng:NextNumber() < prof.wander then
				target = fr[rng:NextInteger(1, #fr)][1]
			else
				local near = {}
				for _, f in fr do if f[2] == fbest then table.insert(near, f[1]) end end
				target = near[rng:NextInteger(1, #near)]
			end
		end
		-- move one step toward target
		local path = {}
		local c = target
		while c ~= cur do table.insert(path, 1, c); c = parent[c] end
		local nxt = path[1]
		t += stepT
		steps += 1
		cur = nxt
		enter(cur)
	end
end

local function knownRoute(mem: any, p: any): (number?, { number }?)
	local pts = {}
	local dists = {}
	local function d(a, b)
		if dists[a] == nil then dists[a] = { kbfs(mem, a) } end
		return dists[a][1][b]
	end
	local best, bo = math.huge, nil
	for _, o in M.PERMS do
		local s = p.seals
		local a1, a2, a3, a4 = d(p.entrance, s[o[1]]), d(s[o[1]], s[o[2]]), d(s[o[2]], s[o[3]]), d(s[o[3]], p.door)
		if a1 and a2 and a3 and a4 then
			local L = a1 + a2 + a3 + a4
			if L < best then best, bo = L, o end
		end
	end
	if bo == nil then return nil, nil end
	pts = { p.entrance, p.seals[bo[1]], p.seals[bo[2]], p.seals[bo[3]], p.door }
	local cells = { p.entrance }
	local wp = { 1 }
	for k = 1, 4 do
		local _, parent = kbfs(mem, pts[k])
		local seg = { pts[k + 1] }
		local c = pts[k + 1]
		while c ~= pts[k] do c = parent[c]; table.insert(seg, 1, c) end
		for j = 2, #seg do table.insert(cells, seg[j]) end
		table.insert(wp, #cells)
	end
	return best, { cells = cells, wp = wp } :: any
end

local function routeFunnel(m: any, r: any): number
	local total = 0
	local e = r.cells[1]
	local startPt = { x = (e % m.W + 0.5) * CELL, y = (e // m.W) * CELL }
	for k = 1, 4 do
		local a, b = r.wp[k], r.wp[k + 1]
		local seg = {}
		for j = a, b do table.insert(seg, r.cells[j]) end
		local s = if k == 1 then startPt else M.centre(m, r.cells[a], CELL)
		total += M.funnel(m, seg, s, M.centre(m, r.cells[b], CELL), CELL, MARGIN, false)
	end
	return total
end

local function countForks(m: any, r: any): number
	local n = 0
	for _, c in r.cells do if degree(m, c) >= 3 then n += 1 end end
	return n
end

local function session(m: any, p: any, prof: any, rng: any, thresholds: { number }): any
	local mem = newMemory()
	local clock = FIRST_OVERHEAD
	local reached = {}
	local times = {}
	-- run 1: exploration from the entrance (half a cell from the line)
	local t1 = exploreRun(m, p, mem, prof, rng, nil, p.entrance, nil)
	t1 += 0.5 * CELL / (WALK * prof.effExplore)
	clock += t1
	table.insert(times, t1)
	local function mark(t: number)
		for i, thr in thresholds do
			if reached[i] == nil and t <= thr then reached[i] = clock / 60 end
		end
	end
	mark(t1)
	local r = 1
	while clock < SESSION_MINUTES * 60 do
		r += 1
		clock += RETRY_OVERHEAD
		local _, route = knownRoute(mem, p)
		local slop = prof.slopMin + (prof.slop1 - prof.slopMin) * (r - 1) ^ (-prof.alpha)
		local t = routeFunnel(m, route) * (1 + slop) / WALK + countForks(m, route) * prof.decide * prof.hes ^ (r - 1)
		if rng:NextNumber() < prof.qScout then
			-- a scouting run: from a random route cell, explore up to scoutCells new cells, then finish
			local idx = rng:NextInteger(1, #route.cells)
			local c0 = route.cells[idx]
			local ts, st = exploreRun(m, p, mem, prof, rng, prof.scoutCells, c0, { true, true, true })
			t += ts * 2 -- out and back, roughly
		end
		clock += t
		table.insert(times, t)
		mark(t)
	end
	return { reached = reached, times = times, runs = r }
end

local function pct(t, q)
	local c = table.clone(t)
	table.sort(c)
	if #c == 0 then return 0 / 0 end
	return c[math.max(1, math.floor(#c * q + 0.5))]
end


local N = tonumber((select(4, ...))) or 200
local SWEEP = { 1.10, 1.14, 1.16, 1.18, 1.20, 1.22, 1.25, 1.30, 1.40, 1.60, 2.00 }
print(string.format("grid %dx%d loops %d, %d days, session %d min; minutes to first run <= mult x perfect line (median over days / p90 / days never)", W, H, LOOPS, N, SESSION_MINUTES))
for _, pname in { "fast", "normal", "slow" } do
	local prof = PROFILES[pname]
	local first, perfects, runsPerMin = {}, {}, {}
	local hit = {}
	for k in SWEEP do hit[k] = {} end
	local never = {}
	for k in SWEEP do never[k] = 0 end
	local lastBest = {}
	for s = 1, N do
		local rng = M.rng(s * 104729 + 17)
		local e = { W // 2, 0 }
		local m, p
		repeat
			m = M.generate(W, H, LOOPS, rng, e)
			p = M.place(m, e[2] * W + e[1], RULES, rng)
		until p
		local r = M.route(m, p)
		local perfect = routeFunnel(m, { cells = r.cells, wp = r.waypointAt }) / WALK
		table.insert(perfects, perfect)
		local thr = {}
		for k, mult in SWEEP do thr[k] = perfect * mult end
		local res = session(m, p, prof, M.rng(s * 31 + 5), thr)
		table.insert(first, res.times[1])
		table.insert(runsPerMin, res.runs / SESSION_MINUTES)
		local best = math.huge
		for _, t in res.times do if t < best then best = t end end
		table.insert(lastBest, best / perfect)
		for k in SWEEP do
			if res.reached[k] then table.insert(hit[k], res.reached[k]) else never[k] += 1 end
		end
	end
	print(string.format("  %s: first run s p10 %.0f p50 %.0f p90 %.0f | perfect line s p50 %.1f | runs/min %.2f | best after %d min x perfect p50 %.3f p10 %.3f p90 %.3f",
		pname, pct(first, 0.1), pct(first, 0.5), pct(first, 0.9), pct(perfects, 0.5), pct(runsPerMin, 0.5), SESSION_MINUTES, pct(lastBest, 0.5), pct(lastBest, 0.1), pct(lastBest, 0.9)))
	local line = "    "
	for k, mult in SWEEP do
		line ..= string.format("x%.2f: %s/%s/%d  ", mult,
			#hit[k] > 0 and string.format("%.1f", pct(hit[k], 0.5)) or "-",
			#hit[k] > 0 and string.format("%.1f", pct(hit[k], 0.9)) or "-", never[k])
	end
	print(line)
end
