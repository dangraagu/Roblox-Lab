-- MapGen: the 13 x 13 terraced island (DESIGN.md §2.2). Run: luau tests/MapGen.spec.luau
--
-- What a map must always be, because the fairness of every disaster rests on it:
--   * neighbouring cells never differ by more than one level (every cell reachable on foot, a 4-stud step is a jump);
--   * at least 18 cells at level >= 3 (dry after the last flood rise; 8 players fit);
--   * no flood traps: every level-k cell (k <= 2) reaches a level >= k+1 cell without stepping down;
--   * the longest such escape is at most 80 studs of cell-centre path (100 walked at the 1.25 path factor);
--   * every map supports every disaster (nothing about a map is chosen for its disaster).
local MapGen = require("../src/shared/MapGen")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local IC = Config.Island
local N = IC.Grid

local function randOf(seed: number): () -> number
	local r = Rng.new(seed)
	return function() return r:next() end
end

local function grid(fill: number): { { number } }
	local g = {}
	for i = 1, N do
		g[i] = {}
		for j = 1, N do g[i][j] = fill end
	end
	return g
end

--======================================================================= geometry helpers

do
	local x, z = MapGen.cellCenter(IC, 7, 7)
	eq(x, 0, "the centre cell's x is the world origin")
	eq(z, 0, "and its z")
	local x1, z1 = MapGen.cellCenter(IC, 1, 13)
	eq(x1, -48, "cell (1, _) sits at x = -48")
	eq(z1, 48, "cell (_, 13) sits at z = +48")
	local i, j = MapGen.cellAt(IC, -48, 48)
	eq(i, 1, "cellAt finds the cell back (i)")
	eq(j, 13, "cellAt finds the cell back (j)")
	local i2, j2 = MapGen.cellAt(IC, 51.9, -51.9)
	eq(i2, 13, "a point 0.1 stud inside the far edge is in cell 13 (i)")
	eq(j2, 1, "and cell 1 (j)")
	eq((MapGen.cellAt(IC, 52.1, 0)), nil, "a point past the island's edge is in no cell")
	eq(MapGen.topY(IC, 0), 0, "level 0's top is at y = 0 (the beach)")
	eq(MapGen.topY(IC, 4), 16, "level 4's top is at y = 16")
	eq(MapGen.halfSize(IC), 52, "the island spans 104 x 104 studs")
end

--======================================================================= validate: every rule rejects what it should

do
	-- a hand-made valid map: one broad hill
	local g = grid(0)
	for i = 1, N do
		for j = 1, N do
			local d = math.max(math.abs(i - 7), math.abs(j - 7))
			g[i][j] = math.max(0, math.min(4, 6 - d))
		end
	end
	local ok, why = MapGen.validate(IC, g)
	truthy(ok, "a broad hill is a valid map (" .. tostring(why) .. ")")

	local cliff = grid(0)
	for i = 1, N do for j = 1, N do cliff[i][j] = g[i][j] end end
	cliff[7][7] = 4
	cliff[7][8] = 2
	local ok2, why2 = MapGen.validate(IC, cliff)
	eq(ok2, false, "a two-level step is rejected")
	truthy(why2 ~= nil and string.find(why2, "step", 1, true) ~= nil, "and the reason says step (" .. tostring(why2) .. ")")

	local low = grid(0)
	for i = 4, 10 do for j = 4, 10 do low[i][j] = 1 end end
	for i = 5, 9 do for j = 5, 9 do low[i][j] = 2 end end
	for i = 6, 8 do for j = 6, 8 do low[i][j] = 3 end end
	local ok3, why3 = MapGen.validate(IC, low) -- 9 high cells
	eq(ok3, false, "17 or fewer high cells is rejected")
	truthy(why3 ~= nil and string.find(why3, "high", 1, true) ~= nil, "and the reason says high (" .. tostring(why3) .. ")")

	-- a level-1 cell in a level-0 hollow, cut off from the hill by a level-0 moat: a flood trap
	local trap = grid(0)
	for i = 1, N do for j = 1, N do trap[i][j] = g[i][j] end end
	for i = 1, N do for j = 1, N do if trap[i][j] < 1 then trap[i][j] = 0 end end end
	trap[1][1] = 1 -- the corner cell: its neighbours (1,2) and (2,1) are level 0 or 1?
	trap[1][2], trap[2][1] = 0, 0
	local ok4, why4 = MapGen.validate(IC, trap)
	eq(ok4, false, "a level-1 cell whose only way up goes through level 0 is a flood trap")
	truthy(why4 ~= nil and string.find(why4, "trap", 1, true) ~= nil, "and the reason says trap (" .. tostring(why4) .. ")")

	-- a level-1 plain with a hill in one corner: the far corner is 14 steps (116 studs) from level 2
	local plain = grid(1)
	for i = 8, N do
		for j = 8, N do plain[i][j] = math.min(4, 1 + math.min(i - 7, j - 7)) end
	end
	eq(MapGen.highCount(IC, plain), 25, "the corner hill has 25 high cells (so only the escape can fail)")
	local ok5, why5 = MapGen.validate(IC, plain)
	eq(ok5, false, "a map whose flood escape is longer than 80 studs is rejected")
	truthy(why5 ~= nil and string.find(why5, "escape", 1, true) ~= nil, "and the reason says escape (" .. tostring(why5) .. ")")
end

--======================================================================= floodEscape: BFS distances

do
	local g = grid(0)
	for i = 1, N do
		for j = 1, N do
			local d = math.max(math.abs(i - 7), math.abs(j - 7))
			g[i][j] = math.max(0, math.min(4, 6 - d))
		end
	end
	local esc = MapGen.floodEscape(g, 1)
	-- a level-0 cell next to a level-1 cell escapes in one step
	eq(esc[MapGen.key(1, 7)], 1, "the beach cell (1, 7) is one step from level 1")
	eq(esc[MapGen.key(7, 7)], nil, "a level-4 cell is not listed for rise 1 (it is not under water)")
	local esc3 = MapGen.floodEscape(g, 3)
	eq(esc3[MapGen.key(3, 7)], 1, "a level-2 cell (3, 7) next to level 3 escapes rise 3 in one step")
end

--======================================================================= 1 000 generated maps

local tries, maxTries, maps = 0, 0, 0
local highMin, highMax = math.huge, 0
local highs = {}
local worst, worstEscape = {}, 0
local levelCount = { [0] = 0, 0, 0, 0, 0 }
local propsMax = 0
local styleSeen = {}
local badDrop, badProps, invalid = 0, 0, 0
for seed = 1, 1000 do
	local map, t = MapGen.generate(IC, randOf(seed * 7919 + 13))
	maps += 1
	tries += t
	maxTries = math.max(maxTries, t)
	local ok = MapGen.validate(IC, map.levels)
	if not ok then invalid += 1 end
	local h = MapGen.highCount(IC, map.levels)
	highMin = math.min(highMin, h)
	highMax = math.max(highMax, h)
	table.insert(highs, h)
	for i = 1, N do for j = 1, N do levelCount[map.levels[i][j]] += 1 end end
	local w = MapGen.worstEscape(IC, map.levels)
	table.insert(worst, w)
	worstEscape = math.max(worstEscape, w)
	styleSeen[map.style] = true
	propsMax = math.max(propsMax, #map.props)
	local style = IC.Styles[map.style]
	for _, p in map.props do
		if p.kind ~= style.props[1] and p.kind ~= style.props[2] then badProps += 1 end
		if map.levels[p.i] == nil or map.levels[p.i][p.j] == nil then badProps += 1 end
	end
	-- 8 players land on distinct level >= 1 cells, 2 cells apart
	local drops = MapGen.dropCells(IC, map.levels, 8, randOf(seed))
	if #drops ~= 8 then badDrop += 1 end
	for a = 1, #drops do
		local da = drops[a]
		if map.levels[da.i][da.j] < 1 then badDrop += 1 end
		for b = a + 1, #drops do
			local db = drops[b]
			if math.max(math.abs(da.i - db.i), math.abs(da.j - db.j)) < IC.DropSpacingCells then badDrop += 1 end
		end
	end
end
table.sort(highs)
table.sort(worst)
local accept = maps / tries
eq(invalid, 0, "every one of 1 000 generated maps passes validate")
truthy(accept >= 0.9, string.format("at least 90 %% of candidates pass (measured %.3f)", accept))
truthy(maxTries <= 3, "never more than 3 tries for a map (measured " .. maxTries .. ")")
truthy(highMin >= IC.MinHighCells, "every map has >= 18 cells at level >= 3 (min " .. highMin .. ")")
truthy(worstEscape <= IC.MaxEscapeStuds, "the longest flood escape on any map is <= 80 studs (max " .. worstEscape .. ")")
eq(badDrop, 0, "8 players always land on distinct level >= 1 cells, 2 cells apart")
eq(badProps, 0, "every prop is a kind of its map's style, on a real cell")
truthy(propsMax <= IC.MaxProps, "no map has more than 80 props (max " .. propsMax .. ")")
eq(styleSeen[1] and styleSeen[2] and styleSeen[3], true, "all three styles come up")
do
	local total = 0
	for l = 0, 4 do total += levelCount[l] end
	local share = {}
	for l = 0, 4 do share[l + 1] = string.format("%.3f", levelCount[l] / total) end
	print(string.format("  1000 maps: accept %.3f, tries max %d; level>=3 cells min %d / median %d / max %d; "
		.. "worst escape median %d, max %d studs; level share 0-4: %s; props max %d",
		accept, maxTries, highMin, highs[500], highMax, worst[500], worstEscape, table.concat(share, " / "), propsMax))
end

--======================================================================= determinism and a seed-free server

do
	local a = MapGen.generate(IC, randOf(424242))
	local b = MapGen.generate(IC, randOf(424242))
	local same = a.style == b.style
	for i = 1, N do for j = 1, N do if a.levels[i][j] ~= b.levels[i][j] then same = false end end end
	truthy(same, "the same random stream builds the same island (shots place: Config.Shots.IslandSeed)")
	-- a stream that never passes validation still yields a valid island (the fallback), never an error
	local stuck = function() return 0 end
	local ok, map = pcall(MapGen.generate, IC, stuck)
	truthy(ok, "generate never errors, even when no candidate passes (" .. tostring(map) .. ")")
	if ok then truthy((MapGen.validate(IC, map.levels)), "and the fallback island is valid") end
end

--======================================================================= drop cells when the island is crowded

do
	local g = grid(0)
	for i = 1, N do
		for j = 1, N do
			local d = math.max(math.abs(i - 7), math.abs(j - 7))
			g[i][j] = math.max(0, math.min(4, 6 - d))
		end
	end
	local d = MapGen.dropCells(IC, g, 12, randOf(5))
	eq(#d, 12, "12 players still get 12 distinct cells when spacing cannot hold for all")
	local seen = {}
	local dup = false
	for _, c in d do
		local k = MapGen.key(c.i, c.j)
		if seen[k] then dup = true end
		seen[k] = true
	end
	eq(dup, false, "and no two share a cell")
end

print(string.format("MapGen: %d passed, %d failed", passed, failed))
assert(failed == 0, "MapGen tests failed")
