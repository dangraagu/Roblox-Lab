-- Pure tests for Layout: the yard grid, lair and camp generation, trap placement rules.
-- Run from the game directory: luau tests/Layout.spec.luau
--
-- Counts that describe the DESIGN (lines, gaps, rocks, forced lines) are written by hand from
-- DESIGN.md sections 5-7. Counts that are MEASUREMENTS (resamples, walled-in cells) are printed,
-- and bounded only where the design makes a promise about them.
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Layout = require("../src/shared/Layout")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- For loops over thousands of seeds: count violations, assert once.
local function tally() return { n = 0, first = nil } end
local function note(t, msg) t.n += 1; if t.first == nil then t.first = msg end end
local function none(t, msg)
	if t.n == 0 then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> " .. t.n .. " violations, first: " .. tostring(t.first))
	end
end

local SEEDS = 2000

--============================================================================ geometry

do
	local r = Layout.cellRect(Config, 1, 0)
	eq(r.x0, 0, "cell (1,0) x0"); eq(r.x1, 8, "cell (1,0) x1"); eq(r.z0, 16, "cell (1,0) z0"); eq(r.z1, 24, "cell (1,0) z1")
	local x, z = Layout.cellCenter(Config, 5, 0)
	eq(x, 36, "gate approach centre x"); eq(z, 20, "gate approach centre z")
	x, z = Layout.cellCenter(Config, 5, 8)
	eq(x, 36, "centre grab cell x"); eq(z, 84, "centre grab cell z")
	x, z = Layout.cellCenter(Config, 9, 9)
	eq(x, 68, "last cage x"); eq(z, 92, "last cage z")
	local c, rr = Layout.cellAt(Config, 36.5, 20.2)
	eq(c, 5, "cellAt col"); eq(rr, 0, "cellAt row")
	c, rr = Layout.cellAt(Config, 0, 24)
	eq(c, 1, "cellAt on a boundary rounds into the higher cell (col)"); eq(rr, 1, "...(row)")
	c, rr = Layout.cellAt(Config, -0.5, 10)
	eq(c, 0, "cellAt left of the yard is column 0"); eq(rr, -1, "cellAt on the apron is row -1")
	-- the design's measured distance: gate approach to the Collect Pad is 16.97 studs
	local gx, gz = Layout.cellCenter(Config, 5, 0)
	local pad = Config.World.Apron.Pad
	eq(string.format("%.2f", math.sqrt((gx - pad.x) ^ 2 + (gz - pad.z) ^ 2)), "16.97", "gate approach to Collect Pad")
	-- REVIEW-1 R2-3 CHANGED THIS CONTRACT. The anchor used to sit on the cage front (z 88) with a
	-- 10-stud reach, which covers the grab cell but shows the prompt over 2.9x its area (64 % of
	-- the in-reach standing points were on no grab cell). It now hangs over the grab cell's centre,
	-- reaching every point a root can stand on in the cell (inset by the 1-stud root half-width:
	-- corners hypot(3, 3) = 4.24 away) and spilling at most 0.25 studs past the cell's edge.
	local ax, az = Layout.grabAnchor(Config, 5)
	eq(ax, 36, "grab anchor x"); eq(az, 84, "grab anchor z is the grab cell's centre")
	-- REVIEW-1.md B2 CHANGED THIS CONTRACT AGAIN. The 4.25-stud reach covered the cell inset by 1 stud on
	-- BOTH axes, but row 8 is open along x, so a root stands anywhere across the cell and up to z 87
	-- against the bars: the prompt missed 12-14 % of the points a root stands on in the cell, and still
	-- showed 0.25 studs past it, where the server refused. Now the server's grab region IS the
	-- prompt's region: the trusted position within Raid.GrabReach (on the flat) of the anchor, and the
	-- prompt's MaxActivationDistance is that same number (the anchor hangs at root height).
	eq(Config.Raid.GrabPromptDistance, Config.Raid.GrabReach, "the prompt reaches exactly as far as the server's grab rule")
	local cells, covered, mismatch = 0, 0, 0
	for px = 32, 40, 0.25 do
		for pz = 80, 87, 0.25 do
			cells += 1
			if Layout.inGrabReach(Config, 5, px, pz) then covered += 1 end
		end
	end
	for px = 24, 48, 0.25 do
		for pz = 72, 89, 0.25 do
			local d = math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2)
			if Layout.inGrabReach(Config, 5, px, pz) ~= (d <= Config.Raid.GrabPromptDistance) then mismatch += 1 end
		end
	end
	eq(mismatch, 0, "at every point round the cage the server's rule and the prompt's reach agree")
	local bars = 0
	for px = 32, 40, 0.25 do if Layout.inGrabReach(Config, 5, px, 87) then bars += 1 end end
	eq(bars, 33, "the whole width of the cage front (z 87, x 32..40) is in reach")
	print(string.format("  grab reach %.2f covers %.1f %% of the grab cell's standing points (x 32..40, z 80..87)", Config.Raid.GrabReach, 100 * covered / cells))
	truthy(covered / cells >= 0.97, "...and at least 97 % of the grab cell's standing points")
	truthy(not Layout.inGrabReach(Config, 5, 36, 76) and not Layout.inGrabReach(Config, 5, 44, 84), "neither the cell below nor the next cage's cell is in reach")
end

do
	eq(#Layout.gapCombos(Config, 3), 35, "35 ways to put three gaps 2 apart in 9 columns")
	eq(#Layout.gapCombos(Config, 2), 28, "28 ways for two gaps")
	eq(#Layout.gapCombos(Config, 1), 9, "9 ways for one gap")
	local bad = tally()
	for _, n in { 1, 2, 3 } do
		for _, combo in Layout.gapCombos(Config, n) do
			if #combo ~= n then note(bad, "size") end
			for i = 2, #combo do
				if combo[i] - combo[i - 1] < 2 then note(bad, table.concat(combo, ",")) end
			end
		end
	end
	none(bad, "every gap combination keeps its gaps at least 2 apart")
end

--============================================================================ seeds

do
	local s1 = Layout.lairSeed(Config, 5150)
	eq(s1, Layout.lairSeed(Config, 5150), "a lair seed is stable")
	truthy(s1 ~= Layout.lairSeed(Config, 5151), "neighbouring userIds get different lairs")
	-- userId is reduced FIRST: a huge id must not overflow and zero the low bits
	local big = Layout.lairSeed(Config, 9007199254740)
	truthy(big % 1 == 0 and big >= 0 and big < 2147483647, "a huge userId still gives an integer seed in range")
	truthy(Layout.lairSeed(Config, 9007199254740) ~= Layout.lairSeed(Config, 9007199254741), "...and adjacent huge ids differ")

	-- Layout.campSeed enumerates the specs' camp sets; the server draws camp seeds from a server-only
	-- Random stream instead (REVIEW-1.md A2, guards G22)
	local c1 = Layout.campSeed(Config, 2147483646, 999999, 4)
	truthy(c1 % 1 == 0 and c1 >= 0 and c1 < 2147483647, "the largest camp seed is an integer in range")
	truthy(Layout.campSeed(Config, 17, 1, 1) ~= Layout.campSeed(Config, 17, 2, 1), "raid serials change the camp")
	truthy(Layout.campSeed(Config, 17, 1, 1) ~= Layout.campSeed(Config, 18, 1, 1), "the session salt changes the camp")
	truthy(Layout.campSeed(Config, 17, 1, 1) ~= Layout.campSeed(Config, 17, 1, 2), "the tier changes the camp")
	-- the design's largest intermediate, 2 654 448 767 457 080, must stay under 2^53
	truthy(20260916 * 31 + 2147483647 * 7 + 999999 * 2654435761 + 4 * 104729 < 2 ^ 53, "camp seed intermediate < 2^53")
end

--============================================================================ reachability + placement on a hand-built lair

local function blankLair()
	-- a lair with no rocks and gaps at columns 1, 5, 9 on rows 3 and 6
	return Layout.fromSpec(Config, { kind = "lair", lines = { { row = 3, cols = { 1, 5, 9 } }, { row = 6, cols = { 1, 5, 9 } } }, rocks = {} })
end

do
	local L = blankLair()
	eq(Layout.cellKind(L, 2, 3), "fence", "fence between gaps")
	eq(Layout.cellKind(L, 5, 3), "floor", "gap is floor")
	eq(Layout.cellKind(L, 5, 0), "floor", "the gate approach is floor")
	eq(Layout.cellKind(L, 4, 0), "fence", "the rest of row 0 is the front fence")
	eq(Layout.cellKind(L, 5, 9), "cage", "row 9 is the cage row")
	eq(Layout.cellKind(L, 0, 4), "void", "outside the yard is void")
	truthy(Layout.row8Reachable(L), "an open lair reaches row 8")

	local ok, why = Layout.validatePlacement(Config, L, 5, 1, "snare")
	truthy(not ok, "the entry cell is refused"); eq(why, "Keep the entrance clear", "entry reason")
	ok, why = Layout.validatePlacement(Config, L, 2, 3, "laser")
	truthy(not ok, "a fence cell is refused"); eq(why, "That is a fence", "fence reason")
	ok, why = Layout.validatePlacement(Config, L, 5, 8, "snare")
	truthy(not ok, "row 8 is refused"); eq(why, "Traps go in yard rows 1 to 7", "row reason")
	ok, why = Layout.validatePlacement(Config, L, 10, 2, "snare")
	truthy(not ok, "column 10 is refused"); eq(why, "Traps go in yard rows 1 to 7", "column reason")
	ok, why = Layout.validatePlacement(Config, L, 3, 2, "turret")
	truthy(not ok, "an unknown kind is refused"); eq(why, "Unknown trap", "kind reason")

	truthy(Layout.place(Config, L, 5, 3, "laser"), "a laser in the centre gap")
	ok, why = Layout.validatePlacement(Config, L, 5, 3, "snare")
	truthy(not ok, "an occupied cell is refused"); eq(why, "There is already a trap there", "occupied reason")
	ok, why = Layout.validatePlacement(Config, L, 5, 4, "laser")
	truthy(not ok, "a laser beside a laser is refused"); eq(why, "Lasers need a safe cell between them", "adjacency reason")
	truthy(Layout.validatePlacement(Config, L, 5, 4, "snare"), "a snare beside a laser is fine")
	truthy(Layout.validatePlacement(Config, L, 4, 4, "laser"), "a DIAGONAL laser neighbour is fine")

	-- close two gaps of line 3 with snares: legal, the laser gap still lets everything through
	truthy(Layout.place(Config, L, 1, 3, "snare"), "snare in gap 1")
	truthy(Layout.place(Config, L, 9, 3, "snare"), "snare in gap 9")
	truthy(Layout.row8Reachable(L), "row 8 still reachable through the laser gap")
	-- lasers never wall anything off, but a snare in the last open gap would
	local ok2, why2 = Layout.validatePlacement(Config, L, 5, 3, "snare")
	truthy(not ok2, "(occupied by the laser anyway)")
	Layout.clear(L, 5, 3)
	ok2, why2 = Layout.validatePlacement(Config, L, 5, 3, "snare")
	truthy(not ok2, "a snare closing the last gap is refused")
	eq(why2, "That would wall off your cages - poachers and raiders must have a way in", "wall-off reason")
	truthy(Layout.validatePlacement(Config, L, 5, 3, "laser"), "...while a laser there is fine")
end

do
	-- caps: 4 lasers, 6 snares
	local L = blankLair()
	local laserCells = { { 1, 1 }, { 3, 1 }, { 7, 1 }, { 9, 1 } }
	for _, c in laserCells do truthy(Layout.place(Config, L, c[1], c[2], "laser"), "laser at " .. c[1] .. "," .. c[2]) end
	local ok, why = Layout.validatePlacement(Config, L, 2, 5, "laser")
	truthy(not ok, "a fifth laser is refused")
	eq(why, "Your lair already has 4 laser nets", "laser cap reason")
	local snareCells = { { 2, 2 }, { 4, 2 }, { 6, 2 }, { 8, 2 }, { 2, 4 }, { 4, 4 } }
	for _, c in snareCells do truthy(Layout.place(Config, L, c[1], c[2], "snare"), "snare at " .. c[1] .. "," .. c[2]) end
	ok, why = Layout.validatePlacement(Config, L, 6, 4, "snare")
	truthy(not ok, "a seventh snare is refused")
	eq(why, "Your lair already has 6 snares", "snare cap reason")
	eq(Layout.count(L, "laser"), 4, "four lasers counted")
	eq(Layout.count(L, "snare"), 6, "six snares counted")
	eq(Layout.clear(L, 2, 2), "snare", "clearing returns the kind for the refund")
	eq(Layout.clear(L, 2, 2), nil, "clearing an empty cell returns nil")
	eq(Layout.count(L, "snare"), 5, "five snares after a clear")
end

do
	-- a cell rocks have walled in: "Nothing can ever walk there"
	-- wall in (1,1) with rocks at (1,2) and (2,1)
	local L = Layout.fromSpec(Config, { kind = "lair", lines = { { row = 3, cols = { 1, 5, 9 } }, { row = 6, cols = { 1, 5, 9 } } },
		rocks = { { 1, 2 }, { 2, 1 } } })
	local ok, why = Layout.validatePlacement(Config, L, 1, 1, "laser")
	truthy(not ok, "a walled-in cell is refused")
	eq(why, "Nothing can ever walk there", "walled-in reason")
	ok, why = Layout.validatePlacement(Config, L, 2, 1, "laser")
	eq(why, "A rock is in the way", "rock reason")
end

do
	-- reconcile: saved traps are replayed in order through the CURRENT rules
	local L = blankLair()
	local kept, removed = Layout.reconcile(Config, L, { "L:5:3", "L:5:4", "S:1:3", "S:9:3", "S:5:3", "S:2:3", "S:4:1", "X:1:1" })
	eq(#kept, 4, "four saved traps survive")
	eq(kept[1], "L:5:3", "the first laser survives")
	eq(kept[4], "S:4:1", "a legal snare later in the list survives")
	eq(#removed, 4, "four are removed")
	eq(removed[1], "L:5:4", "adjacent laser removed")
	eq(removed[2], "S:5:3", "trap on an occupied cell removed")
	eq(removed[3], "S:2:3", "trap on a fence removed")
	eq(removed[4], "X:1:1", "malformed string removed")
	eq(Layout.count(L, "laser"), 1, "the layout holds what was kept")
	eq(Layout.trapString("laser", 4, 3), "L:4:3", "trap string format")
	local k, c, r = Layout.parseTrap("S:2:7")
	eq(k, "snare", "parse kind"); eq(c, 2, "parse col"); eq(r, 7, "parse row")
	eq((Layout.parseTrap("L:44:3")), nil, "parse rejects two-digit fields")
end

--============================================================================ danger areas

do
	local L = blankLair()
	Layout.place(Config, L, 5, 3, "laser")
	-- gap cell (5,3): x 32..40, z 40..48; fence both sides -> extends 1 stud INTO the fence margin
	local d = Layout.dangerRect(Config, L, 5, 3)
	eq(d.x0, 31, "a gap laser reaches 1 stud into the left fence's margin")
	eq(d.x1, 41, "...and the right fence's")
	eq(d.z0, 41, "...but is inset 1 stud towards the open row below")
	eq(d.z1, 47, "...and the open row above")

	Layout.place(Config, L, 2, 1, "snare")
	Layout.place(Config, L, 3, 1, "snare")
	local a = Layout.dangerRect(Config, L, 2, 1)
	local b = Layout.dangerRect(Config, L, 3, 1)
	eq(a.x1, 16, "a snare meets its snare neighbour exactly at the shared edge")
	eq(b.x0, 16, "...from both sides, so nobody slips between two snares")
	eq(a.x0, 9, "a snare is inset 1 stud towards open floor")
	eq(a.z0, 23, "...and reaches 1 stud into the front fence's margin on the row-0 side")
end

--============================================================================ free rects (the trusted-position map)

do
	local L = blankLair()
	local rects = Layout.freeRects(Config, L)
	-- walkable: (5,0) + rows 1,2,4,5,7,8 fully (54) + 6 gaps = 61
	eq(#rects, 61, "one expanded rect per walkable cell")
	local r = rects[1]
	eq(r.x1 - r.x0, 10, "a walkable cell expands by 1 stud on each side")
end

do
	-- REVIEW-1.md A6: corner squeezes. A barrier sits wherever two walls touch only at a corner; over
	-- 2 000 camps per tier every barrier's two walls are ROCKS (a rock is never beside a gap and a
	-- fence line is a full row), and no point of a barrier is standable: each is within 1 stud of
	-- one of the two rocks, so an honest root never meets one.
	for tier = 1, 4 do
		local withSqueeze, total, notRocks, standable = 0, 0, tally(), tally()
		for s = 1, SEEDS do
			local C = Layout.generateCamp(Config, Rng, Layout.campSeed(Config, 424242, s, tier), tier)
			local _, barriers = Layout.freeRects(Config, C)
			if #barriers > 0 then withSqueeze += 1 end
			total += #barriers
			for _, b in barriers do
				local vx, vz = (b.ax + b.bx) / 2, (b.az + b.bz) / 2
				local walls = 0
				for _, d in { { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } } do
					local c, r = Layout.cellAt(Config, vx + d[1], vz + d[2])
					local k = Layout.cellKind(C, c, r)
					if k ~= "floor" then
						walls += 1
						if k ~= "rock" then note(notRocks, "seed " .. s .. " " .. k .. " at " .. c .. "," .. r) end
					end
				end
				if walls ~= 2 then note(notRocks, "seed " .. s .. ": " .. walls .. " walls round a barrier") end
				for i = 0, 20 do
					local x, z = b.ax + (b.bx - b.ax) * i / 20, b.az + (b.bz - b.az) * i / 20
					-- a 2 x 2 body centred here overlaps a wall cell
					local hitsWall = false
					for _, d in { { -0.999, -0.999 }, { 0.999, -0.999 }, { -0.999, 0.999 }, { 0.999, 0.999 } } do
						local c, r = Layout.cellAt(Config, x + d[1], z + d[2])
						if Layout.cellKind(C, c, r) ~= "floor" then hitsWall = true end
					end
					if not hitsWall then note(standable, string.format("seed %d (%.2f, %.2f)", s, x, z)) end
				end
			end
		end
		print(string.format("  tier %d: %d of %d camps have a corner squeeze (%d barriers)", tier, withSqueeze, SEEDS, total))
		none(notRocks, "tier " .. tier .. ": every barrier sits between exactly two corner-touching rocks")
		none(standable, "tier " .. tier .. ": no point of a barrier is standable")
	end
end

--============================================================================ lairs over many seeds

do
	local bad, rocksBad, protectBad, reachBad, detBad = tally(), tally(), tally(), tally(), tally()
	local resampled, worst, fallbacks, walled = 0, 0, 0, 0
	for s = 1, SEEDS do
		local seed = Layout.lairSeed(Config, 100000 + s * 7)
		local L = Layout.generateLair(Config, Rng, seed)
		if L.attempts > 1 then resampled += 1 end
		worst = math.max(worst, L.attempts)
		if L.fallback then fallbacks += 1 end
		if #L.lines ~= 2 or L.lines[1].row ~= 3 or L.lines[2].row ~= 6 then note(bad, "lines on seed " .. seed) end
		for _, line in L.lines do
			if #line.cols ~= 3 then note(bad, "gaps " .. #line.cols) end
			for c = 1, 9 do
				local isGap = table.find(line.cols, c) ~= nil
				local k = Layout.cellKind(L, c, line.row)
				if isGap and k ~= "floor" then note(bad, "gap not floor") end
				if not isGap and k ~= "fence" then note(bad, "non-gap not fence") end
			end
		end
		if not L.fallback and #L.rocks ~= 6 then note(rocksBad, "rocks " .. #L.rocks) end
		for _, rk in L.rocks do
			local c, r = rk[1], rk[2]
			if r < 1 or r > 7 or r == 3 or r == 6 or (c == 5 and r == 1) then note(protectBad, "rock at " .. c .. "," .. r) end
			for _, line in L.lines do
				if math.abs(r - line.row) == 1 and table.find(line.cols, c) then note(protectBad, "rock beside a gap " .. c .. "," .. r) end
			end
		end
		if not Layout.row8Reachable(L) then note(reachBad, "seed " .. seed) end
		if s <= 50 then
			local again = Layout.generateLair(Config, Rng, seed)
			if Layout.signature(again) ~= Layout.signature(L) then note(detBad, "seed " .. seed) end
		end
		-- walled-in free cells: floor in rows 1..7 not reachable from the entry
		local reach = Layout.reachableFrom(L, 5, 1)
		for r = 1, 7 do
			for c = 1, 9 do
				if Layout.cellKind(L, c, r) == "floor" and not reach[Layout.key(c, r)] then walled += 1 end
			end
		end
	end
	none(bad, "every lair has fence lines at rows 3 and 6 with three gaps each")
	none(rocksBad, "every lair has six rocks")
	none(protectBad, "no rock sits on the entry, a fence row, or beside a gap")
	none(reachBad, "every lair's cage walk is reachable from the entry")
	none(detBad, "the same lair seed always builds the same lair")
	truthy(worst <= Config.Camp.MaxLayoutAttempts, "no lair needed more than MaxLayoutAttempts")
	eq(fallbacks, 0, "no lair fell back to the rockless layout")
	print(string.format("  lairs: %d seeds, %d resampled, worst %d attempts, %d fallbacks, %d walled-in free cells in total",
		SEEDS, resampled, worst, fallbacks, walled))
end

--============================================================================ camps over many seeds, every tier

local FORCED = { 0, 1, 2, 3 }
local ROCKS = { 6, 6, 6, 4 }
local SNARES = { 1, 2, 3, 3 }

for tier = 1, 4 do
	local P = Config.Camps[tier]
	local lineBad, armBad, adjBad, trapBad, reachBad, cageBad, prizeBad, phaseBad, detBad, countBad =
		tally(), tally(), tally(), tally(), tally(), tally(), tally(), tally(), tally(), tally()
	local resampled, worst, fallbacks = 0, 0, 0
	for s = 1, SEEDS do
		local seed = Layout.campSeed(Config, 424242, s, tier)
		local C = Layout.generateCamp(Config, Rng, seed, tier)
		if C.attempts > 1 then resampled += 1 end
		worst = math.max(worst, C.attempts)
		if C.fallback then fallbacks += 1 end

		if #C.lines ~= #P.lines then note(lineBad, "line count") end
		local forced = 0
		for i, line in C.lines do
			if line.row ~= P.lines[i] then note(lineBad, "row") end
			if #line.cols ~= P.gaps[i] then note(lineBad, "gaps") end
			local armed = 0
			for _, c in line.cols do
				local t = Layout.trapAt(C, c, line.row)
				if t and t.kind == "laser" then armed += 1 end
			end
			if armed ~= P.armed[i] then note(armBad, "armed " .. armed) end
			if armed == #line.cols then forced += 1 end
		end
		if forced ~= FORCED[tier] then note(armBad, "forced " .. forced) end

		local lasers, snares = 0, 0
		for _, t in Layout.traps(C) do
			if t.kind == "laser" then
				lasers += 1
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local n = Layout.trapAt(C, t.col + d[1], t.row + d[2])
					if n and n.kind == "laser" then note(adjBad, "lasers adjacent at " .. t.col .. "," .. t.row) end
				end
				if t.on ~= P.on or t.off ~= P.off then note(phaseBad, "timing") end
				if not (t.phase >= 0 and t.phase < P.on + P.off) then note(phaseBad, "phase " .. tostring(t.phase)) end
				-- lasers only ever sit in gaps
				local inGap = false
				for _, line in C.lines do
					if line.row == t.row and table.find(line.cols, t.col) then inGap = true end
				end
				if not inGap then note(trapBad, "laser outside a gap") end
			else
				snares += 1
				if t.row == 8 or t.row < 1 or (t.col == 5 and t.row == 1) then note(trapBad, "snare on a protected cell") end
				for _, line in C.lines do
					if math.abs(t.row - line.row) == 1 and table.find(line.cols, t.col) then note(trapBad, "snare beside a gap") end
					if t.row == line.row then note(trapBad, "snare in a fence row") end
				end
			end
		end
		local wantL = 0
		for _, a in P.armed do wantL += a end
		if lasers ~= wantL then note(countBad, "lasers " .. lasers) end
		if not C.fallback and (snares ~= SNARES[tier] or #C.rocks ~= ROCKS[tier]) then
			note(countBad, "snares " .. snares .. " rocks " .. #C.rocks)
		end
		if C.fallback and (snares ~= 0 or #C.rocks ~= 0) then note(countBad, "fallback kept rocks or snares") end
		for _, rk in C.rocks do
			for _, line in C.lines do
				if math.abs(rk[2] - line.row) == 1 and table.find(line.cols, rk[1]) then note(trapBad, "rock beside a gap") end
			end
		end

		if not Layout.row8Reachable(C) then note(reachBad, "seed " .. seed) end

		if #C.cages ~= 3 then note(cageBad, "cages " .. #C.cages) end
		local cols, prizes = {}, 0
		for _, cg in C.cages do
			if cols[cg.col] then note(cageBad, "duplicate column") end
			cols[cg.col] = true
			local want = if cg.prize then tier else math.max(1, tier - 1)
			local sTier = nil
			for _, sp in Config.Species do if sp.id == cg.sp then sTier = sp.tier end end
			if sTier ~= want then note(cageBad, "cage species tier " .. tostring(sTier) .. " want " .. want) end
			if cg.prize then prizes += 1 end
		end
		if prizes ~= 1 then note(prizeBad, "prizes " .. prizes) end
		for _, cg in C.cages do
			if cg.prize then
				for _, other in C.cages do
					local dp, doo = math.abs(cg.col - 5), math.abs(other.col - 5)
					if doo > dp or (doo == dp and other.col < cg.col) then note(prizeBad, "prize not farthest/lowest") end
				end
			end
		end
		if s <= 50 then
			local again = Layout.generateCamp(Config, Rng, seed, tier)
			if Layout.signature(again) ~= Layout.signature(C) then note(detBad, "seed " .. seed) end
		end
	end
	local tag = "tier " .. tier .. ": "
	none(lineBad, tag .. "fence lines at the tier's rows with the tier's gap counts")
	none(armBad, tag .. "armed gaps per line, and exactly " .. FORCED[tier] .. " forced lines")
	none(adjBad, tag .. "no two lasers are ever 4-adjacent")
	none(trapBad, tag .. "lasers only in gaps; rocks and snares never on protected cells")
	none(countBad, tag .. "the tier's laser, rock and snare counts")
	none(reachBad, tag .. "every camp's cage walk is reachable from the entry")
	none(cageBad, tag .. "three cages on distinct columns holding the right tiers")
	none(prizeBad, tag .. "one prize, on the column farthest from the gate, ties to the lower column")
	none(phaseBad, tag .. "laser timings and phases")
	none(detBad, tag .. "the same camp seed replays the same camp")
	truthy(worst <= Config.Camp.MaxLayoutAttempts, tag .. "attempts within the cap")
	print(string.format("  camps tier %d: %d seeds, %d resampled, worst %d attempts, %d fallbacks", tier, SEEDS, resampled, worst, fallbacks))
end

do
	-- the fallback branch itself: a cap of 0 attempts must still build a legal, reachable camp
	local shadow = table.clone(Config)
	shadow.Camp = table.clone(Config.Camp)
	shadow.Camp.MaxLayoutAttempts = 0
	local C = Layout.generateCamp(shadow, Rng, 12345, 4)
	truthy(C.fallback, "with no attempts allowed the camp falls back")
	eq(#C.rocks, 0, "fallback has no rocks")
	eq(Layout.count(C, "snare"), 0, "fallback has no snares")
	eq(Layout.count(C, "laser"), 5, "fallback still arms the tier's lasers")
	truthy(Layout.row8Reachable(C), "fallback is reachable")
end

do
	local name = Layout.campName(Config, 77)
	eq(name, Layout.campName(Config, 77), "camp names are a pure function of the seed")
	truthy(string.match(name, "^%a+ %a+'s? Camp$") ~= nil, "camp name reads like 'Muddy Boots' Camp': " .. name)
	local seen = {}
	local n = 0
	for s = 1, 4000 do
		local nm = Layout.campName(Config, s)
		if not seen[nm] then seen[nm] = true; n += 1 end
	end
	eq(n, 64, "64 distinct camp names")
	local boots = false
	for nm in seen do if string.find(nm, "Boots' Camp") then boots = true end end
	truthy(boots, "a name ending in s takes a bare apostrophe")
end

--============================================================================ REVIEW-1

do
	-- R1-1 (critical). Layout.key(col, row) = (row + 2) * 32 + (col + 2), so (col + 32, row - 1)
	-- names the same trap as (col, row). The server's "clear" only checked type(number), refunded
	-- the trap and left its saved string behind; every rejoin refunded the string again.
	local L = blankLair()
	truthy(Layout.place(Config, L, 2, 2, "laser"), "a laser at (2,2)")
	eq(Layout.key(2 + 32, 2 - 1), Layout.key(2, 2), "the alias really collides in Layout.key")
	eq(Layout.clear(L, 2 + 32, 2 - 1), nil, "clearing at the alias (34,1) clears nothing")
	eq(Layout.clear(L, 2 - 32, 2 + 1), nil, "...nor at (-30,3)")
	eq(Layout.clear(L, 2.5, 2), nil, "...nor at a fractional column")
	eq(Layout.clear(L, 2, 0), nil, "...nor on the fence row")
	eq(Layout.clear(L, 2, 8), nil, "...nor on the cage walk")
	eq(Layout.count(L, "laser"), 1, "the laser survives every one of those")
	truthy(not Layout.isBuildCell(L, 34, 1) and Layout.isBuildCell(L, 2, 2), "isBuildCell: rows 1..7, columns 1..9, integers only")
	eq(Layout.clear(L, 2, 2), "laser", "clearing at its own cell still works")
end

do
	-- R1-1. A save naming the same cell twice can only come from a desync (the alias above). Every
	-- copy after the first is removed WITHOUT a refund; the first string for a cell is refunded
	-- when the current rules reject it (a Config change), exactly once.
	local L = blankLair()
	local kept, removed, refundable = Layout.reconcile(Config, L, { "L:2:2", "L:2:2", "S:2:2", "L:2:3", "L:2:3", "L:4:4" })
	eq(#kept, 2, "kept: the first L:2:2 and L:4:4")
	eq(#removed, 4, "removed: the two later strings for (2,2) and both strings for fence cell (2,3)")
	eq(refundable and #refundable, 1, "refundable: only the first (2,3) string")
	eq(refundable and refundable[1], "L:2:3", "...by name")
	local _, _, noRefund = Layout.reconcile(Config, blankLair(), { "L:2:2", "L:2:2", "L:2:2", "L:2:2" })
	eq(noRefund and #noRefund, 0, "four copies of one legal trap refund nothing")
end

do
	-- R1-5. A carried cryptid escapes through the GATE only. Each row-1 cell's trusted rect grows
	-- 1 stud into the front fence, which cellAt calls row 0, so "row <= 0" let a noclipper out of
	-- any row-1 cell. The gate cell is x 32..40; its trusted rect is x 31..41.
	truthy(Layout.escaped(Config, 36, 23.5), "the gate cell escapes")
	truthy(Layout.escaped(Config, 31.2, 20), "...including the gate's 1-stud wall margin")
	truthy(not Layout.escaped(Config, 4, 23.5), "column 1 pushed into the front fence does not")
	truthy(not Layout.escaped(Config, 68, 23.5), "...nor column 9")
	truthy(not Layout.escaped(Config, 36, 24.5), "row 1 in front of the gate does not")
end

print(string.format("Layout: %d passed, %d failed", passed, failed))
if failed > 0 then error("Layout tests failed") end
