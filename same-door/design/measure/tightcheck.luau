-- Is the day's P (Dungeon.tightLine) the shortest line? An independent sampled search (the one in
-- tests/Dungeon.spec, on more days and other seeds): every seal order, every simple cell path up to 6
-- steps over the BFS distance, the start every stud along the line, each pickup circle at 24 points,
-- best line by dynamic programming. Sampling makes it an upper bound on the true minimum, so a search
-- line shorter than P (by more than 0.05 studs) is a miss of the game's solver.
-- Run (from this folder): luau tightcheck.luau [-a days]
local root = "../../"
local Dungeon = require(root .. "src/server/Dungeon")
local cfg = require(root .. "src/shared/Config")
local Rng = require(root .. "src/shared/Rng")
local N = tonumber((...)) or 100
local W = cfg.Grid.W
local CELL = cfg.Grid.Cell
local margin = cfg.Check.TautMargin
local Rs, Rd = cfg.Pickup.Radius - cfg.Perfect.PickupInset, cfg.Pickup.Radius
local DUNGEON_PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
local function drawOf(seed)
	local r = Rng.new(seed)
	return function(n) return r:below(n) end
end
local function centre(i) return { x = (i % W + 0.5) * CELL, y = (i // W + 0.5) * CELL } end
local function paths(m, a, b, sRef, eRef, reach)
	local dist = Dungeon.bfs(m, b)
	local limit = dist[a] + 6
	local all, best = {}, math.huge
	local path, on = { a }, { [a] = true }
	local function dfs(c, depth)
		if c == b then
			local l = Dungeon.funnel(m, path, sRef, eRef, CELL, margin)
			table.insert(all, { l = l, cells = table.clone(path) })
			if l < best then best = l end
			return
		end
		for _, n in Dungeon.neighbours(m, c) do
			if not on[n] and depth + 1 + dist[n] <= limit then
				on[n] = true; table.insert(path, n); dfs(n, depth + 1); table.remove(path); on[n] = nil
			end
		end
	end
	dfs(a, 0)
	-- moving an end by d changes a corridor's line by at most d (1-Lipschitz), so only corridors
	-- within 2 x (both ends' reach) of the best at the reference ends can win
	local keep = {}
	for _, p in all do if p.l <= best + 2 * reach + 0.5 then table.insert(keep, p.cells) end end
	return keep
end
local K = 24
local function ring(c, r)
	local out = {}
	for k = 0, K - 1 do
		local a = 2 * math.pi * k / K
		table.insert(out, { x = c.x + r * math.cos(a), y = c.y + r * math.sin(a) })
	end
	return out
end
local searchDays, shorter, worstGap = N, 0, 0
local gaps = {}
local lo, hi = cfg.Grid.EntranceX * CELL + margin, (cfg.Grid.EntranceX + 1) * CELL - margin
for sd = 1, searchDays do
	local rec = Dungeon.mint(cfg, drawOf(sd * 15485863 + 101), 20726, 1790730000)
	local w = Dungeon.fromRecord(cfg, rec)
	local m = w.maze
	local e = w.entrance
	local starts = {}
	for x = lo, hi do table.insert(starts, { x = x, y = 0 }) end
	local best = math.huge
	for _, o in DUNGEON_PERMS do
		local seq = { e, w.seals[o[1]], w.seals[o[2]], w.seals[o[3]], w.door }
		local stages = { starts }
		for k = 2, 4 do table.insert(stages, ring(centre(seq[k]), Rs)) end
		table.insert(stages, ring(centre(seq[5]), Rd))
		local cost = {}
		for j in stages[1] do cost[j] = 0 end
		for k = 1, 4 do
			local sRef = if k == 1 then { x = (lo + hi) / 2, y = 0 } else centre(seq[k])
			local reachA = if k == 1 then (hi - lo) / 2 else Rs
			local reachB = if k == 4 then Rd else Rs
			local cands = paths(m, seq[k], seq[k + 1], sRef, centre(seq[k + 1]), reachA + reachB)
			local nextCost = {}
			for j, q in stages[k + 1] do
				local bestJ = math.huge
				for i, p in stages[k] do
					for _, c in cands do
						local l = cost[i] + Dungeon.funnel(m, c, p, q, CELL, margin)
						if l < bestJ then bestJ = l end
					end
				end
				nextCost[j] = bestJ
			end
			cost = nextCost
		end
		for _, c in cost do best = math.min(best, c) end
	end
	local P = rec.perfectMs / 1000 * cfg.Walk.Speed
	table.insert(gaps, P - best)
	if best < P - 0.05 then shorter += 1; worstGap = math.max(worstGap, P - best) end
end
table.sort(gaps)
print(string.format("%d days: search line shorter than P by > 0.05 studs on %d (worst %.3f); P - search: min %.3f p50 %.3f max %.3f studs",
	N, shorter, worstGap, gaps[1], gaps[math.ceil(#gaps / 2)], gaps[#gaps]))
