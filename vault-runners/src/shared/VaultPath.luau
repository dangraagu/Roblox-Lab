--!strict
-- VaultPath.luau — hvor LANG TID hvelvet faktisk tar. REN logikk.
--
-- This is the file the game was missing. Vault Runners is a race against a rising kill plane,
-- and until this module existed NOTHING in the repo measured how long the maze takes to walk.
-- The countdown was three hand-typed numbers (70 / 80 / 90 seconds) and the plane's speed was
-- (vault height) / (countdown) — so ADDING STOREYS MADE THE PLANE FASTER through the lower ones.
-- The adversarial review walked the BFS-optimal path at WalkSpeed 16 with climbing costed at
-- ZERO seconds and still died on storey 0 of Silver at 13.7s of 80. Silver and Gold — 1200 and
-- 6000 banked gems — were mathematically unwinnable, and no number in Config said so.
--
-- So the countdown is no longer typed in. It is DERIVED, here, from the vault that was actually
-- generated: BFS the shortest route through each storey's maze, cost the climb, and give the
-- runner that much time times a slack factor. A bigger maze mathematically cannot get a shorter
-- deadline, because the deadline is a function of the maze.
--
-- Pure by construction: cfg + a built model in, plain numbers out. No Roblox global, no clock,
-- no geometry of its own — `model` is exactly what VaultFloor.build returned. A bare
-- `require("./X")` resolves in the luau CLI and is INVALID in Roblox, so this file, like every
-- other module in src/shared, requires nothing at all.
--
-- WHAT IS AND IS NOT COUNTED. Counted: the shortest walk from where you land on a storey to the
-- stair out of it, at Config.Movement.WalkSpeed, plus one climb per storey transition. NOT
-- counted: gems. Detouring for gems is the whole game, and the slack factor is what pays for it
-- — `measure().gemDetour` prices the cheapest one-gem detour per storey so a spec can assert the
-- player can afford at least that.

local VaultPath = {}

--============================================================================ the maze graph

-- grid[fy][fx] == true means WALL. Maze cell (cx, cy) sits at fine cell (2cx+1, 2cy+1), and two
-- neighbouring cells are connected when the fine cell BETWEEN them is open. MazeGen is a
-- recursive backtracker, so the maze is perfect (exactly one route between any two cells) — but
-- BFS is used anyway rather than a walk-the-only-path shortcut, because "perfect" is a property
-- of the generator, not of this file, and a future generator with loops must not silently start
-- reporting a route that is longer than the one a player would take.
local function neighbours(grid: any, cells: number, cx: number, cy: number)
	local out = {}
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for _, d in ipairs(dirs) do
		local nx, ny = cx + d[1], cy + d[2]
		if nx >= 0 and nx < cells and ny >= 0 and ny < cells then
			local row = grid[2 * cy + 1 + d[2]]
			if row ~= nil and row[2 * cx + 1 + d[1]] == false then
				out[#out + 1] = { nx, ny }
			end
		end
	end
	return out
end

-- Breadth-first distance, in CELL STEPS, from `from` to every reachable cell of one storey.
-- Returns a table indexed by `cy * cells + cx`. Unreachable cells are simply absent — a caller
-- asking for one gets nil and must decide what that means, rather than silently reading a 0.
function VaultPath.distances(model: any, storey: number, from: any): any
	local grid = model.grids[storey + 1]
	local cells = model.cells
	local dist = {}
	local function id(cx: number, cy: number) return cy * cells + cx end

	dist[id(from.cx, from.cy)] = 0
	local queue = { { from.cx, from.cy } }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local d = dist[id(cur[1], cur[2])]
		for _, n in ipairs(neighbours(grid, cells, cur[1], cur[2])) do
			if dist[id(n[1], n[2])] == nil then
				dist[id(n[1], n[2])] = d + 1
				queue[#queue + 1] = n
			end
		end
	end
	return dist
end

function VaultPath.stepsBetween(model: any, storey: number, from: any, to: any): number?
	local dist = VaultPath.distances(model, storey, from)
	return dist[to.cy * model.cells + to.cx]
end

--============================================================================ the clock

-- One cell step is TWO fine cells — the corridor cell you leave and the one you cross into —
-- so it is 2 * cellSize studs, not cellSize. Getting this wrong halves every route in the game
-- and makes every vault look twice as winnable as it is.
function VaultPath.studsPerStep(model: any): number
	return 2 * model.cellSize
end

-- Seconds to climb ONE storey: `n` steps of the spiral, each one a jump. The step count is read
-- off the model (floor(storeyHeight / stepRise)), never assumed to be six.
function VaultPath.climbSeconds(cfg: any, model: any): number
	local steps = math.floor(model.storeyHeight / model.stepRise)
	return steps * cfg.Movement.ClimbSecondsPerStep
end

-- The whole run, as a timeline. Every number is SECONDS from the drop-in.
--
--   arriveAt[s+1]  the runner is standing on storey s, at the cell they landed in
--   leaveAt[s+1]   they have walked to the stair (or, on the top storey, to the exit pad)
--   gemDetour[s+1] the cheapest extra seconds to touch ONE gem on storey s on the way past
--
-- The top storey has no stair, so leaveAt[storeys] IS the escape: totalSeconds.
function VaultPath.measure(cfg: any, model: any): any
	local walkSpeed = cfg.Movement.WalkSpeed
	local perStep = VaultPath.studsPerStep(model) / walkSpeed
	local climb = VaultPath.climbSeconds(cfg, model)

	local arriveAt, leaveAt, walkSteps, gemDetour = {}, {}, {}, {}
	local t = 0
	for s = 0, model.storeys - 1 do
		local from = model.entryCells[s + 1]
		local to = model.exitCells[s + 1]
		local dist = VaultPath.distances(model, s, from)
		local steps = dist[to.cy * model.cells + to.cx]
		assert(steps ~= nil, string.format(
			"VaultPath.measure: storey %d's exit cell is unreachable from its entry cell", s))

		arriveAt[s + 1] = t
		walkSteps[s + 1] = steps
		t += steps * perStep
		leaveAt[s + 1] = t

		-- The cheapest one-gem detour on this storey, measured the way a player would actually
		-- take it: entry -> gem -> exit, minus the direct entry -> exit they would have walked
		-- anyway. Needs a SECOND BFS, rooted at the exit, or the return leg is guesswork.
		local back = VaultPath.distances(model, s, to)
		local best = nil
		for _, g in ipairs(model.gems) do
			if g.storey == s and g.cell ~= nil then
				local a = dist[g.cell.cy * model.cells + g.cell.cx]
				local b = back[g.cell.cy * model.cells + g.cell.cx]
				if a ~= nil and b ~= nil then
					local extra = (a + b - steps) * perStep
					if best == nil or extra < best then best = extra end
				end
			end
		end
		gemDetour[s + 1] = best

		if s < model.storeys - 1 then t += climb end
	end

	return {
		walkSteps = walkSteps,
		arriveAt = arriveAt,
		leaveAt = leaveAt,
		gemDetour = gemDetour,
		climbSeconds = climb,
		secondsPerStep = perStep,
		totalSeconds = leaveAt[model.storeys],
	}
end

--============================================================================ the countdown

-- THE DERIVATION. Read this before changing any number in Config.Collapse.
--
-- The collapse rises at a constant speed and covers the whole vault in exactly one countdown, so
-- the fraction of the countdown at which it reaches storey s's kill line is a pure property of
-- the GEOMETRY (VaultFloor.planeFractionAt). The runner has to be off storey s by then. That is
-- one inequality per storey:
--
--     leaveAt(s)  <=  frac(s) * T          for every storey below the top
--     leaveAt(top) <=  T                   the seal itself
--
-- Solve each for T, take the worst, multiply by the slack the player is owed for gems and for
-- not being a BFS solver, and round UP to a whole second (rounding up only ever gives time
-- away). A vault with more storeys has a bigger leaveAt AND a smaller frac(s) for its lower
-- storeys, so both effects now PUSH THE COUNTDOWN UP. Under the old model they both pushed the
-- effective deadline DOWN, which is how Silver shipped unwinnable.
-- `VaultFloor` arrives as an ARGUMENT, the same way MazeGen and Rng arrive at VaultFloor.build.
-- Nothing in src/shared requires anything: `require("./VaultFloor")` resolves in the luau CLI
-- and is INVALID in Roblox, and that mistake has already cost this repo a server that loaded
-- green in every test and not at all in the engine.
function VaultPath.countdown(cfg: any, model: any, slack: number, VaultFloor: any): number
	local m = VaultPath.measure(cfg, model)
	local need = m.totalSeconds
	for s = 0, model.storeys - 2 do
		local frac = VaultFloor.planeFractionAt(model, model.killLines[s + 1])
		-- frac <= 0 would mean the plane is already at storey s's kill line at t = 0. That is a
		-- broken vault, not a hard one; refuse rather than divide by it.
		assert(frac > 0, string.format(
			"VaultPath.countdown: storey %d is already under the collapse at t=0", s))
		local required = m.leaveAt[s + 1] / frac
		if required > need then need = required end
	end
	local t = math.ceil(need * slack)
	return math.max(t, cfg.Collapse.MinSeconds)
end

return VaultPath
