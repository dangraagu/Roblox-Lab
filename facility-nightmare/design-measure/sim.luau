--!nocheck
-- DESIGN MEASUREMENT RIG for facility-nightmare/DESIGN.md. NOT GAME CODE.
-- A prototype planner + a blind model explorer + a blackout front, written only to derive the
-- spec's numbers. It is not the game's generator: do not copy it into src/. The real
-- src/shared/Facility.luau must re-produce DESIGN.md Appendix M1's table (same MazeGen, same draw
-- order) or the spec's numbers must be re-measured against the real module.
-- Rng.luau and MazeGen.luau here are verbatim copies of vault-runners/src/shared (md5 217e5d06...
-- and c269d302...), present only so `require("./X")` resolves in the luau CLI.
-- Run from this directory:  <luau>/luau.exe m1_nofront.luau 2>&1   (m1 .. m10)
local Rng = require("./Rng")
local MazeGen = require("./MazeGen")

local M = {}

M.CFG = {
	CellSize = 28,
	WalkSpeed = 16,
	DoorOpenSeconds = 0.5,
	PickupDetourSeconds = 0.9,
	ExtraDoorChance = 0.2,
	OnboardMaxDist = 2,
}

local function bfs(adj, n2, src)
	local d = {}
	for i = 1, n2 do d[i] = -1 end
	d[src] = 0
	local q, h = { src }, 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in adj[a] do
			if d[b] < 0 then d[b] = d[a] + 1; table.insert(q, b) end
		end
	end
	return d
end
M.bfs = bfs

function M.plan(n, layoutSeed, lootSeed, fuses, batteries, onboarding, cfg)
	cfg = cfg or M.CFG
	local rng = Rng.new(layoutSeed)
	local grid = MazeGen.generate(n, n, rng)
	local n2 = n * n
	local function id(x, y) return y * n + x + 1 end
	local adj = {}
	for i = 1, n2 do adj[i] = {} end
	local doors = 0
	local function link(a, b) table.insert(adj[a], b); table.insert(adj[b], a); doors += 1 end
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x < n - 1 then
				local open = grid[2 * y + 1][2 * x + 2] == false
				if not open and rng:next() < cfg.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x + 1, y)) end
			end
			if y < n - 1 then
				local open = grid[2 * y + 2][2 * x + 1] == false
				if not open and rng:next() < cfg.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x, y + 1)) end
			end
		end
	end
	-- entry: a perimeter cell
	local perim = {}
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 then table.insert(perim, id(x, y)) end
		end
	end
	local entry = perim[rng:below(#perim)]
	local d = bfs(adj, n2, entry)
	local maxD, far = 0, {}
	for i = 1, n2 do
		if d[i] > maxD then maxD = d[i]; far = { i } elseif d[i] == maxD then table.insert(far, i) end
	end
	local exit = far[rng:below(#far)]
	-- loot, independent stream
	local lr = Rng.new(lootSeed)
	local cand = {}
	for i = 1, n2 do if i ~= entry and i ~= exit then table.insert(cand, i) end end
	local item = {}
	local fuseRooms = {}
	local function take(list)
		local k = lr:below(#list)
		local r = list[k]
		table.remove(list, k)
		return r
	end
	local start = 1
	if onboarding then
		local near = {}
		for _, r in cand do if d[r] <= cfg.OnboardMaxDist then table.insert(near, r) end end
		if #near > 0 then
			local r = near[lr:below(#near)]
			for k, c in cand do if c == r then table.remove(cand, k) break end end
			item[r] = "fuse"; table.insert(fuseRooms, r); start = 2
		end
	end
	for _ = start, fuses do
		local r = take(cand); item[r] = "fuse"; table.insert(fuseRooms, r)
	end
	for _ = 1, batteries do
		if #cand > 0 then local r = take(cand); item[r] = "battery" end
	end
	return { n = n, n2 = n2, adj = adj, entry = entry, exit = exit, d = d, maxD = maxD,
		item = item, fuses = fuses, doors = doors }
end

-- Blind explorer. opts: speed (studs/s), front = {lead, step} or nil, battery = {cap, cell, grace, recover}
-- Returns a record.
function M.explore(p, opts, cfg)
	cfg = cfg or M.CFG
	local speed = opts.speed or cfg.WalkSpeed
	local stepT = cfg.CellSize / speed
	local front = opts.front
	local bat = opts.battery
	local function darkAt(r)
		if not front or r == p.exit then return math.huge end
		return front.lead + p.d[r] * front.step
	end
	local visited = { [p.entry] = true }
	local nVisited = 1
	local pos = p.entry
	local t = 0
	local held = 0
	local exitKnown = (p.entry == p.exit)
	local firstFuseT, firstFuseRooms = nil, nil
	local darkSec = 0
	local battery = bat and (bat.start or bat.cap) or 0
	local exposure = 0
	local died, diedAt = false, nil
	local revivesUsed = 0
	local firstDarkEntry = nil
	local minBattery = battery

	local function spend(room, dur)
		if died or dur <= 0 then t += math.max(dur, 0); return end
		local da = darkAt(room)
		local litDur = math.max(0, math.min(t + dur, da) - t)
		local darkDur = dur - litDur
		if litDur > 0 and bat then exposure = math.max(0, exposure - bat.recover * litDur) end
		if darkDur > 0 then
			darkSec += darkDur
			if bat then
				local fromBat = math.min(battery, darkDur)
				battery -= fromBat
				minBattery = math.min(minBattery, battery)
				local rest = darkDur - fromBat
				if rest > 0 then
					exposure += rest
					if exposure >= bat.grace then
						if (bat.revives or 0) > revivesUsed then
							-- Second Wind: cancel this death once, in place
							revivesUsed += 1
							exposure = 0
							battery = math.min(bat.cap, battery + (bat.reviveBattery or 0))
						else
							died = true
							diedAt = t + litDur + fromBat + (rest - (exposure - bat.grace))
						end
					end
				end
			end
		end
		t += dur
	end

	local function enter(r)
		if not visited[r] then
			visited[r] = true; nVisited += 1
			if not firstDarkEntry and r ~= p.exit and t >= darkAt(r) then firstDarkEntry = t end
			local it = p.item[r]
			if r == p.exit then exitKnown = true end
			if it == "fuse" then
				spend(r, cfg.PickupDetourSeconds)
				held += 1
				if not firstFuseT then firstFuseT = t; firstFuseRooms = nVisited end
			elseif it == "battery" then
				spend(r, cfg.PickupDetourSeconds)
				if bat then battery = math.min(bat.cap, battery + bat.cell) end
			end
		end
	end

	local openedEdge = {}
	local firstDarkBehind = nil
	local function move(a, b, fresh)
		spend(a, stepT / 2)
		if fresh then spend(b, cfg.DoorOpenSeconds) end
		spend(b, stepT / 2)
		openedEdge[math.min(a, b) .. "," .. math.max(a, b)] = true
		if not firstDarkBehind then
			for _, c in p.adj[b] do
				if openedEdge[math.min(b, c) .. "," .. math.max(b, c)] and c ~= p.exit and t >= darkAt(c) and t < darkAt(b) then
					firstDarkBehind = t
					break
				end
			end
		end
	end

	-- BFS over the KNOWN graph (visited rooms) from pos; returns parent map + dist
	local function knownBfs()
		local dist, par = { [pos] = 0 }, {}
		local q, h = { pos }, 1
		while h <= #q do
			local a = q[h]; h += 1
			for _, b in p.adj[a] do
				if visited[b] and dist[b] == nil then
					dist[b] = dist[a] + 1; par[b] = a; table.insert(q, b)
				end
			end
		end
		return dist, par
	end

	local function walkTo(target, par)
		local path = {}
		local c = target
		while c ~= pos do table.insert(path, 1, c); c = par[c] end
		for _, r in path do
			local fresh = not visited[r]
			move(pos, r, fresh)
			pos = r
			enter(r)
			if died then return end
		end
	end

	local guard = 0
	while not died do
		guard += 1
		if guard > 1000 then error("explorer loop") end
		if held >= p.fuses and exitKnown then
			local dist, par = knownBfs()
			walkTo(p.exit, par)
			break
		end
		-- nearest frontier room
		local dist, par = knownBfs()
		local best, bestD = nil, math.huge
		for a, da in dist do
			for _, b in p.adj[a] do
				if not visited[b] and da + 1 < bestD then best = b; bestD = da + 1; par[b] = a
				elseif not visited[b] and da + 1 == bestD and b < best then best = b; par[b] = a end
			end
		end
		if not best then error("no frontier but objective incomplete") end
		-- par[best] was set to the frontier parent; walk
		walkTo(best, par)
	end
	return {
		t = died and diedAt or t, died = died, darkSec = darkSec, visited = nVisited,
		firstFuseT = firstFuseT, firstFuseRooms = firstFuseRooms, battery = battery,
		minBattery = minBattery, revivesUsed = revivesUsed, firstDarkEntry = firstDarkEntry, firstDarkBehind = firstDarkBehind,
	}
end

function M.pct(list, q)
	table.sort(list)
	local k = math.max(1, math.min(#list, math.floor(q * #list + 0.5)))
	return list[k]
end
function M.mean(list)
	local s = 0
	for _, v in list do s += v end
	return s / #list
end

return M
