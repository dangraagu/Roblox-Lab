-- How far below the day's stored P can a line go? Written 2026-10-01 when tests/walk.luau found a
-- player line (501.6 studs) shorter than the day's P (517.6). Compares the stored P against the
-- minimum over the 6 seal orders and over every simple cell path up to SLACK steps over the BFS
-- distance per leg. Also prints the largest number of DFS expansions one leg needed
-- (Config.Perfect.MaxExpansions must stay far above it).
--   before the fix (P = the funnel along ONE min-step BFS route): slack 4 and 8 both printed
--     "true/P p10 0.9629 p50 0.9978 p90 1.0000 min 0.9172; shorter line on 107 of 200 days (54%)"
--   after (P = Dungeon.bestLine): 0 of 200 days at slack 4 and at slack 8; max expansions 932 / 1732
-- Run: luau pgap.luau -a <slack>    (from this folder)
local root = "../../"
local Dungeon = require(root .. "src/server/Dungeon")
local Config = require(root .. "src/shared/Config")
local Rng = require(root .. "src/shared/Rng")
local SLACK = tonumber((...)) or 8
local N = 200
local cfg = Config
-- REVIEW-1: this measured the FIRST build's centre-line P (margin 2.5, centre to centre). P is now the
-- tight line (Dungeon.tightLine; tests/Dungeon.spec checks it against an independent sampled search),
-- so against the stored P this centre search now reads ratios above 1. Kept as the record of trap 14.
local cell, margin = cfg.Grid.Cell, 2.5
local PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
local maxNodes = 0
local function centre(m, i) return { x = (i % m.W + 0.5) * cell, y = (i // m.W + 0.5) * cell } end
local function legMin(m, a, b, sPt, ePt)
	local dist = Dungeon.bfs(m, b)
	local limit = dist[a] + SLACK
	local best = math.huge
	local path, on = { a }, { [a] = true }
	local nodes = 0
	local function dfs(c, depth)
		nodes += 1
		if c == b then
			local len = Dungeon.funnel(m, path, sPt, ePt, cell, margin)
			if len < best then best = len end
			return
		end
		for _, n in Dungeon.neighbours(m, c) do
			if not on[n] and depth + 1 + dist[n] <= limit then
				on[n] = true; table.insert(path, n)
				dfs(n, depth + 1)
				table.remove(path); on[n] = nil
			end
		end
	end
	dfs(a, 0)
	if nodes > maxNodes then maxNodes = nodes end
	return best
end
local ratios = {}
local r = Rng.new(777)
local draw = function(n) return r:below(n) end
local done = 0
while done < N do
	local rec = Dungeon.mint(cfg, draw, 1, 1)
	if rec then
		local w = Dungeon.fromRecord(cfg, rec)
		local m = w.maze
		local P = rec.perfectMs / 1000 * cfg.Walk.Speed -- the stored P (whatever the game computes now)
		local e = w.entrance
		local startPt = { x = (e % m.W + 0.5) * cell, y = (e // m.W) * cell }
		local bestT = math.huge
		for _, o in PERMS do
			local pts = { e, w.seals[o[1]], w.seals[o[2]], w.seals[o[3]], w.door }
			local total = 0
			for k = 1, 4 do
				local s = if k == 1 then startPt else centre(m, pts[k])
				total += legMin(m, pts[k], pts[k + 1], s, centre(m, pts[k + 1]))
			end
			bestT = math.min(bestT, total)
		end
		table.insert(ratios, bestT / P)
		done += 1
	end
end
table.sort(ratios)
local function q(p) return ratios[math.max(1, math.floor(p * #ratios + 0.5))] end
local below = 0
for _, x in ratios do if x < 0.999 then below += 1 end end
print(string.format("max DFS expansions in one leg: %d", maxNodes))
print(string.format("slack %d, %d days: true/P p10 %.4f p50 %.4f p90 %.4f min %.4f; days where a shorter line exists: %d (%.0f%%)",
	SLACK, N, q(0.1), q(0.5), q(0.9), ratios[1], below, below / N * 100))
