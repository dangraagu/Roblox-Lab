-- MazeGen.spec — the generator is a verbatim copy (md5 c269d302...) of labyrint-spill's, and
-- FACILITY's reachability argument leans on exactly one of its properties: the grid it returns is
-- a PERFECT maze, so every room is reachable before a single extra door is added.
-- Run: luau tests/MazeGen.spec.luau
local Rng = require("../src/shared/Rng")
local MazeGen = require("../src/shared/MazeGen")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- Count open passages between neighbouring cells and flood from (0,0).
local function analyse(n, seed)
	local grid = MazeGen.generate(n, n, Rng.new(seed))
	local edges = 0
	local adj = {}
	local function id(x, y) return y * n + x + 1 end
	for i = 1, n * n do adj[i] = {} end
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x < n - 1 and grid[2 * y + 1][2 * x + 2] == false then
				edges += 1
				table.insert(adj[id(x, y)], id(x + 1, y)); table.insert(adj[id(x + 1, y)], id(x, y))
			end
			if y < n - 1 and grid[2 * y + 2][2 * x + 1] == false then
				edges += 1
				table.insert(adj[id(x, y)], id(x, y + 1)); table.insert(adj[id(x, y + 1)], id(x, y))
			end
		end
	end
	local seen, q, h = { [1] = true }, { 1 }, 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in adj[a] do
			if not seen[b] then seen[b] = true; table.insert(q, b) end
		end
	end
	return edges, #q, grid
end

local badEdges, badReach = 0, 0
for _, n in { 4, 5 } do
	for i = 1, 2000 do
		local edges, reached = analyse(n, 7919 * i + n)
		if edges ~= n * n - 1 then badEdges += 1 end
		if reached ~= n * n then badReach += 1 end
	end
end
eq(badEdges, 0, "every 4x4 and 5x5 maze is a spanning tree (n*n - 1 passages), 4000 seeds")
eq(badReach, 0, "every cell is reachable from (0,0), 4000 seeds")

do
	local _, _, a = analyse(5, 12345)
	local _, _, b = analyse(5, 12345)
	local same = true
	for y = 0, 10 do
		for x = 0, 10 do
			if a[y][x] ~= b[y][x] then same = false end
		end
	end
	truthy(same, "same seed -> identical maze")
end

print(string.format("MazeGen: %d passed, %d failed", passed, failed))
