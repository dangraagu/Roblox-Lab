-- Spec for Lamps: the Lamp Grid feeder, lights out with "all lit" as the goal (DESIGN.md §3.3, §3.5.3).
-- Run: luau tests/Lamps.spec.luau 2>&1
--
-- Tapping a lamp flips it and its four neighbours. A grid is made by pressing a hidden set of k lamps
-- from the lit grid, and kept only when the MINIMUM number of presses that solves it is exactly k.
-- The 3x3 grid has a unique solution; the 4x4 grid has 16 press sets that change nothing, so the
-- minimum is taken over all of them. A hint names one lamp of a minimum solution FROM THE CURRENT grid.
local Lamps = require("../src/shared/Lamps")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function randOf(seed)
	local r = Rng.new(seed)
	return function() return r:next() end
end

eq(Lamps.nullity(3), 1, "3x3: only pressing nothing changes nothing (unique solutions)")
eq(Lamps.nullity(4), 16, "4x4: 16 press sets change nothing (null space of dimension 4)")

-- press(): a corner flips 3, an edge 4, the centre 5
do
	local g = Lamps.litGrid(3)
	truthy(Lamps.allLit(g), "a fresh grid is all lit")
	Lamps.press(g, 3, 1)
	local off = 0
	for _, v in g do if not v then off += 1 end end
	eq(off, 3, "a corner press flips 3 lamps")
	Lamps.press(g, 3, 1)
	truthy(Lamps.allLit(g), "pressing twice undoes it")
	Lamps.press(g, 3, 5)
	off = 0
	for _, v in g do if not v then off += 1 end end
	eq(off, 5, "the centre flips 5 lamps")
	Lamps.press(g, 3, 2)
	off = 0
	local g2 = Lamps.litGrid(3)
	Lamps.press(g2, 3, 2)
	for _, v in g2 do if not v then off += 1 end end
	eq(off, 4, "an edge flips 4 lamps")
end

local function checkGrids(n, k, count, seed)
	local rand = randOf(seed)
	local bad = { solved = 0, min = 0, set = 0, solve = 0, hint = 0, gens = 0 }
	local attempts, maxAttempts = 0, 0
	for _ = 1, count do
		local g = Lamps.generate({ n = n, k = k }, rand)
		if g == nil then
			bad.gens += 1
			continue
		end
		attempts += g.attempts
		maxAttempts = math.max(maxAttempts, g.attempts)
		if Lamps.allLit(g.grid) then bad.solved += 1 end
		if Lamps.minPresses(g.grid, n) ~= k then bad.min += 1 end
		local copy = table.clone(g.grid)
		for _, i in g.set do Lamps.press(copy, n, i) end
		if not Lamps.allLit(copy) or #g.set ~= k then bad.set += 1 end
		local sol = Lamps.solve(g.grid, n)
		local copy2 = table.clone(g.grid)
		for _, i in sol do Lamps.press(copy2, n, i) end
		if #sol ~= k or not Lamps.allLit(copy2) then bad.solve += 1 end
		-- after a few random presses, a hint lamp is part of a minimum solution from the CURRENT grid
		local cur = table.clone(g.grid)
		for _ = 1, 1 + math.floor(rand() * 3) do Lamps.press(cur, n, 1 + math.floor(rand() * n * n)) end
		if not Lamps.allLit(cur) then
			local before = Lamps.minPresses(cur, n)
			local h = Lamps.hint(cur, n, rand)
			local after = table.clone(cur)
			if h then Lamps.press(after, n, h) end
			if h == nil or Lamps.minPresses(after, n) ~= before - 1 then bad.hint += 1 end
		end
	end
	print(string.format("  %dx%d k=%d: %d grids, attempts mean %.2f max %d", n, n, k, count, attempts / count, maxAttempts))
	eq(bad.gens, 0, string.format("%dx%d k=%d: every generation succeeded", n, n, k))
	eq(bad.solved, 0, string.format("%dx%d k=%d: never starts solved", n, n, k))
	eq(bad.min, 0, string.format("%dx%d k=%d: the minimum is exactly k", n, n, k))
	eq(bad.set, 0, string.format("%dx%d k=%d: the hidden set solves it", n, n, k))
	eq(bad.solve, 0, string.format("%dx%d k=%d: solve() finds a k-press solution from the grid alone", n, n, k))
	eq(bad.hint, 0, string.format("%dx%d k=%d: a hint lamp cuts the minimum by one from the current grid", n, n, k))
end
for k = 1, 4 do checkGrids(3, k, 400, 60 + k) end
for k = 1, 5 do checkGrids(4, k, 400, 70 + k) end

eq(Lamps.hintCap(2), 1, "k 2: 1 hint")
eq(Lamps.hintCap(5), 4, "k 5: 4 hints")
eq(Lamps.hintCap(1), 1, "k 1: still 1 hint")
eq(Lamps.hint(Lamps.litGrid(4), 4, randOf(1)), nil, "no hint on a solved grid")
eq(#Lamps.solve(Lamps.litGrid(4), 4), 0, "a solved grid needs no presses")

print(string.format("Lamps: %d passed, %d failed", passed, failed))
if failed > 0 then error("Lamps spec failed", 0) end
