--!strict
-- Lamps.luau — the Lamp Grid feeder: lights out on an n x n grid, the goal is EVERY LAMP LIT.
-- Pure; no Roblox. Randomness is injected as `rand(): number in [0, 1)`.
--
-- A grid is an array of n*n booleans (true = lit), row by row. Pressing lamp i flips it and the lamps
-- above, below, left and right of it. Rules (tests/Lamps.spec.luau pins each):
--   * a grid is made by pressing a hidden set of k lamps from the lit grid, and kept only when the
--     MINIMUM number of presses that solves it is exactly k, so the difficulty knob is exact;
--   * the minimum is taken over every solution: on 4x4 there are 16 of them for any solvable grid
--     (a null space of dimension 4), on 3x3 exactly one;
--   * `solve` and `hint` work from the current grid only, so a hint accounts for presses already made.
-- Solutions are found by light chasing: choose the first row's presses (2^n ways), then each lamp left
-- unlit in row r - 1 forces the press below it; a choice is a solution when the last row ends lit.

local Lamps = {}

local effectsCache: { [number]: { number } } = {}

-- effects[i] = bitmask of the lamps pressing i flips (bit i-1 is lamp i)
function Lamps.effects(n: number): { number }
	local cached = effectsCache[n]
	if cached then return cached end
	local eff = {}
	for r = 1, n do
		for c = 1, n do
			local i = (r - 1) * n + c
			local m = bit32.lshift(1, i - 1)
			if r > 1 then m = bit32.bor(m, bit32.lshift(1, i - n - 1)) end
			if r < n then m = bit32.bor(m, bit32.lshift(1, i + n - 1)) end
			if c > 1 then m = bit32.bor(m, bit32.lshift(1, i - 2)) end
			if c < n then m = bit32.bor(m, bit32.lshift(1, i)) end
			eff[i] = m
		end
	end
	effectsCache[n] = eff
	return eff
end

function Lamps.litGrid(n: number): { boolean }
	local g = {}
	for i = 1, n * n do g[i] = true end
	return g
end

function Lamps.allLit(grid: { boolean }): boolean
	for _, v in grid do
		if not v then return false end
	end
	return true
end

-- Flip lamp i and its neighbours, in place.
function Lamps.press(grid: { boolean }, n: number, i: number)
	local m = Lamps.effects(n)[i]
	for j = 1, n * n do
		if bit32.btest(m, bit32.lshift(1, j - 1)) then
			grid[j] = not grid[j]
		end
	end
end

local function unlitMask(grid: { boolean }): number
	local m = 0
	for i, v in grid do
		if not v then m = bit32.bor(m, bit32.lshift(1, i - 1)) end
	end
	return m
end

local function popcount(x: number): number
	local c = 0
	while x ~= 0 do
		x = bit32.band(x, x - 1)
		c += 1
	end
	return c
end

-- Every press set (bitmask) that turns `mask` (the unlit lamps) into all lit.
local function allSolutions(mask: number, n: number): { number }
	local eff = Lamps.effects(n)
	local out = {}
	for first = 0, 2 ^ n - 1 do
		local state = mask
		local presses = 0
		for c = 1, n do
			if bit32.btest(first, bit32.lshift(1, c - 1)) then
				state = bit32.bxor(state, eff[c])
				presses = bit32.bor(presses, bit32.lshift(1, c - 1))
			end
		end
		for r = 2, n do
			for c = 1, n do
				local above = (r - 2) * n + c
				if bit32.btest(state, bit32.lshift(1, above - 1)) then
					local i = (r - 1) * n + c
					state = bit32.bxor(state, eff[i])
					presses = bit32.bor(presses, bit32.lshift(1, i - 1))
				end
			end
		end
		if state == 0 then table.insert(out, presses) end
	end
	return out
end

-- How many press sets change nothing: 1 on 3x3, 16 on 4x4.
function Lamps.nullity(n: number): number
	return #allSolutions(0, n)
end

local function bestOf(mask: number, n: number): number?
	local best, bestCount = nil, math.huge
	for _, s in allSolutions(mask, n) do
		local pc = popcount(s)
		if pc < bestCount then
			best, bestCount = s, pc
		end
	end
	return best
end

-- A minimum press list (lamp indices, ascending) that lights the grid.
function Lamps.solve(grid: { boolean }, n: number): { number }
	local best = bestOf(unlitMask(grid), n)
	local out = {}
	if best == nil then return out end
	for i = 1, n * n do
		if bit32.btest(best, bit32.lshift(1, i - 1)) then table.insert(out, i) end
	end
	return out
end

function Lamps.minPresses(grid: { boolean }, n: number): number
	local best = bestOf(unlitMask(grid), n)
	if best == nil then return math.huge end
	return popcount(best)
end

local function below(rand: () -> number, n: number): number
	local v = math.floor(rand() * n) + 1
	if v > n then v = n end
	if v < 1 then v = 1 end
	return v
end

-- spec = { n, k, maxAttempts? (500) } -> { grid, set (the k pressed lamps), attempts } or nil
function Lamps.generate(spec: any, rand: () -> number): any
	local n, k = spec.n, spec.k
	for attempt = 1, spec.maxAttempts or 500 do
		local cells = {}
		for i = 1, n * n do cells[i] = i end
		for i = #cells, 2, -1 do
			local j = below(rand, i)
			cells[i], cells[j] = cells[j], cells[i]
		end
		local grid = Lamps.litGrid(n)
		local set = {}
		for i = 1, k do
			Lamps.press(grid, n, cells[i])
			set[i] = cells[i]
		end
		if Lamps.minPresses(grid, n) == k then
			table.sort(set)
			return { grid = grid, set = set, attempts = attempt }
		end
	end
	return nil
end

function Lamps.hintCap(k: number): number
	return math.max(1, k - 1)
end

-- One lamp of a minimum solution from the CURRENT grid; nil when it is already lit.
function Lamps.hint(grid: { boolean }, n: number, rand: () -> number): number?
	if Lamps.allLit(grid) then return nil end
	local sol = Lamps.solve(grid, n)
	if #sol == 0 then return nil end
	return sol[below(rand, #sol)]
end

return Lamps
