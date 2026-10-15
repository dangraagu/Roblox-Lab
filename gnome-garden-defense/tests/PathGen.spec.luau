-- PathGen.spec: the procedural garden bed (DESIGN.md §3.6).
-- Run: luau tests/PathGen.spec.luau
--
-- A bed is a path of exactly PathCells cells from the hedge gap (x = 0) to the carrot patch (x = GridW - 1),
-- built from 3-5 vertical runs in columns at least 2 apart, and the pads are every lawn cell touching it.
-- The golden beds below were RECORDED from tests/GardenModel.luau (the balance model every measured
-- number came from) before PathGen existed: the game must draw exactly the beds the model measured.

local PathGen = require("../src/shared/PathGen")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function approx(a, b, msg) eq(math.abs(a - b) < 1e-9, true, msg .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")") end

local function cellsText(path)
	local parts = {}
	for _, c in path.cells do table.insert(parts, c.x .. "," .. c.y) end
	return table.concat(parts, ";")
end

--====================================================================== golden beds (from the model)
local GOLDEN = {
	{ seed = 1001, cells = "0,2;1,2;2,2;2,1;2,0;3,0;4,0;5,0;5,1;5,2;5,3;5,4;5,5;5,6;5,7;5,8;6,8;7,8;7,7;7,6;7,5;7,4;7,3;7,2;8,2;9,2;10,2;10,3;10,4;11,4",
		pads = 43, at100 = { 44, 44 }, cover1 = 17.5, pad1 = { 1, 0 } },
	{ seed = 1002, cells = "0,4;1,4;2,4;3,4;3,3;3,2;3,1;3,0;4,0;5,0;6,0;6,1;6,2;6,3;6,4;6,5;6,6;6,7;7,7;8,7;8,6;8,5;9,5;10,5;10,4;10,3;10,2;10,1;10,0;11,0",
		pads = 49, at100 = { 52, 20 }, cover1 = 17.5, pad1 = { 2, 0 } },
	{ seed = 1003, cells = "0,4;1,4;2,4;2,5;2,6;2,7;3,7;4,7;4,6;4,5;4,4;4,3;4,2;4,1;5,1;6,1;6,2;6,3;6,4;6,5;6,6;7,6;8,6;8,5;8,4;9,4;10,4;10,5;10,6;11,6",
		pads = 48, at100 = { 36, 20 }, cover1 = 6.5, pad1 = { 3, 0 } },
	{ seed = 77, cells = "0,6;1,6;2,6;2,5;2,4;2,3;2,2;2,1;3,1;4,1;5,1;6,1;7,1;8,1;8,2;8,3;8,4;8,5;8,6;8,7;8,8;9,8;10,8;10,7;10,6;10,5;10,4;10,3;10,2;11,2",
		pads = 49, at100 = { 60, 12 }, cover1 = 6.5, pad1 = { 1, 0 } },
	{ seed = 123456789, cells = "0,2;1,2;1,3;1,4;1,5;1,6;2,6;3,6;4,6;4,5;4,4;4,3;4,2;5,2;6,2;6,3;6,4;6,5;6,6;6,7;6,8;7,8;8,8;8,7;8,6;8,5;8,4;9,4;10,4;11,4",
		pads = 47, at100 = { 36, 20 }, cover1 = 15.5, pad1 = { 0, 1 } },
}
for _, gold in GOLDEN do
	local path = PathGen.genPath(Config, Rng.new(gold.seed))
	eq(cellsText(path), gold.cells, "seed " .. gold.seed .. " draws the model's bed")
	local pads = PathGen.pads(Config, path)
	eq(#pads, gold.pads, "seed " .. gold.seed .. " has the model's pad count")
	eq(path.length, 240, "seed " .. gold.seed .. ": the path is 240 studs, hedge edge to patch edge")
	local x, z = PathGen.posAt(path, 100)
	approx(x, gold.at100[1], "seed " .. gold.seed .. ": the point 100 studs along (x)")
	approx(z, gold.at100[2], "seed " .. gold.seed .. ": the point 100 studs along (z)")
	local _, cover = PathGen.rangeMask(path, pads[1].cx, pads[1].cz, 14)
	approx(cover, gold.cover1, "seed " .. gold.seed .. ": path within 14 studs of the first pad")
	eq(pads[1].x .. "," .. pads[1].y, gold.pad1[1] .. "," .. gold.pad1[2], "seed " .. gold.seed .. ": pads are sorted by row, then column")
end

--====================================================================== every bed obeys the rules
do
	local okLen, okEdges, okTouch, okPads, okSame, okStep = true, true, true, true, true, true
	local minPads, maxPads = math.huge, 0
	for s = 1, 300 do
		local p = PathGen.genPath(Config, Rng.new(5000 + s))
		if #p.cells ~= Config.PathCells then okLen = false end
		if p.cells[1].x ~= 0 or p.cells[#p.cells].x ~= Config.GridW - 1 then okEdges = false end
		local at = {}
		for i, c in p.cells do at[c.x .. "," .. c.y] = i end
		for i, c in p.cells do
			if i > 1 then
				local d = math.abs(c.x - p.cells[i - 1].x) + math.abs(c.y - p.cells[i - 1].y)
				if d ~= 1 then okStep = false end
			end
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local j = at[(c.x + d[1]) .. "," .. (c.y + d[2])]
				if j and math.abs(j - i) ~= 1 then okTouch = false end
			end
		end
		local pads = PathGen.pads(Config, p)
		minPads = math.min(minPads, #pads)
		maxPads = math.max(maxPads, #pads)
		if #pads < Config.MaxGnomes then okPads = false end
		for _, pad in pads do
			if p.onPath[pad.x .. "," .. pad.y] then okPads = false end
		end
		if cellsText(PathGen.genPath(Config, Rng.new(5000 + s))) ~= cellsText(p) then okSame = false end
	end
	truthy(okLen, "every bed's path is exactly PathCells long")
	truthy(okEdges, "every path runs from the hedge gap to the carrot patch")
	truthy(okStep, "consecutive path cells are side by side (the bugs walk a connected path)")
	truthy(okTouch, "no path touches itself side by side")
	truthy(okPads, "every bed has at least MaxGnomes pads, and no pad sits on the path")
	truthy(okSame, "the same seed draws the same bed")
	print(("PathGen: pads per bed %d..%d over 300 seeds"):format(minPads, maxPads))
end

--====================================================================== the path, replicated as text
do
	local path = PathGen.genPath(Config, Rng.new(1001))
	local text = PathGen.encodeCells(path.cells)
	eq(text, GOLDEN[1].cells, "encodeCells writes x,y pairs separated by ;")
	local back = PathGen.fromText(Config, text)
	truthy(back ~= nil, "fromText rebuilds a path from the replicated text")
	if back then
		eq(cellsText(back), cellsText(path), "and it is the same path")
		eq(back.length, path.length, "with the same length")
		local x1, z1 = PathGen.posAt(back, 123.4)
		local x2, z2 = PathGen.posAt(path, 123.4)
		approx(x1, x2, "and the same geometry (x)")
		approx(z1, z2, "and the same geometry (z)")
	end
	eq(PathGen.fromText(Config, "nonsense"), nil, "garbage text is refused, not drawn")
	eq(PathGen.fromText(Config, ""), nil, "an empty text is refused")
end

--====================================================================== posAt is total
do
	local path = PathGen.genPath(Config, Rng.new(9))
	local x0, z0 = PathGen.posAt(path, -50)
	local x1, z1 = PathGen.posAt(path, 0)
	approx(x0, x1, "posAt clamps a negative distance to the hedge gap (x)")
	approx(z0, z1, "posAt clamps a negative distance to the hedge gap (z)")
	local xe, ze = PathGen.posAt(path, 9999)
	approx(xe, Config.GridW * Config.Tile, "posAt clamps past the end to the patch edge")
	truthy(ze >= 0 and ze <= Config.GridH * Config.Tile, "and stays on the bed")
	approx(x1, 0, "the path starts at the hedge edge, x = 0")
end

--====================================================================== the glowing pads (REVIEW-2)
-- The pads that glow (Garden.client) and the ones the pacing model's NORMAL player plants on are the same list:
-- the free pads ranked by path studs within a level-1 Pebble's 14 studs (ties to the lower pad number). Ranked
-- here by hand from rangeMask's own count, so a change to the ranking shows.
do
	local path = PathGen.genPath(Config, Rng.new(4242))
	local pads = PathGen.pads(Config, path)
	local ranked = {}
	for id, pd in pads do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, 14)
		table.insert(ranked, { id = id, cover = cover })
	end
	table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	local best = PathGen.bestPads(Config, path, pads, {}, 3)
	eq(#best, 3, "bestPads gives the three asked for")
	eq(table.concat(best, ","), ranked[1].id .. "," .. ranked[2].id .. "," .. ranked[3].id, "the pads that see the most path, best first")
	local taken = { [ranked[1].id] = true, [ranked[3].id] = true }
	local next3 = PathGen.bestPads(Config, path, pads, taken, 3)
	eq(table.concat(next3, ","), ranked[2].id .. "," .. ranked[4].id .. "," .. ranked[5].id, "a taken pad is skipped: the next best free ones")
	local all = {}
	for id in pads do all[id] = true end
	eq(#PathGen.bestPads(Config, path, pads, all, 3), 0, "a bed with no free pad has none to glow")
	-- for a Lantern (range 18) the best pads are ranked by what a Lantern sees
	local lr = {}
	for id, pd in pads do
		local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, 18)
		table.insert(lr, { id = id, cover = cover })
	end
	table.sort(lr, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
	eq(table.concat(PathGen.bestPads(Config, path, pads, {}, 3, "lantern"), ","), lr[1].id .. "," .. lr[2].id .. "," .. lr[3].id,
		"for a Lantern the pads that see the most path within 18 studs")
end

--====================================================================== glow: the starred gnome and its pads, as one rule
-- Garden.client lights, Hud.client stars and the pacing model's normal player plants what PathGen.glow says: the
-- gnome Garden.suggestKind names for the standing gnomes, and the best free pads FOR IT. On a bed where a
-- Sprinkler's best pads (12 studs) are not a Pebble's (14), a spring garden with one Pebble standing must glow
-- the Sprinkler's (the sweep's M59: a glow ranked for a Pebble survived a check whose bed ranked both the same).
do
	local Garden = require("../src/shared/Garden")
	local function top3(path, pads, taken, range)
		local r = {}
		for id, pd in pads do
			if not taken[id] then
				local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, range)
				table.insert(r, { id = id, cover = cover })
			end
		end
		table.sort(r, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.id < b.id end)
		return r[1].id .. "," .. r[2].id .. "," .. r[3].id, r[1].id
	end
	local found = nil
	for seed = 1, 300 do
		local path = PathGen.genPath(Config, Rng.new(seed))
		local pads = PathGen.pads(Config, path)
		local _, bestPebble = top3(path, pads, {}, 14)
		local taken = { [bestPebble] = true }
		local sp, pe = top3(path, pads, taken, 12), top3(path, pads, taken, 14)
		if sp ~= pe then
			found = { path = path, pads = pads, pebblePad = bestPebble, sprinkler = sp, pebble = pe, seed = seed }
			break
		end
	end
	truthy(found ~= nil, "(a bed where a Sprinkler's three best free pads are not a Pebble's)")
	if found then
		local kind, lit = PathGen.glow(Config, found.path, found.pads, { { pad = found.pebblePad, kind = "pebble" } }, 1, Garden.suggestKind)
		eq(kind, "sprinkler", "one Pebble standing in spring: the Sprinkler is starred")
		eq(table.concat(lit, ","), found.sprinkler, "and the pads that glow are the Sprinkler's best free ones (seed " .. found.seed .. "), not the Pebble's ("
			.. found.pebble .. ")")
		local k0, lit0 = PathGen.glow(Config, found.path, found.pads, {}, 1, Garden.suggestKind)
		eq(k0, "pebble", "a bare bed stars the Pebble")
		eq(#lit0, 3, "and lights three pads")
	end
end

print(("PathGen: %d passed, %d failed"):format(passed, failed))
