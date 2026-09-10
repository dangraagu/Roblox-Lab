-- Curve — IS "DEEPER" ACTUALLY HARDER? Run: luau tests/Curve.spec.luau
--
-- Collapse.spec asks whether a floor is winnable. This one asks whether floor 400 is a different
-- game from floor 40, and whether two mazes of the SAME floor are the same difficulty. Both were
-- BLOCK findings in REVIEW-2:
--
--   "From floor 26 onward every floor of every tier is the identical difficulty spec. The
--    6000-gem Gold unlock buys a tier whose entire difficulty curve is 25 floors of slack
--    tightening, then flat forever."
--
--   "The countdown now swings hard in both directions between adjacent floors, so 'deeper'
--    regularly means 'shorter and easier'."
--
-- The size caps stay where they are (6 cells x 5 storeys) — a bigger maze means a longer
-- countdown, and Collapse.spec's MaxSeconds is what holds that down. So the SLACK is the curve,
-- and this file is what stops it going flat again.
--
-- THE MEASURING INSTRUMENT IS A SIMULATOR, NOT THE FORMULA. src/shared/VaultPath.luau prices a
-- maze's exploration overhead in closed form; if this spec re-asserted that closed form it would
-- only be checking that the same arithmetic still arithmetics. So the difficulty numbers below
-- come from actually WALKING each maze with a blind explorer — no maze knowledge, perfect
-- memory, uniform choice at junctions — and the closed form is never consulted. The two agreeing
-- to 1.1% is a fact about the game; it is not built into the test.

local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local VaultFloor = require("../src/shared/VaultFloor")
local VaultPath = require("../src/shared/VaultPath")
local MazeGen = require("../src/shared/MazeGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

local C = Config

-- The floors REVIEW-3 reports. 1 is the first run a player ever makes; 30 is just past every
-- size cap, which is where the old curve went flat; 400 is deep enough that a flat tail shows up.
local REPORT_FLOORS = { 1, 10, 30, 60, 100, 200, 400 }

--============================================================================ the schedule itself

do
	-- A curve that stops curving is the defect. Not "non-increasing" — STRICTLY decreasing, at
	-- every single floor, because "non-increasing" is exactly what a flat tail satisfies.
	local flatAt = nil
	for f = 1, 1000 do
		local a = Progression.difficulty(C, 1, f).slack
		local b = Progression.difficulty(C, 1, f + 1).slack
		if b >= a and flatAt == nil then flatAt = f end
	end
	ok(flatAt == nil, string.format(
		"the slack curve stops tightening at floor %s — from there on, every deeper floor is the "
			.. "same difficulty as the one before it", tostring(flatAt)))

	-- ...and still moving where a committed player actually is. A schedule that is technically
	-- strictly decreasing but by 1e-6 a floor is flat in every sense a player can feel.
	local s400 = Progression.difficulty(C, 1, 400).slack
	local s1000 = Progression.difficulty(C, 1, 1000).slack
	ok(s400 - s1000 >= 0.02, string.format(
		"floors 400..1000 shed only %.4f of slack — the tail is flat in everything but the sign",
		s400 - s1000))

	-- every report floor is measurably tighter than the one before it
	for i = 2, #REPORT_FLOORS do
		local a = Progression.difficulty(C, 1, REPORT_FLOORS[i - 1]).slack
		local b = Progression.difficulty(C, 1, REPORT_FLOORS[i]).slack
		ok(a - b >= 0.01, string.format(
			"floor %d is only %.4f tighter than floor %d",
			REPORT_FLOORS[i], a - b, REPORT_FLOORS[i - 1]))
	end

	-- the ends of the schedule are the ends of the schedule
	local s1 = Progression.difficulty(C, 1, 1).slack
	ok(math.abs(s1 - C.Collapse.Slack) < 1e-9, "floor 1 is owed the full Config.Collapse.Slack")
	local worst = math.huge
	for f = 1, 20000 do worst = math.min(worst, Progression.difficulty(C, 1, f).slack) end
	ok(worst >= C.Collapse.MinSlack, string.format(
		"some floor is given %.4f slack, under MinSlack %.4f", worst, C.Collapse.MinSlack))
	ok(worst > 1, string.format(
		"some floor is given %.4f — less time than the vault demands, which is unwinnable", worst))
end

--============================================================================ the budget IS the demand times the slack

-- The jitter half of the finding, stated exactly: whatever maze a floor happens to roll, the
-- budget it is handed must be the SAME MULTIPLE of what that maze demands. Anything else and
-- two runs on one floor are two different difficulties.
--
-- The budget is now `walk * slack + obby` — the obby's expected cost is paid at cost, outside
-- the slack — so the multiple to check is the one the SLACK is applied to, with the obby
-- allowance taken back off first. Same property, same failure it catches; the obby is a fixed
-- number of seconds per storey and cannot be the thing that varies between two mazes of a floor.
do
	local worstSpread, worstAt = 0, ""
	for _, floor in ipairs(REPORT_FLOORS) do
		local lo, hi = math.huge, 0
		for k = 1, 60 do
			local spec = Progression.difficulty(C, 3, floor)
			spec.seed = k * 2654435761 + floor * 7919
			local model = VaultFloor.build(C, spec, MazeGen, Rng)
			local walk, obby = VaultPath.demand(C, model, VaultFloor, spec.slack)
			local ratio = (VaultPath.countdown(C, model, spec.slack, VaultFloor) - obby) / walk
			lo, hi = math.min(lo, ratio), math.max(hi, ratio)
		end
		local spread = (hi - lo) / lo
		if spread > worstSpread then worstSpread, worstAt = spread, "floor " .. floor end
	end
	-- The countdown rounds UP to a whole second, so the ratio can only wobble by one second in
	-- the shortest budget any of these floors gets — about 1.5%. Nothing else may move it.
	ok(worstSpread <= 0.02, string.format(
		"budget/demand varies by %.2f%% across mazes of the same floor (%s) — the floor's "
			.. "difficulty depends on which maze it rolled", 100 * worstSpread, worstAt))
end

--============================================================================ the explorer

-- A player cannot see the maze. Perfect memory, uniform choice among unvisited exits, one step
-- back out of a dead end. Deliberately the OPTIMISTIC end of "cannot see the maze": no
-- hesitation, no misread corner, no missed jump, no detour for a gem. So every completion rate
-- below is an upper bound on the real one, and what it is good for is COMPARING floors.
local function lcg(seed)
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	return function(n) s = (s * 16807) % 2147483647; return 1 + (s % n) end
end

local function openNeighbours(grid, cells, cx, cy)
	local out = {}
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local nx, ny = cx + d[1], cy + d[2]
		if nx >= 0 and nx < cells and ny >= 0 and ny < cells then
			local row = grid[2 * cy + 1 + d[2]]
			if row ~= nil and row[2 * cx + 1 + d[1]] == false then out[#out + 1] = { nx, ny } end
		end
	end
	return out
end

-- THE OBBY, ROLLED RATHER THAN AVERAGED. Six pads, five studs of air between them, each one
-- crumbling under the runner — so hops get missed, and a miss drops them to the bottom of the
-- shaft to start again. VaultPath prices that in closed form; this walks it.
--
-- The distinction is the whole point of putting the obby in this file. A budget that pays the
-- EXPECTED cost and a runner who pays the EXPECTED cost cancel exactly, and the obby would have
-- changed nothing measurable. What it actually adds is a right-hand TAIL — most climbs are
-- clean, some cost four falls — and a tail is what turns a comfortable floor into a failed run.
-- So the explorer rolls each hop, and `climbSeconds` is never consulted here.
--
-- A miss costs the fall from the pad below the one that was missed, plus getting back under
-- pad 1. Missing hop 1 is a step off a kerb; missing hop 6 is fifteen studs.
local function climbSeconds(model, rand)
	local n = math.floor(model.storeyHeight / model.stepRise)
	local hop = C.Movement.ClimbSecondsPerStep
	local pMillionths = math.floor(C.Ascent.ModelMissChance * 1e6 + 0.5)
	local t, k = 0, 1
	local guard = 0
	while k <= n do
		guard += 1
		if guard > 100000 then break end
		t += hop
		if rand(1000000) <= pMillionths then
			t += VaultPath.fallSeconds(C, (k - 1) * model.stepRise) + C.Ascent.ModelReapproachSeconds
			k = 1
		else
			k += 1
		end
	end
	return t
end

local function exploreSeconds(model, seed)
	local rand = lcg(seed)
	local perStep = VaultPath.studsPerStep(model) / C.Movement.WalkSpeed
	local t = 0
	for s = 0, model.storeys - 1 do
		local grid, cells = model.grids[s + 1], model.cells
		local from, to = model.entryCells[s + 1], model.exitCells[s + 1]
		local function id(cx, cy) return cy * cells + cx end
		local visited = { [id(from.cx, from.cy)] = true }
		local stack = { { from.cx, from.cy } }
		local steps = 0
		while #stack > 0 do
			local cur = stack[#stack]
			if cur[1] == to.cx and cur[2] == to.cy then break end
			local options = {}
			for _, n in ipairs(openNeighbours(grid, cells, cur[1], cur[2])) do
				if not visited[id(n[1], n[2])] then options[#options + 1] = n end
			end
			if #options == 0 then table.remove(stack); steps += 1
			else
				local p = options[rand(#options)]
				visited[id(p[1], p[2])] = true; stack[#stack + 1] = p; steps += 1
			end
		end
		t += steps * perStep
		if s < model.storeys - 1 then t += climbSeconds(model, rand) end
	end
	return t
end

--============================================================================ the closed form is right

-- VaultPath.climbSeconds prices the shaft with the textbook "n consecutive successes with
-- restart" expectation. This spec never uses it — the explorer above rolls every hop — so the
-- two agreeing is a FACT about the game rather than something built into the test, the same way
-- wastedCells and the blind explorer agree in REVIEW-3 §2. If they ever diverge, the countdown
-- is paying for an obby other than the one being played.
do
	local spec = Progression.difficulty(C, 3, 1)
	spec.seed = Progression.seedFor(C, 3, 1)
	local model = VaultFloor.build(C, spec, MazeGen, Rng)
	local rand = lcg(20260910)
	local N = 20000
	local sum, worstFalls = 0, 0
	local base = math.floor(model.storeyHeight / model.stepRise) * C.Movement.ClimbSecondsPerStep
	for _ = 1, N do
		local t = climbSeconds(model, rand)
		sum += t
		if t > worstFalls then worstFalls = t end
	end
	local mean = sum / N
	local priced = VaultPath.climbSeconds(C, model)
	ok(math.abs(mean - priced) / priced <= 0.02, string.format(
		"%d rolled climbs average %.3fs and VaultPath prices them at %.3fs — the budget is paying "
			.. "for a different obby than the one being climbed", N, mean, priced))
	ok(mean > base, string.format(
		"a rolled climb averages %.3fs against a clean %.3fs — nothing is ever being missed",
		mean, base))
	print(string.format("  climb: clean %.2fs, priced %.2fs, %d rolled %.2fs (worst %.2fs)",
		base, priced, N, mean, worstFalls))
end

local MAZES, TRIALS = 120, 12

local function sample(tier, floor, salt)
	local out = {}
	for k = 1, MAZES do
		local spec = Progression.difficulty(C, tier, floor)
		spec.seed = k * 2654435761 + salt
		local model = VaultFloor.build(C, spec, MazeGen, Rng)
		local budget = VaultPath.countdown(C, model, spec.slack, VaultFloor)
		local times, sum = {}, 0
		for j = 1, TRIALS do
			local t = exploreSeconds(model, k * 131 + j * 977 + salt)
			times[#times + 1] = t; sum += t
		end
		out[#out + 1] = { budget = budget, times = times, mean = sum / TRIALS }
	end
	return out
end

local function completion(pop)
	local w, n = 0, 0
	for _, p in ipairs(pop) do
		for _, t in ipairs(p.times) do n += 1; if t <= p.budget then w += 1 end end
	end
	return w / n
end

--============================================================================ the curve, measured

do
	local rates = {}
	for i, floor in ipairs(REPORT_FLOORS) do
		rates[i] = completion(sample(3, floor, 7 * floor))
	end
	for i = 2, #REPORT_FLOORS do
		ok(rates[i] < rates[i - 1], string.format(
			"floor %d completes %.1f%% of modelled runs and floor %d completes %.1f%% — deeper is "
				.. "not harder", REPORT_FLOORS[i], 100 * rates[i], REPORT_FLOORS[i - 1], 100 * rates[i - 1]))
	end
	-- ...and the whole curve has to actually go somewhere. Two floors 400 apart that differ by a
	-- percentage point are monotone and still flat.
	ok(rates[1] - rates[#rates] >= 0.25, string.format(
		"floor 1 completes %.1f%% and floor 400 completes %.1f%% — %.1f points of curve across "
			.. "the whole game", 100 * rates[1], 100 * rates[#rates], 100 * (rates[1] - rates[#rates])))
	print(string.format("  Gold completion: f1 %.0f%%  f10 %.0f%%  f30 %.0f%%  f60 %.0f%%  f100 %.0f%%  f200 %.0f%%  f400 %.0f%%",
		100 * rates[1], 100 * rates[2], 100 * rates[3], 100 * rates[4], 100 * rates[5],
		100 * rates[6], 100 * rates[7]))
end

--============================================================================ the jitter, measured

-- Two mazes of the same floor must be the same difficulty TO A PLAYER, not just on paper. The
-- budget is a multiple of the demand by construction (asserted above) — this asks whether the
-- demand is a good description of the maze. A budget derived from the shortest path alone is
-- not: it cannot see how much dead end there is to fall into, and the dead-end mass of a 6x6
-- maze varies far more than its shortest path does.
do
	local pop = sample(3, 100, 4242)
	local costs = {}
	for _, p in ipairs(pop) do costs[#costs + 1] = p.mean / p.budget end
	table.sort(costs)
	local sum = 0
	for _, v in ipairs(costs) do sum += v end
	local mean = sum / #costs
	local var = 0
	for _, v in ipairs(costs) do var += (v - mean) ^ 2 end
	local cv = math.sqrt(var / #costs) / mean
	local gap = costs[#costs] / costs[1]

	ok(cv <= 0.10, string.format(
		"the difficulty of Gold floor 100 varies %.2f%% between mazes (CV of per-maze explorer "
			.. "cost) — which maze the floor rolled matters more than which floor it is", 100 * cv))
	ok(gap <= 2.0, string.format(
		"the hardest Gold floor 100 maze is %.2fx the difficulty of the easiest", gap))
	print(string.format("  Gold f100 per-maze difficulty: CV %.2f%%, worst/best %.2fx", 100 * cv, gap))
end

--============================================================================

print(string.format("Curve: %d passed, %d failed", passed, failed))
