--!strict
-- THROWAWAY: player model + hazard schedule for the The Same Door spec. Reuses maze.luau.
local M = require("./maze")
local X = {}

X.CELL, X.WALK, X.MARGIN, X.SIGHT = 16, 16, 2.5, 2
X.RULES = { sealAMin = 3, sealAMax = 6, sealMin = 6, sealSep = 6, doorFrac = 0.6, doorSealSep = 4 }
X.PROFILES = {
	fast = { effExplore = 0.95, decide = 0.3, deadEnd = 0.3, wander = 0.1, slop1 = 0.25, slopMin = 0.06, alpha = 0.6, sigma = 0.35, pMistake = 0.15, hes = 0.5, qScout = 0.35, scoutCells = 6, sessionMin = 30 },
	normal = { effExplore = 0.85, decide = 0.8, deadEnd = 0.6, wander = 0.25, slop1 = 0.35, slopMin = 0.12, alpha = 0.5, sigma = 0.35, pMistake = 0.25, hes = 0.6, qScout = 0.25, scoutCells = 5, sessionMin = 20 },
	slow = { effExplore = 0.75, decide = 1.5, deadEnd = 1.0, wander = 0.4, slop1 = 0.45, slopMin = 0.20, alpha = 0.4, sigma = 0.35, pMistake = 0.35, hes = 0.7, qScout = 0.15, scoutCells = 4, sessionMin = 15 },
}
X.FIRST_OVERHEAD, X.RETRY_OVERHEAD = 10, 8

local function ekey(a: number, b: number): string
	if a < b then return a .. "-" .. b end
	return b .. "-" .. a
end
function X.newMemory(): any
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
		local dx = n - c
		local cur = n
		for _ = 1, X.SIGHT do
			mem.seen[cur] = true
			local nxt = cur + dx
			local ok = false
			for _, nn in M.neighbours(m, cur) do if nn == nxt then ok = true end end
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

-- trace = { {cell, tEnter} ... } in run seconds
function X.explore(m: any, p: any, mem: any, prof: any, rng: any, budget: number?, startCell: number, held0: any, t0: number, trace: any): (number, boolean)
	local t = t0
	local cur = startCell
	local held = held0 or { false, false, false }
	local nHeld = 0
	for s = 1, 3 do if held[s] then nHeld += 1 end end
	local steps = 0
	local stepT = X.CELL / (X.WALK * prof.effExplore)
	local function enter(c: number)
		table.insert(trace, { c, t })
		if not mem.visited[c] then
			mem.visited[c] = true
			local d = #M.neighbours(m, c)
			if d >= 3 then t += prof.decide elseif d == 1 then t += prof.deadEnd end
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
			for c, d in dist do
				if not mem.visited[c] then
					table.insert(fr, { c, d })
					if d < fbest then fbest = d end
				end
			end
			if #fr == 0 then return t, false end
			if rng:NextNumber() < prof.wander then
				target = fr[rng:NextInteger(1, #fr)][1]
			else
				local near = {}
				for _, f in fr do if f[2] == fbest then table.insert(near, f[1]) end end
				target = near[rng:NextInteger(1, #near)]
			end
		end
		local c = target
		local nxt = c
		while c ~= cur do nxt = c; c = parent[c] end
		t += stepT
		steps += 1
		cur = nxt
		enter(cur)
	end
end

function X.knownRoute(mem: any, p: any): (number?, any)
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
	local pts = { p.entrance, p.seals[bo[1]], p.seals[bo[2]], p.seals[bo[3]], p.door }
	local cells, wp = { p.entrance }, { 1 }
	for k = 1, 4 do
		local _, parent = kbfs(mem, pts[k])
		local seg = { pts[k + 1] }
		local c = pts[k + 1]
		while c ~= pts[k] do c = parent[c]; table.insert(seg, 1, c) end
		for j = 2, #seg do table.insert(cells, seg[j]) end
		table.insert(wp, #cells)
	end
	return best, { cells = cells, wp = wp }
end

function X.routeFunnel(m: any, r: any): number
	local total = 0
	local e = r.cells[1]
	local startPt = { x = (e % m.W + 0.5) * X.CELL, y = (e // m.W) * X.CELL }
	for k = 1, 4 do
		local a, b = r.wp[k], r.wp[k + 1]
		local seg = {}
		for j = a, b do table.insert(seg, r.cells[j]) end
		local s = if k == 1 then startPt else M.centre(m, r.cells[a], X.CELL)
		total += M.funnel(m, seg, s, M.centre(m, r.cells[b], X.CELL), X.CELL, X.MARGIN, false)
	end
	return total
end

-- hazards: count cells, dE >= minE, not entrance/seal/door, pairwise >= sep; onRoute forces the first onto the par route
function X.placeHazards(m: any, p: any, parCells: { number }, hz: any, rng: any): { number }
	local banned = { [p.entrance] = true, [p.door] = true, [p.seals[1]] = true, [p.seals[2]] = true, [p.seals[3]] = true }
	local out = {}
	local function ok(c: number): boolean
		if banned[c] or p.dE[c] == nil or p.dE[c] < hz.minE then return false end
		if hz.minDegree and #M.neighbours(m, c) < hz.minDegree then return false end
		for _, h in out do if p.d(h, c) < hz.sep then return false end end
		return true
	end
	if hz.onRoute then
		local cand = {}
		for _, c in parCells do if ok(c) then table.insert(cand, c) end end
		if #cand > 0 then table.insert(out, cand[rng:NextInteger(1, #cand)]) end
	end
	local tries = 0
	while #out < hz.count and tries < 500 do
		tries += 1
		local c = rng:NextInteger(0, m.W * m.H - 1)
		if ok(c) then table.insert(out, c) end
	end
	return out
end

-- impacts of hazard i at t = grace + (i-1)*P/count + k*P
function X.nearMisses(trace: any, tEnd: number, hazards: { number }, hz: any): number
	local n = 0
	local slot = hz.period / hz.count
	for i, h in hazards do
		local off = hz.grace + (i - 1) * slot
		for j, e in trace do
			if e[1] == h then
				local tin = e[2]
				local tout = if trace[j + 1] then trace[j + 1][2] else tEnd
				local lo, hi = tin - hz.near, tout + hz.near
				local k0 = math.max(0, math.ceil((lo - off) / hz.period))
				local T = off + k0 * hz.period
				while T <= hi do
					n += 1
					T += hz.period
				end
			end
		end
	end
	return n
end

-- one day's session: returns list of runs {t, runTime}, clock minutes when each threshold first met,
-- running seconds and near-miss count
function X.day(m: any, p: any, prof: any, rng: any, thresholds: { number }, minutes: number, hazards: { number }, hz: any): any
	local mem = X.newMemory()
	local clock = X.FIRST_OVERHEAD
	local reached, runs, running, near = {}, 0, 0, 0
	local function mark(t: number)
		for i, thr in thresholds do
			if reached[i] == nil and t <= thr then reached[i] = clock end
		end
	end
	local trace = {}
	local t1 = X.explore(m, p, mem, prof, rng, nil, p.entrance, nil, 0.5 * X.CELL / (X.WALK * prof.effExplore), trace)
	near += X.nearMisses(trace, t1, hazards, hz)
	clock += t1; running += t1; runs = 1
	mark(t1)
	local r = 1
	while clock < minutes * 60 do
		r += 1
		clock += X.RETRY_OVERHEAD
		local _, route = X.knownRoute(mem, p)
		local slop = prof.slopMin + (prof.slop1 - prof.slopMin) * (r - 1) ^ (-prof.alpha)
		local u1, u2 = math.max(rng:NextNumber(), 1e-9), rng:NextNumber()
		local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
		slop = slop * math.exp(prof.sigma * z - prof.sigma * prof.sigma / 2)
		local forks = 0
		for _, c in route.cells do if #M.neighbours(m, c) >= 3 then forks += 1 end end
		local t = X.routeFunnel(m, route) * (1 + slop) / X.WALK + forks * prof.decide * prof.hes ^ (r - 1)
		if rng:NextNumber() < prof.pMistake then t += 1 + 3 * rng:NextNumber() end
		local tr = {}
		for j, c in route.cells do table.insert(tr, { c, (j - 1) * t / #route.cells }) end
		if rng:NextNumber() < prof.qScout then
			local idx = rng:NextInteger(1, #route.cells)
			local tScout = X.explore(m, p, mem, prof, rng, prof.scoutCells, route.cells[idx], { true, true, true }, 0, {})
			t += tScout * 2
		end
		near += X.nearMisses(tr, t, hazards, hz)
		clock += t; running += t
		mark(t)
	end
	return { reached = reached, runs = r, running = running, near = near, clock = clock }
end

function X.makeDay(W: number, H: number, loops: number, rng: any, hz: any): any
	local e = { W // 2, 0 }
	local m, p
	repeat
		m = M.generate(W, H, loops, rng, e)
		p = M.place(m, e[2] * W + e[1], X.RULES, rng)
	until p
	local r = M.route(m, p)
	local perfect = X.routeFunnel(m, { cells = r.cells, wp = r.waypointAt }) / X.WALK
	local hazards = X.placeHazards(m, p, r.cells, hz, rng)
	return { m = m, p = p, r = r, perfect = perfect, hazards = hazards }
end

function X.pct(t: { number }, q: number): number
	local c = table.clone(t)
	table.sort(c)
	if #c == 0 then return 0 / 0 end
	return c[math.max(1, math.floor(#c * q + 0.5))]
end

return X
