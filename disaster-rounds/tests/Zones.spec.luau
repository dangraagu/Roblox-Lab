-- Zones: the red rule (DESIGN.md §2.3). Run: luau tests/Zones.spec.luau
--
-- Red means exactly where it hits. Every hit test the server runs goes through this module, and every red thing a
-- client draws is drawn from the same numbers. Here: just inside is a hit, just outside is safe, for all four
-- disasters; a hit needs the root inside at EVERY server sample in [T, T + LagGrace], so a late step out still
-- dodges (ties go to the dodger); hovering or flying never helps (the tests are 2-D or decided by the cell).
local Zones = require("../src/shared/Zones")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local H = Config.Hits
local IC = Config.Island
local ringR = Zones.ringRadius(Config)
eq(ringR, 4.5, "a ring's radius is HitRadius 3.0 + PlayerRadius 1.5")
eq(Zones.funnelRadius(Config), 6.5, "the funnel's is 5.0 + 1.5")

--======================================================================= disks: inclusive edge, 2-D only

do
	truthy(Zones.inDisk(10, 20, ringR, 10 + 4.49, 20), "4.49 studs from a ring's centre is inside")
	truthy(Zones.inDisk(10, 20, ringR, 10 + 4.5, 20), "exactly on the edge is inside (the red is drawn to the edge)")
	eq(Zones.inDisk(10, 20, ringR, 10 + 4.51, 20), false, "4.51 studs is outside")
	eq(Zones.inDisk(0, 0, ringR, 3.2, 3.2), false, "a diagonal 4.53 away is outside")
	truthy(Zones.inDisk(0, 0, ringR, 3.1, 3.1), "a diagonal 4.38 away is inside")
end

--======================================================================= the ring judge: every sample in [T, T + grace]

local function judgeRun(impact: number, samples: { { number } }): string
	local j = Zones.newJudge(impact, H.LagGrace)
	local result = "none"
	for _, s in samples do
		local r = Zones.judgeSample(j, "p", s[1], s[2] == 1)
		if r ~= nil then
			result = r
			if r == "hit" then break end
		end
	end
	return result
end

do
	eq(judgeRun(10, { { 9.9, 1 }, { 10.0, 1 }, { 10.1, 1 }, { 10.2, 1 } }), "hit", "inside at T, T+0.1 and T+0.2: hit")
	eq(judgeRun(10, { { 9.9, 1 }, { 10.0, 1 }, { 10.1, 1 }, { 10.2, 0 } }), "dodge", "out at T+0.2 (a late step on the server's view): dodge")
	eq(judgeRun(10, { { 9.9, 0 }, { 10.0, 1 }, { 10.1, 0 }, { 10.2, 1 } }), "dodge", "out at any sample in the window: dodge")
	eq(judgeRun(10, { { 9.9, 1 }, { 10.0, 0 }, { 10.1, 1 }, { 10.2, 1 } }), "dodge", "out exactly at T: dodge")
	eq(judgeRun(10, { { 9.8, 0 }, { 9.9, 0 }, { 10.0, 1 }, { 10.1, 1 }, { 10.2, 1 } }), "hit", "stepping IN before T is a hit (the ring is the truth)")
	eq(judgeRun(10, { { 10.05, 1 }, { 10.15, 1 }, { 10.25, 0 } }), "hit", "unaligned samples: both in-window samples inside, hit")
	eq(judgeRun(10, { { 10.05, 1 }, { 10.15, 0 }, { 10.25, 1 } }), "dodge", "unaligned samples: out at 10.15, dodge")
	eq(judgeRun(10, { { 9.9, 1 }, { 10.4, 0 } }), "dodge", "a stalled tick with no sample in the window: out at the next sample, dodge")
	eq(judgeRun(10, { { 9.9, 0 }, { 10.4, 1 } }), "hit", "a stalled tick with no sample in the window: in at the next sample, hit")
	-- a judge decides each player once
	local j = Zones.newJudge(5, H.LagGrace)
	eq(Zones.judgeSample(j, "a", 5.0, false), "dodge", "player a out at T: dodge")
	eq(Zones.judgeSample(j, "a", 5.2, true), nil, "and nothing more for player a")
	eq(Zones.judgeSample(j, "b", 5.0, true), nil, "player b inside at T: pending")
	eq(Zones.judgeSample(j, "b", 5.2, true), "hit", "player b inside through T+0.2: hit")
	eq(Zones.judgeSample(j, "b", 5.3, true), nil, "and a hit is reported once")
	truthy(Zones.judgeDone(j, 5.21), "the judge is done once T + grace has passed")
	eq(Zones.judgeDone(j, 5.1), false, "not before")
end

--======================================================================= dwell: continuous time inside (flood, holes, funnel)

do
	local t = Zones.newDwell()
	eq(Zones.dwell(t, "k", true, 0.0, 0.6), false, "the first sample over flooded ground is not yet a hit")
	eq(Zones.dwell(t, "k", true, 0.5, 0.6), false, "0.5 s is not yet")
	eq(Zones.dwell(t, "k", true, 0.6, 0.6), true, "0.6 s in a row is a hit")
	eq(Zones.dwell(t, "j", true, 0.0, 0.6), false, "a jump across a one-cell flooded gap ...")
	eq(Zones.dwell(t, "j", true, 0.5, 0.6), false, "... spends 0.5 s over the water ...")
	eq(Zones.dwell(t, "j", false, 0.6, 0.6), false, "... and lands dry: no hit")
	eq(Zones.dwell(t, "j", true, 0.7, 0.6), false, "and the clock starts again from zero")
	eq(Zones.dwell(t, "j", true, 1.2, 0.6), false, "0.5 s later still not")
	eq(Zones.dwell(t, "j", true, 1.3, 0.6), true, "0.6 s after re-entering: hit")
	Zones.clearDwell(t, "j")
	eq(Zones.dwell(t, "j", true, 5.0, 0.6), false, "a cleared clock starts over")
end

--======================================================================= the four disasters: just inside, just outside

do
	-- Meteor (a ring): covered above
	-- Flood: the cell under the root decides, not the root's height
	eq(Zones.flooded(Config.Island, 0, 0.01), true, "water 0.01 over the beach top floods it")
	eq(Zones.flooded(Config.Island, 0, 0.0), false, "water level with the top does not (ties go to the dodger)")
	eq(Zones.flooded(Config.Island, 2, 8.5), true, "a level-2 top (y 8) under water at 8.5 is flooded")
	eq(Zones.flooded(Config.Island, 3, 10.0), false, "a level-3 top (y 12) never floods at the last rise (10)")
	-- Tornado: the funnel's disk
	truthy(Zones.inDisk(0, 0, Zones.funnelRadius(Config), 6.49, 0), "6.49 studs from the funnel is inside")
	eq(Zones.inDisk(0, 0, Zones.funnelRadius(Config), 6.51, 0), false, "6.51 is outside")
	-- Quake: the cell under the root (its square), at every sample in [drop, drop + grace]
	local IC = Config.Island
	truthy(Zones.overCell(IC, 7, 7, 3.99, -3.99), "a root 3.99 studs from the centre cell's middle is over it")
	eq(Zones.overCell(IC, 7, 7, 4.01, 0), false, "4.01 studs east is over the next cell")
	eq(Zones.overCell(IC, 7, 7, 0, -4.01), false, "4.01 studs south too")
	-- one formula with MapGen.cellAt, to the last bit: a root at 3.999999999999999 is in whichever cell cellAt says
	-- (fairness check 2026-10-07: cellAt said cell 8, the drop judge said cell 7, and a bot on safe ground was hit)
	local MapGen = require("../src/shared/MapGen")
	local agree = true
	for _, x in { 3.999999999999999, 4.000000000000001, -3.999999999999999, 4, 12 - 1e-15, 11.999999999999998, 0.5 } do
		for _, z in { 11.5, 3.999999999999999, -44.00000000000001 } do
			local i, j = MapGen.cellAt(IC, x, z)
			for ci = 1, IC.Grid do
				for cj = 1, IC.Grid do
					if Zones.overCell(IC, ci, cj, x, z) ~= (ci == i and cj == j) then agree = false end
				end
			end
		end
	end
	truthy(agree, "overCell and MapGen.cellAt agree on every boundary point, to the last bit")
end

--======================================================================= the exit search (the ExitStuds rule)

do
	local open = function(_x: number, _z: number) return true end
	eq(Zones.exitDistance(0, 0, {}, open, 0.8, 30), 0, "nothing red: already out")
	local d1 = Zones.exitDistance(0, 0, { { x = 0, z = 0, r = ringR } }, open, 0.8, 30)
	truthy(math.abs(d1 - (ringR + 0.8)) < 0.51, string.format("out of one ring at its centre: about 4.5 + 0.8 studs (%.2f)", d1))
	-- boxed in by rings on every side but one
	local disks = { { x = 0, z = 0, r = ringR } }
	for a = 0, 5 do
		local ang = a * math.pi / 4
		table.insert(disks, { x = math.cos(ang) * 8, z = math.sin(ang) * 8, r = ringR })
	end
	local d2 = Zones.exitDistance(0, 0, disks, open, 0.8, 30)
	truthy(d2 > ringR + 0.8 and d2 < 30, string.format("boxed in on six sides: the exit is further (%.2f)", d2))
	local wall = function(x: number, _z: number) return x > -2 end
	local d3 = Zones.exitDistance(0, 0, { { x = 0, z = 0, r = ringR } }, wall, 0.8, 30)
	truthy(d3 >= ringR + 0.8 - 0.01, string.format("a wall on one side: still out the other way (%.2f)", d3))
	local closed = function(_x: number, _z: number) return false end
	eq(Zones.exitDistance(0, 0, { { x = 0, z = 0, r = ringR } }, closed, 0.8, 30), math.huge, "nowhere to stand: no exit (math.huge)")
end

--======================================================================= red you can SEE on terraced ground (REVIEW-1 F7, F8)

-- The hit tests are 2-D, but the island is terraced: a flat red disc drawn at one cell's top is buried inside a higher
-- neighbour's column (the review measured 34-35 % of rings with part of their reach hidden that way). Every red piece
-- is therefore drawn as a red volume from just above the LOWEST top under it to just above the HIGHEST, so the ground
-- of every cell it reaches shows red. These helpers say which cells a piece reaches and how tall its volume is.
local function setOf(cells): { [string]: boolean }
	local s = {}
	for _, c in cells do s[c.i .. "," .. c.j] = true end
	return s
end
local function count(s): number
	local n = 0
	for _ in s do n += 1 end
	return n
end
-- the cell (i, j) of a point, by MapGen.cellAt's arithmetic (an independent copy for the spec)
local function cellOf(x: number, z: number): (number?, number?)
	local n, cs = IC.Grid, IC.CellStuds
	local i, j = math.floor(x / cs + n / 2) + 1, math.floor(z / cs + n / 2) + 1
	if i < 1 or i > n or j < 1 or j > n then return nil, nil end
	return i, j
end
-- how far into the shape the cell's square reaches: >= 0 means they meet (by brute force over the square)
local function squareBounds(i: number, j: number): (number, number, number, number)
	local n, cs = IC.Grid, IC.CellStuds
	local lx, lz = (i - 1 - n / 2) * cs, (j - 1 - n / 2) * cs
	return lx, lx + cs, lz, lz + cs
end

do
	-- a ring at a cell's centre reaches that cell and its four side neighbours, not the diagonals (5.66 > 4.5)
	local s = setOf(Zones.cellsUnderDisk(IC, 0, 0, ringR))
	eq(count(s), 5, "a ring at the centre of cell (7, 7) reaches 5 cells")
	truthy(s["7,7"] and s["6,7"] and s["8,7"] and s["7,6"] and s["7,8"], "itself and its four side neighbours")
	-- 3 studs toward +X: it now also reaches the two +X diagonals (corner 4.12 away) and not the -X side (7 away)
	local s2 = setOf(Zones.cellsUnderDisk(IC, 3, 0, ringR))
	eq(count(s2), 6, "a ring 1 stud from the +X side reaches 6 cells")
	truthy(s2["8,6"] and s2["8,8"] and not s2["6,7"], "the +X diagonals (4.12 away), not the -X neighbour (7 away)")
	-- never off the grid
	local edge = Zones.cellsUnderDisk(IC, 51.9, 51.9, 6.5)
	local okEdge = #edge > 0
	for _, c in edge do
		if c.i < 1 or c.i > IC.Grid or c.j < 1 or c.j > IC.Grid then okEdge = false end
	end
	truthy(okEdge, "at the island's corner it lists only cells of the island (" .. #edge .. ")")
	eq(#Zones.cellsUnderDisk(IC, 80, 0, ringR), 0, "out over the sea: no cell")
	-- a ring whose edge exactly touches a cell boundary: the hit test is edge-inclusive (inDisk), so a root just inside
	-- the neighbour's square IS hit, and that neighbour's ground must show red (the headless terrace check found rings
	-- centred at x = 32.5, whose reach ends at x = 28.0 exactly, drawn without the cell on the far side of x = 28)
	local touch = setOf(Zones.cellsUnderDisk(IC, 32.5, 0, ringR))
	truthy(touch["10,7"], "a ring at x = 32.5 reaches x = 28.0 exactly: cell 10 (x 20..28) is listed")
	truthy(Zones.inDisk(32.5, 0, ringR, 28 - 1e-12, 0), "(a root at x = 28 - 1e-12, over cell 10, is inside the ring)")
	local tb = setOf(Zones.cellsUnderBox(IC, 32.5, 0, 0, 1, 1, 4.5))
	truthy(tb["10,7"], "a box whose side lies on x = 28.0 lists cell 10 too")

	-- 400 random discs and 400 random boxes against a 0.05-stud brute force: every cell a sample point lands in is
	-- listed, and every listed cell the brute force missed is a sliver under 0.05 studs deep
	local s3 = 4242
	local function r01()
		s3 = (1664525 * s3 + 1013904223) % 4294967296
		return s3 / 4294967296
	end
	local missed, extra = 0, 0
	for _ = 1, 400 do
		local cx, cz = (r01() * 2 - 1) * 58, (r01() * 2 - 1) * 58
		local r = if r01() < 0.5 then ringR else Zones.funnelRadius(Config)
		local listed = setOf(Zones.cellsUnderDisk(IC, cx, cz, r))
		local seen = {}
		local step = 0.05
		for x = cx - r, cx + r + 1e-9, step do
			for z = cz - r, cz + r + 1e-9, step do
				if (x - cx) ^ 2 + (z - cz) ^ 2 <= r * r then
					local i, j = cellOf(x, z)
					if i then seen[i .. "," .. j] = true end
				end
			end
		end
		for k in seen do if not listed[k] then missed += 1 end end
		for k in listed do
			if not seen[k] then
				local i, j = string.match(k, "(%d+),(%d+)")
				local lx, hx, lz, hz = squareBounds(tonumber(i) :: number, tonumber(j) :: number)
				local dx = math.max(lx - cx, 0, cx - hx)
				local dz = math.max(lz - cz, 0, cz - hz)
				if math.sqrt(dx * dx + dz * dz) < r - 0.05 then extra += 1 end
			end
		end
	end
	eq(missed, 0, "400 random discs: no cell the disc reaches is left out")
	eq(extra, 0, "and no cell is listed that it does not reach (but for slivers under 0.05 studs)")

	-- boxes: the tornado's path pieces. Along +X from (0, 0) to (8, 0), 13 wide: x 0..8 is cells 7-8, z -6.5..6.5 is 6-8
	local b = setOf(Zones.cellsUnderBox(IC, 4, 0, 1, 0, 4, 6.5))
	eq(count(b), 6, "a path piece 8 long and 13 wide along +X from a cell centre reaches 6 cells")
	truthy(b["7,6"] and b["7,7"] and b["7,8"] and b["8,6"] and b["8,7"] and b["8,8"], "2 along by 3 across")
	local bmissed, bextra = 0, 0
	for _ = 1, 400 do
		local cx, cz = (r01() * 2 - 1) * 56, (r01() * 2 - 1) * 56
		local a = r01() * math.pi * 2
		local ux, uz = math.cos(a), math.sin(a)
		local hl, hw = 0.2 + r01() * 2, 6.5
		local listed = setOf(Zones.cellsUnderBox(IC, cx, cz, ux, uz, hl, hw))
		local seen = {}
		local step = 0.05
		for s = -hl, hl + 1e-9, step do
			for w = -hw, hw + 1e-9, step do
				local i, j = cellOf(cx + ux * s - uz * w, cz + uz * s + ux * w)
				if i then seen[i .. "," .. j] = true end
			end
		end
		for k in seen do if not listed[k] then bmissed += 1 end end
		for k in listed do
			if not seen[k] then
				-- a listed cell the samples missed must touch the box within 0.05 studs: check its four corners' and the
				-- box's four corners' cross-distances (a sliver)
				local i, j = string.match(k, "(%d+),(%d+)")
				local lx, hx, lz, hz = squareBounds(tonumber(i) :: number, tonumber(j) :: number)
				local close = false
				for _, s in { -hl, hl } do
					for _, w in { -hw, hw } do
						local px, pz = cx + ux * s - uz * w, cz + uz * s + ux * w
						local dx = math.max(lx - px, 0, px - hx)
						local dz = math.max(lz - pz, 0, pz - hz)
						if math.sqrt(dx * dx + dz * dz) < 0.08 then close = true end
					end
				end
				for _, q in { { lx, lz }, { lx, hz }, { hx, lz }, { hx, hz } } do
					local dx, dz = q[1] - cx, q[2] - cz
					local along, across = dx * ux + dz * uz, -dx * uz + dz * ux
					if math.abs(along) < hl + 0.08 and math.abs(across) < hw + 0.08 then close = true end
				end
				if math.max(lx, math.min(hx, cx)) == cx and math.max(lz, math.min(hz, cz)) == cz then close = true end
				if not close then bextra += 1 end
			end
		end
	end
	eq(bmissed, 0, "400 random path pieces: no cell a piece reaches is left out")
	eq(bextra, 0, "and no cell is listed that it does not reach (but for slivers under 0.05 studs)")

	-- the volume: from just above the lowest top to just above the highest
	local levels = { ["7,7"] = 2, ["8,7"] = 3 }
	local function levelAt(i: number, j: number): number? return levels[i .. "," .. j] end
	local lo, hi = Zones.redSpan(IC, { { i = 7, j = 7 }, { i = 8, j = 7 } }, levelAt)
	truthy(math.abs((lo or 0) - (2 * IC.LevelStuds + 0.05)) < 1e-9, "a ring over a step from level 2 up to 3 starts 0.05 studs over the level-2 top")
	truthy(math.abs((hi or 0) - (3 * IC.LevelStuds + 0.25)) < 1e-9, "and reaches 0.25 studs over the level-3 top: red shows on both terraces")
	local flo, fhi = Zones.redSpan(IC, { { i = 7, j = 7 } }, levelAt)
	truthy(math.abs(((fhi or 0) - (flo or 0)) - 0.2) < 1e-9, "over flat ground it is the old flat disc, 0.2 studs thick")
	truthy(math.abs((flo or 0) - (2 * IC.LevelStuds + 0.05)) < 1e-9, "0.05 studs over the top")
	eq(Zones.redSpan(IC, { { i = 1, j = 1 } }, levelAt), nil, "over no known cell: nothing to draw")
end

print(string.format("Zones: %d passed, %d failed", passed, failed))
assert(failed == 0, "Zones tests failed")
