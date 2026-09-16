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

-- HOW MUCH DEAD END THERE IS TO FALL INTO on the way across storey `s`, in cells.
--
-- The shortest path is not a description of a maze's difficulty. Two 6x6 mazes with the same
-- 19-step route are not the same run: one is a corridor with three stubs off it, the other is a
-- thicket. A player cannot see the maze from above, so what costs them time is the branch mass
-- hanging off the route — and at the 6x5 cap that varies far more than the route length does.
--
-- For a PERFECT maze this is not a simulation, it is arithmetic. A runner with perfect memory at
-- a junction picks uniformly among the exits they have not tried, so each wrong branch is
-- entered before the right one with probability exactly one half; a wrong branch of m cells
-- costs 2m steps, every edge in and every edge back. Expectation: 2m * 1/2 = m. So the expected
-- lost steps is simply THE NUMBER OF CELLS sitting in branches off the route.
--
-- Measured against a blind-explorer simulator over 2000 storeys at the cap, the coefficient this
-- predicts (1.0) fits at 1.0002 by least squares, and steps / (route + waste) has a CV of 1.12%.
-- tests/Curve.spec.luau re-measures that with its OWN simulator and never reads this function.
--
-- The exit cell's own branches are excluded: the run ends the moment the runner steps onto it.
function VaultPath.wastedCells(model: any, storey: number): number
	local grid = model.grids[storey + 1]
	local cells = model.cells
	local from, to = model.entryCells[storey + 1], model.exitCells[storey + 1]
	local function id(cx: number, cy: number) return cy * cells + cx end

	local dist = VaultPath.distances(model, storey, from)

	-- Walk back down the distance gradient from the exit to mark the route. Reusing `distances`
	-- rather than keeping a second parent map means there is only one BFS in this file that
	-- anything depends on being right.
	local onPath = {}
	local cur = { to.cx, to.cy }
	local d = dist[id(to.cx, to.cy)]
	if d == nil then return 0 end
	onPath[id(cur[1], cur[2])] = true
	while d > 0 do
		local stepped = false
		for _, n in ipairs(neighbours(grid, cells, cur[1], cur[2])) do
			if dist[id(n[1], n[2])] == d - 1 then
				cur = n
				d -= 1
				onPath[id(cur[1], cur[2])] = true
				stepped = true
				break
			end
		end
		assert(stepped, "VaultPath.wastedCells: the distance map has no way back to the entry")
	end

	-- Everything reachable from a route cell without stepping on a route cell is in some wrong
	-- branch. One flood counts them all: in a perfect maze no cell can hang off two route cells,
	-- so nothing is counted twice.
	local seen, wasted = {}, 0
	local queue, head = {}, 1
	local function push(cx: number, cy: number)
		for _, n in ipairs(neighbours(grid, cells, cx, cy)) do
			if not onPath[id(n[1], n[2])] and seen[id(n[1], n[2])] == nil then
				seen[id(n[1], n[2])] = true
				queue[#queue + 1] = n
				wasted += 1
			end
		end
	end
	for key in pairs(onPath) do
		local cy = math.floor(key / cells)
		local cx = key - cy * cells
		if not (cx == to.cx and cy == to.cy) then push(cx, cy) end
	end
	while head <= #queue do
		local c = queue[head]
		head += 1
		push(c[1], c[2])
	end
	return wasted
end

--============================================================================ the clock

-- One cell step is TWO fine cells — the corridor cell you leave and the one you cross into —
-- so it is 2 * cellSize studs, not cellSize. Getting this wrong halves every route in the game
-- and makes every vault look twice as winnable as it is.
function VaultPath.studsPerStep(model: any): number
	return 2 * model.cellSize
end

--============================================================================ the jump

-- HOW FAR A RUNNER CARRIES, jumping, while gaining `rise` studs of height. This is the number
-- that decides whether a gap in the climb shaft is a jump or a formality, and it is solved, not
-- guessed: Roblox launches the character at Humanoid.JumpPower studs/s and pulls it down at
-- Workspace.Gravity, and the game leaves both at their defaults (Config.Movement).
--
--     y(t) = J t - g t^2 / 2 = rise   ->   t = (J + sqrt(J^2 - 2 g rise)) / g
--
-- taking the DESCENDING root, because the runner lands on the way down. Horizontal speed is
-- WalkSpeed for the whole flight: Roblox keeps applying the walk force in the air, so there is
-- no run-up to model and a standing hop off a 3-stud pad reaches as far as a running one.
--
-- Returns 0 for a rise the jump cannot reach at all (the discriminant goes negative above
-- J^2 / 2g = 6.4 studs), rather than a complex number or a silent nan.
function VaultPath.jumpReach(cfg: any, rise: number): number
	local mv = cfg.Movement
	local disc = mv.JumpPower * mv.JumpPower - 2 * mv.Gravity * rise
	if disc < 0 then return 0 end
	local t = (mv.JumpPower + math.sqrt(disc)) / mv.Gravity
	return mv.WalkSpeed * t
end

-- Seconds of free fall through `drop` studs, from rest. The runner who misses a hop is not
-- pushed, they are dropped, so this is the honest half of what a miss costs.
function VaultPath.fallSeconds(cfg: any, drop: number): number
	if drop <= 0 then return 0 end
	return math.sqrt(2 * drop / cfg.Movement.Gravity)
end

--============================================================================ the climb

-- Seconds to climb ONE storey: `n` pads of the shaft, each one a jump. The pad count is read
-- off the model (floor(storeyHeight / stepRise)), never assumed to be six.
--
-- THIS IS THE CLEAN CLIMB — the one where nothing is missed. `VaultPath.climbSeconds` is what
-- the budget actually pays, and it is this plus the expected cost of the misses.
function VaultPath.climbBaseSeconds(cfg: any, model: any): number
	local steps = math.floor(model.storeyHeight / model.stepRise)
	return steps * cfg.Movement.ClimbSecondsPerStep
end

-- WHAT A MISSED HOP COSTS, in seconds, averaged over which hop was missed.
--
-- There is no checkpoint in the shaft and nothing to catch you: a miss drops the runner to the
-- storey floor they started from, and the climb starts again at pad 1. So a miss costs the fall
-- itself plus getting back under the first pad — and every hop already made is re-paid through
-- the retry count, not through this number.
--
-- MISSES ARE NOT SPREAD EVENLY UP THE SHAFT, and the first cut of this function averaged the
-- drop over the six hops as if they were. They are not: a miss restarts at pad 1, so hop 1 is
-- attempted every round and hop 6 only in a round that got that far. Hop k is reached with
-- probability q^(k-1), so that is the weight a miss there carries.
--
-- The fall is weighted too, not evaluated at the average drop — sqrt is concave, so
-- E[sqrt(drop)] and sqrt(E[drop]) are different numbers and the second one is the flattering one.
--
-- tests/Curve.spec.luau's rolled climb is what caught the uniform version: 20000 simulated
-- climbs came out 10% cheaper than this file was pricing them.
function VaultPath.missSeconds(cfg: any, model: any): number
	local n = math.floor(model.storeyHeight / model.stepRise)
	local q = 1 - cfg.Ascent.ModelMissChance
	local wsum, fsum = 0, 0
	for k = 1, n do
		local w = q ^ (k - 1)
		wsum += w
		fsum += w * VaultPath.fallSeconds(cfg, (k - 1) * model.stepRise)
	end
	return fsum / wsum + cfg.Ascent.ModelReapproachSeconds
end

-- EXPECTED seconds for one storey transition, misses included.
--
-- n hops, each missed independently with probability p, and a miss sends the runner back to the
-- bottom of the shaft. That is the textbook "n consecutive successes with restart":
--
--     E[hop attempts] = (1 - q^n) / (p q^n)        q = 1 - p
--     E[misses]       = p * E[attempts]
--
-- so the expected cost is E[attempts] hops plus E[misses] falls. At p = 0 the first expression
-- is 0/0; the limit is n, and the branch below is that limit rather than a nan — which matters,
-- because p = 0 is exactly the mutation a spec uses to ask whether the budget pays for the obby
-- at all.
--
-- E[misses] IS NOT attempts - n. That was the first cut and it is wrong by a factor of three at
-- p = 0.04: attempts - n counts the successful hops of the rounds that ended in a fall as if they
-- were falls. Every attempt is a Bernoulli trial with the same p, so the count of failures among
-- them is p times the count — which is what tests/Curve.spec.luau's rolled climb measures.
--
-- p IS A MODEL, NOT A MEASUREMENT. Nobody has played this game, so Config.Ascent.ModelMissChance
-- is a stated assumption about a competent player in the same way measure_curve.luau's blind
-- explorer is — and REVIEW-4 sweeps it rather than defending one value. What the geometry
-- guarantees (tests/VaultFloor.spec.luau, `climbIsFailable`) is that p is not ZERO: every hop in
-- the shaft crosses a gap wider than the runner, inside a reach the jump actually has.
function VaultPath.climbAttempts(cfg: any, model: any): (number, number)
	local n = math.floor(model.storeyHeight / model.stepRise)
	local p = cfg.Ascent.ModelMissChance
	if p <= 0 then return n, 0 end
	local q = 1 - p
	local qn = q ^ n
	local attempts = (1 - qn) / (p * qn)
	return attempts, p * attempts
end

function VaultPath.climbSeconds(cfg: any, model: any): number
	local attempts, misses = VaultPath.climbAttempts(cfg, model)
	return attempts * cfg.Movement.ClimbSecondsPerStep
		+ misses * VaultPath.missSeconds(cfg, model)
end

-- The part of the climb the runner spends BACK DOWN AT THE STOREY THEY CAME FROM. A clean climb
-- rises out of the collapse and never returns; a missed hop drops them onto the floor the plane
-- is about to reach. So this — not the whole climb — is what storey s's deadline has to cover on
-- top of the walk across it. See VaultPath.demand.
function VaultPath.climbRetrySeconds(cfg: any, model: any): number
	return VaultPath.climbSeconds(cfg, model) - VaultPath.climbBaseSeconds(cfg, model)
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
	-- THE CLIMB IS NOW AN OBBY AND THE CLOCK KNOWS IT, in two separate pieces.
	--
	--   climbBase   the clean six hops. Part of the WALK demand, and multiplied by the slack the
	--               same way the corridors are.
	--   climbRetry  the expected cost of the hops that are missed. Kept OUT of the walk demand,
	--               because the countdown pays it AT COST — see VaultPath.demand.
	--
	-- `climb` (both together) is what the run actually takes, and it is what the optimal-runner
	-- timeline below is ticked against.
	local climbBase = VaultPath.climbBaseSeconds(cfg, model)
	local climbRetry = VaultPath.climbRetrySeconds(cfg, model)
	local climb = climbBase + climbRetry

	-- How much of a storey's branch mass is charged to the demand. 0 would price the vault as if
	-- the runner could see the maze from above; 1 prices the whole expected blind walk. See
	-- Config.Collapse.WasteWeight for why it is neither.
	local beta = cfg.Collapse.WasteWeight

	local arriveAt, leaveAt, walkSteps, gemDetour = {}, {}, {}, {}
	local wasteCells, walkDemandAt, obbyBy = {}, {}, {}
	local t, dt = 0, 0
	for s = 0, model.storeys - 1 do
		local from = model.entryCells[s + 1]
		local to = model.exitCells[s + 1]
		local dist = VaultPath.distances(model, s, from)
		local steps = dist[to.cy * model.cells + to.cx]
		assert(steps ~= nil, string.format(
			"VaultPath.measure: storey %d's exit cell is unreachable from its entry cell", s))

		local waste = VaultPath.wastedCells(model, s)
		wasteCells[s + 1] = waste
		dt += (steps + beta * waste) * perStep
		walkDemandAt[s + 1] = dt
		-- HOW MUCH OBBY HAS HAPPENED BY THE TIME THE RUNNER IS CLEAR OF STOREY s. Clearing storey s
		-- means completing the transition out of it, which is the (s+1)-th climb, so every retry on
		-- transitions 0..s is behind them — and every one of those retries was seconds spent
		-- standing on a floor the plane was rising toward. Only the retries: the clean climb is a
		-- monotone rise out of the danger and is already in the walk demand above.
		obbyBy[s + 1] = (s + 1) * climbRetry
		if s < model.storeys - 1 then dt += climbBase end

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
		climbBaseSeconds = VaultPath.climbBaseSeconds(cfg, model),
		climbRetrySeconds = climbRetry,
		secondsPerStep = perStep,
		totalSeconds = leaveAt[model.storeys],
		-- ...and the same timeline as the DEMAND prices it: the BFS route plus its share of the
		-- branch mass a blind runner loses time in. `leaveAt`/`totalSeconds` stay the pure
		-- shortest-path clock, because that is what tests/Collapse.spec.luau simulates against.
		wasteCells = wasteCells,
		-- THE DEMAND, SPLIT. `walkDemandAt[s+1]` is what the maze asks of a blind runner up to the
		-- stair on storey s, clean climbs included — the part the slack multiplies. `obbyBy[s+1]`
		-- is the expected seconds of missed hops behind them by then — the part the countdown pays
		-- at cost. The top storey's entries are the escape constraint.
		walkDemandAt = walkDemandAt,
		obbyBy = obbyBy,
		walkDemandTotal = walkDemandAt[model.storeys],
		obbyTotal = (model.storeys - 1) * climbRetry,
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
--
-- THE OBBY IS PAID AT COST, NOT AT SLACK. Each inequality is
--
--     slack * walk(s)  +  obby(s)   <=   frac(s) * T
--
-- and NOT `slack * (walk(s) + obby(s))`. The slack exists to cover what nobody can predict — how
-- much of the maze a runner who cannot see it from above will wander into. The expected cost of
-- the crumbling shaft is not that: it is a known quantity this file computes exactly, so paying
-- 1.85x of it at floor 1 would be handing out a premium on the one part of the run that is not
-- uncertain. Measured, 6000 modelled runs a floor: charging the obby inside the slack moved Gold
-- completion from 49.1% to 52.1% at floor 400 — the RAGE OBBY MADE THE GAME EASIER. At cost it
-- reads 50.3%, and REVIEW-3's whole curve survives with the obby in it. What the obby adds to a
-- run is not its mean, which is paid for; it is its TAIL, which is not.
--
-- Returns the two halves separately so a spec can ask "is the budget the same multiple of what
-- this maze demands, whatever maze the floor rolled?" — the question that decides whether two
-- mazes of one floor are the same difficulty — without re-implementing the derivation to ask it.
-- Which constraint BINDS depends on the slack, so both halves come from the same binding one.
function VaultPath.demand(cfg: any, model: any, VaultFloor: any, slack: number): (number, number)
	local m = VaultPath.measure(cfg, model)
	local walk, obby = m.walkDemandTotal, m.obbyTotal
	local best = walk * slack + obby
	for s = 0, model.storeys - 2 do
		local frac = VaultFloor.planeFractionAt(model, model.killLines[s + 1])
		-- frac <= 0 would mean the plane is already at storey s's kill line at t = 0. That is a
		-- broken vault, not a hard one; refuse rather than divide by it.
		assert(frac > 0, string.format(
			"VaultPath.demand: storey %d is already under the collapse at t=0", s))
		local w, o = m.walkDemandAt[s + 1] / frac, m.obbyBy[s + 1] / frac
		if w * slack + o > best then best, walk, obby = w * slack + o, w, o end
	end
	return walk, obby
end

function VaultPath.countdown(cfg: any, model: any, slack: number, VaultFloor: any): number
	local walk, obby = VaultPath.demand(cfg, model, VaultFloor, slack)
	return math.max(math.ceil(walk * slack + obby), cfg.Collapse.MinSeconds)
end

return VaultPath
