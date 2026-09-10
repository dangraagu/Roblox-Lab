-- measure_curve.luau — WHERE Config.Collapse's NUMBERS CAME FROM. Run: luau measure_curve.luau 2>&1
--
-- Not a gate: tests/Curve.spec.luau is the gate. This is the tuning instrument. Re-run it before
-- moving Slack, MinSlack, TightenFloors, TightenExponent or WasteWeight, and move them to what it
-- prints rather than to a number that sounds right. Full write-up in REVIEW-3.md.
--
-- It carries its OWN copy of the closed form (pathAndWaste) and its own blind-explorer simulator,
-- and never calls VaultPath.wastedCells — so it can be used to check that file rather than only
-- to agree with it. The two matched to 1.0002 on the least-squares coefficient when this was
-- written, against a theoretical 1.0.
--
--   1. Slack     — the floor-1 value, read off a modelled completion target per tier.
--   2. the decay — TightenFloors / TightenExponent, as slack at floors 1..4000.
--   3. MinSlack  — the lowest asymptote that clears every bound in tests/Collapse.spec.luau,
--                  over the game's own 1200 floors AND a 1200-maze cap population.
--   4. the curve — modelled completion per floor, which has to come out strictly decreasing.
--   5. the jitter— how much two mazes of ONE floor differ, at WasteWeight 0 against the chosen
--                  value. This is the number that says whether the budget describes the maze.

local Config = require("./src/shared/Config")
local Progression = require("./src/shared/Progression")
local VaultFloor = require("./src/shared/VaultFloor")
local VaultPath = require("./src/shared/VaultPath")
local MazeGen = require("./src/shared/MazeGen")
local Rng = require("./src/shared/Rng")

local C = Config
local BETA = 0.25

local function stats(xs)
	table.sort(xs)
	local n = #xs
	local sum = 0
	for _, v in ipairs(xs) do sum += v end
	local mean = sum / n
	local var = 0
	for _, v in ipairs(xs) do var += (v - mean) ^ 2 end
	return { n = n, min = xs[1], max = xs[n], mean = mean, sd = math.sqrt(var / n),
		p50 = xs[math.max(1, math.ceil(0.50 * n))] }
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

local function pathAndWaste(model, s)
	local grid, cells = model.grids[s + 1], model.cells
	local from, to = model.entryCells[s + 1], model.exitCells[s + 1]
	local function id(cx, cy) return cy * cells + cx end
	local parent = { [id(from.cx, from.cy)] = false }
	local queue, head = { { from.cx, from.cy } }, 1
	while head <= #queue do
		local cur = queue[head]; head += 1
		for _, n in ipairs(openNeighbours(grid, cells, cur[1], cur[2])) do
			if parent[id(n[1], n[2])] == nil then parent[id(n[1], n[2])] = cur; queue[#queue + 1] = n end
		end
	end
	local path, onPath = {}, {}
	local cur = { to.cx, to.cy }
	while cur do path[#path + 1] = cur; onPath[id(cur[1], cur[2])] = true; cur = parent[id(cur[1], cur[2])] end
	local seen, wasted = {}, 0
	local q2, h2 = {}, 1
	local function push(c)
		for _, n in ipairs(openNeighbours(grid, cells, c[1], c[2])) do
			if not onPath[id(n[1], n[2])] and seen[id(n[1], n[2])] == nil then
				seen[id(n[1], n[2])] = true; q2[#q2 + 1] = n; wasted += 1
			end
		end
	end
	for _, c in ipairs(path) do if not (c[1] == to.cx and c[2] == to.cy) then push(c) end end
	while h2 <= #q2 do local c = q2[h2]; h2 += 1; push(c) end
	return #path - 1, wasted
end

local function lcg(seed)
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	return function(n) s = (s * 16807) % 2147483647; return 1 + (s % n) end
end

local function exploreStepsSim(model, s, rand)
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
	return steps
end

-- THE OBBY, ROLLED. The climb shaft is six pads with five studs of open air between them and
-- every pad crumbles under the runner, so hops get missed and a miss restarts the shaft. This is
-- the simulator; src/shared/VaultPath.luau prices the same process in closed form and this file
-- never reads that. (tests/Curve.spec.luau has its own copy for the same reason.)
local function climbRoll(model, rand)
	local n = math.floor(model.storeyHeight / model.stepRise)
	local hop = C.Movement.ClimbSecondsPerStep
	local pMill = math.floor(C.Ascent.ModelMissChance * 1e6 + 0.5)
	local t, k, guard = 0, 1, 0
	while k <= n do
		guard += 1
		if guard > 100000 then break end
		t += hop
		if rand(1000000) <= pMill then
			t += VaultPath.fallSeconds(C, (k - 1) * model.stepRise) + C.Ascent.ModelReapproachSeconds
			k = 1
		else
			k += 1
		end
	end
	return t
end

local function rowFor(model, floor)
	local m = VaultPath.measure(C, model)
	local shortS, wasteS = {}, {}
	for s = 0, model.storeys - 1 do
		local sh, wa = pathAndWaste(model, s)
		shortS[s + 1] = sh * m.secondsPerStep
		wasteS[s + 1] = wa * m.secondsPerStep
	end
	local fracs = {}
	for s = 0, model.storeys - 2 do
		fracs[s + 1] = VaultFloor.planeFractionAt(model, model.killLines[s + 1])
	end
	local gemD = 0
	for s = 0, model.storeys - 1 do gemD += m.gemDetour[s + 1] or 0 end
	return { floor = floor, storeys = model.storeys, climb = m.climbSeconds, perStep = m.secondsPerStep,
		climbBase = m.climbBaseSeconds, climbRetry = m.climbRetrySeconds,
		shortS = shortS, wasteS = wasteS, fracs = fracs, bfsLeave = m.leaveAt,
		bfsTotal = m.totalSeconds, gemD = gemD, model = model }
end

-- THE WALK DEMAND — the maze plus the CLEAN climbs. The slack multiplies this and only this.
local function demandOf(r, beta)
	local t, leave = 0, {}
	for s = 1, r.storeys do
		t += r.shortS[s] + beta * r.wasteS[s]
		leave[s] = t
		if s < r.storeys then t += r.climbBase end
	end
	return t, leave
end

-- ...and the budget: `walk * slack + obby`, worst constraint wins. The obby's expected cost is
-- added AT COST rather than inside the slack — see src/shared/VaultPath.luau's `demand`. Charging
-- it inside the slack measured 52.1% at Gold floor 400 against a pre-obby 49.1%: the rage obby
-- made the game easier.
local function budgetOf(r, beta, slack)
	local total, leave = demandOf(r, beta)
	local best = total * slack + (r.storeys - 1) * r.climbRetry
	for s = 1, r.storeys - 1 do
		local q = (leave[s] * slack + s * r.climbRetry) / r.fracs[s]
		if q > best then best = q end
	end
	return math.max(math.ceil(best), C.Collapse.MinSeconds)
end

-- a population of (row, explorer times) for one floor spec
local function population(tier, floor, mazes, trials, salt)
	local pop = {}
	for k = 1, mazes do
		local spec = Progression.difficulty(C, tier, floor)
		spec.seed = k * 2654435761 + salt
		local model = VaultFloor.build(C, spec, MazeGen, Rng)
		local r = rowFor(model, floor)
		local times, sum = {}, 0
		for j = 1, trials do
			local rand = lcg(k * 131 + j * 977 + salt)
			local t = 0
			for s = 0, model.storeys - 1 do
				t += exploreStepsSim(model, s, rand) * r.perStep
				-- ROLLED, not averaged. A budget that pays the expected obby cost and a runner who
				-- pays the expected obby cost cancel exactly; what the obby actually adds to a run
				-- is the TAIL, and a tail only shows up if the hops are rolled.
				if s < model.storeys - 1 then t += climbRoll(model, rand) end
			end
			times[#times + 1] = t; sum += t
		end
		pop[#pop + 1] = { row = r, times = times, mean = sum / trials }
	end
	return pop
end

local function rateAt(pop, beta, slack)
	local w, n = 0, 0
	for _, p in ipairs(pop) do
		local b = budgetOf(p.row, beta, slack)
		for _, t in ipairs(p.times) do n += 1; if t <= b then w += 1 end end
	end
	return 100 * w / n
end

--============================================================================ the schedule

local MIN_SLACK = 1.21
local function slackAt(S0, Min, K, p, f) return Min + (S0 - Min) * (1 + (f - 1) / K) ^ (-p) end

--============================================================================ 0. the shortest path at the cap

print("=========================================== 0. SHORTEST PATH AT THE 6x5 CAP, 2000 SEEDS")
print("The distribution the budget has to track. Cells " .. C.Curve.MaxCells .. ", storeys "
	.. C.Curve.MaxStoreys .. ", one cell step = " .. (2 * C.Vault.CellSize) .. " studs at WalkSpeed "
	.. C.Movement.WalkSpeed .. ".")
print("")
do
	local steps, secs, waste, need = {}, {}, {}, {}
	for k = 1, 2000 do
		local spec = Progression.difficulty(C, 3, 300)
		spec.seed = k * 2654435761 + 12345
		local model = VaultFloor.build(C, spec, MazeGen, Rng)
		local m = VaultPath.measure(C, model)
		local st, wa = 0, 0
		for s = 1, model.storeys do
			st += m.walkSteps[s]
			wa += m.wasteCells[s]
		end
		steps[#steps + 1] = st
		waste[#waste + 1] = wa
		secs[#secs + 1] = m.totalSeconds
		need[#need + 1] = select(1, VaultPath.demand(C, model, VaultFloor, C.Collapse.Slack))
	end
	local function line(label, xs)
		local t = stats(xs)
		print(string.format("  %-28s MED %6.1f  [%6.1f ..%6.1f]  sd %5.2f  CV %5.2f%%",
			label, t.p50, t.min, t.max, t.sd, 100 * t.sd / t.mean))
	end
	line("BFS cell steps (5 storeys)", steps)
	line("cells in dead-end branches", waste)
	line("optimal route seconds", secs)
	line("DEMAND seconds", need)
end

--============================================================================ 0b. the game's own floors

print("")
print("=========================================== 0b. WHAT THE GAME ACTUALLY GENERATES")
print("The real seeds, per tier. 'demand' is what the vault asks of a perfect runner.")
print("")
print("floor |  slack | Bronze cd  demand | Silver cd  demand | Gold   cd  demand")
for _, f in ipairs({ 1, 10, 30, 60, 100, 200, 400 }) do
	local row = string.format("%5d | %.4f |", f, Progression.difficulty(C, 1, f).slack)
	for tier = 1, 3 do
		local spec = Progression.difficulty(C, tier, f)
		spec.seed = Progression.seedFor(C, tier, f)
		local model = VaultFloor.build(C, spec, MazeGen, Rng)
		row = row .. string.format(" %6ds %6.1fs   |",
			VaultPath.countdown(C, model, spec.slack, VaultFloor),
			(VaultPath.demand(C, model, VaultFloor, spec.slack)))
	end
	print(row)
end

--============================================================================ 1. pick S0

print("=========================================== 1. FLOOR-1 SLACK, FROM A COMPLETION TARGET")
print("Explorer model, WalkSpeed " .. C.Movement.WalkSpeed .. " studs/s, climb "
	.. C.Movement.ClimbSecondsPerStep .. "s per tread. beta = " .. BETA .. ".")
print("400 mazes x 20 trials per tier at floor 1.")
print("")
local popF1 = {}
for tier = 1, 3 do popF1[tier] = population(tier, 1, 400, 20, 11 * tier) end
for _, S0 in ipairs({ 1.95, 1.90, 1.85, 1.80, 1.75, 1.70, 1.65, 1.60 }) do
	print(string.format("  S0 %.2f -> floor 1 completion: Bronze %3.0f%%  Silver %3.0f%%  Gold %3.0f%%",
		S0, rateAt(popF1[1], BETA, S0), rateAt(popF1[2], BETA, S0), rateAt(popF1[3], BETA, S0)))
end

--============================================================================ 2. pick the decay shape

print("")
print("=========================================== 2. DECAY SHAPE")
print("slack(f) = Min + (S0-Min) * (1 + (f-1)/K)^-p, with Min " .. MIN_SLACK)
print("")
local S0 = 1.85
for _, cand in ipairs({ { 25, 0.50 }, { 40, 0.50 }, { 25, 0.75 }, { 40, 0.75 }, { 60, 1.00 }, { 25, 1.00 } }) do
	local K, p = cand[1], cand[2]
	local line = string.format("  K %3d p %.2f | ", K, p)
	for _, f in ipairs({ 1, 10, 30, 60, 100, 200, 400, 1000, 4000 }) do
		line = line .. string.format("f%-4d %.3f  ", f, slackAt(S0, MIN_SLACK, K, p, f))
	end
	print(line)
end

--============================================================================ 3. verify the bounds

print("")
print("=========================================== 3. BOUNDS, 3 TIERS x 400 FLOORS + 1200 CAP MAZES")
print("tests/Collapse.spec.luau needs storey air >= 4s, escape spare >= 8s, gem spare >= 2s;")
print("Config needs the budget inside [" .. C.Collapse.MinSeconds .. ", " .. C.Collapse.MaxSeconds .. "]s.")
print("")
local gameRows, capRows = {}, {}
for tier = 1, 3 do
	for floor = 1, 400 do
		local spec = Progression.difficulty(C, tier, floor)
		spec.seed = Progression.seedFor(C, tier, floor)
		gameRows[#gameRows + 1] = rowFor(VaultFloor.build(C, spec, MazeGen, Rng), floor)
	end
end
for k = 1, 1200 do
	local spec = Progression.difficulty(C, 3, 300)
	spec.seed = k * 2654435761 + 555
	capRows[#capRows + 1] = rowFor(VaultFloor.build(C, spec, MazeGen, Rng), 400)
end

local function checkSchedule(S0v, Min, K, p)
	local wS, wE, wG, lo, hi = math.huge, math.huge, math.huge, math.huge, 0
	local sAt, eAt, gAt, hAt = "", "", "", ""
	local function run(list, forced, tag)
		for i, r in ipairs(list) do
			local slack = forced or slackAt(S0v, Min, K, p, r.floor)
			local b = budgetOf(r, BETA, slack)
			for s = 1, r.storeys - 1 do
				-- ...minus the falls back onto this storey and every one below it.
				local margin = r.fracs[s] * b - (r.bfsLeave[s] + s * r.climbRetry)
				if margin < wS then wS = margin; sAt = tag .. " #" .. i .. " f" .. r.floor .. " storey " .. (s - 1) end
			end
			local e = b - r.bfsTotal
			if e < wE then wE = e; eAt = tag .. " #" .. i .. " f" .. r.floor end
			if e - r.gemD < wG then wG = e - r.gemD; gAt = tag .. " #" .. i .. " f" .. r.floor end
			if b < lo then lo = b end
			if b > hi then hi = b; hAt = tag .. " #" .. i .. " f" .. r.floor end
		end
	end
	run(gameRows, nil, "game")
	run(capRows, Min, "cap")
	return wS, wE, wG, lo, hi, sAt, eAt, gAt, hAt
end

for _, cand in ipairs({ { 1.85, 25, 0.50 }, { 1.85, 25, 0.75 }, { 1.85, 25, 1.00 }, { 1.85, 40, 0.75 } }) do
	local s0, K, p = cand[1], cand[2], cand[3]
	local wS, wE, wG, lo, hi, sAt, _, gAt, hAt = checkSchedule(s0, MIN_SLACK, K, p)
	print(string.format("  S0 %.2f K %d p %.2f | storey %5.1fs (%s) | escape %5.1fs | gem %5.1fs (%s) | budget %3.0f..%-3.0fs (%s)  %s",
		s0, K, p, wS, sAt, wE, wG, gAt, lo, hi, hAt,
		(wS >= 4 and wE >= 8 and wG >= 2 and lo >= C.Collapse.MinSeconds and hi <= C.Collapse.MaxSeconds)
			and "OK" or "VIOLATES"))
end

--============================================================================ 4. the monotonicity table

print("")
print("=========================================== 4. MONOTONICITY — MEASURED SUCCESS MARGIN PER FLOOR")
print("Gold. 300 mazes x 20 explorer trials per floor = 6000 modelled runs each.")
print("")
local CHOSEN = { S0 = 1.85, Min = MIN_SLACK, K = 25, p = 0.75 }
local pops = {}
for _, f in ipairs({ 1, 10, 30, 60, 100, 200, 400, 1000 }) do pops[f] = population(3, f, 300, 20, 7 * f) end
for _, shape in ipairs({ { 25, 0.50 }, { 25, 0.75 }, { 25, 1.00 }, { 40, 0.75 } }) do
	print(string.format("-- K %d p %.2f", shape[1], shape[2]))
	print("floor | slack | completion | median budget/explorer-time margin")
	local prevRate, mono = math.huge, true
	for _, f in ipairs({ 1, 10, 30, 60, 100, 200, 400, 1000 }) do
		local slack = slackAt(CHOSEN.S0, CHOSEN.Min, shape[1], shape[2], f)
		local rate = rateAt(pops[f], BETA, slack)
		local margins = {}
		for _, pp in ipairs(pops[f]) do
			local b = budgetOf(pp.row, BETA, slack)
			for _, t in ipairs(pp.times) do margins[#margins + 1] = b / t end
		end
		if rate > prevRate + 1e-9 then mono = false end
		prevRate = rate
		print(string.format("%5d | %.3f | %9.1f%% | %.3f", f, slack, rate, stats(margins).p50))
	end
	print(mono and "  monotone: yes" or "  monotone: NO")
	print("")
end

--============================================================================ 5. jitter, before and after

print("")
print("=========================================== 5. JITTER WITHIN A SINGLE FLOOR")
print("Gold floor 100, 400 mazes x 20 trials. 'cost' = explorer seconds / that maze's demand.")
print("A wider spread means two mazes of the SAME floor are different difficulties.")
print("")
do
	local pop = population(3, 100, 400, 20, 4242)
	for _, beta in ipairs({ 0.00, 0.25 }) do
		local costs = {}
		for _, p in ipairs(pop) do costs[#costs + 1] = p.mean / (demandOf(p.row, beta)) end
		local s = stats(costs)
		local budgets = {}
		local slack = slackAt(CHOSEN.S0, CHOSEN.Min, CHOSEN.K, CHOSEN.p, 100)
		for _, p in ipairs(pop) do budgets[#budgets + 1] = budgetOf(p.row, beta, slack) end
		local sb = stats(budgets)
		print(string.format("beta %.2f (%s): per-maze cost MED %.3f  [%.3f..%.3f]  sd %.4f  CV %5.2f%%  worst/best %.2fx"
			.. "   | budget %.0f..%.0fs CV %.1f%%",
			beta, beta == 0 and "shipped, shortest path" or "chosen",
			s.p50, s.min, s.max, s.sd, 100 * s.sd / s.mean, s.max / s.min,
			sb.min, sb.max, 100 * sb.sd / sb.mean))
	end
end

--============================================================================ 6. the obby

print("")
print("=========================================== 6. THE OBBY, AND WHAT ITS ONE ASSUMPTION COSTS")
print("The shaft's geometry is measured (tests/VaultFloor.spec.luau `climbIsFailable`); the rate at")
print("which a player MISSES one of its hops is not, because nobody has played this game. So this")
print("sweeps Config.Ascent.ModelMissChance and reports what each value does to the whole curve.")
print("Budget and runner move together: the countdown prices the obby at the same p the explorer")
print("rolls it at, which is what the shipped game does.")
print("")
print("The pre-obby column is what REVIEW-3 measured with a staircase in place of the shaft:")
print("  f1 98.1  f10 95.4  f30 87.8  f60 76.8  f100 68.8  f200 58.5  f400 49.1")
print("")

local OBBY_FLOORS = { 1, 10, 30, 60, 100, 200, 400 }
local shipped = C.Ascent.ModelMissChance
print("    p | climb  falls/ | worst | " .. string.format("%5s %5s %5s %5s %5s %5s %5s | mono",
	"f1", "f10", "f30", "f60", "f100", "f200", "f400"))
print("      |  (s)   storey |  cd   |")
for _, pm in ipairs({ 0.00, 0.02, 0.04, 0.06, 0.08, 0.12 }) do
	C.Ascent.ModelMissChance = pm

	-- what one storey transition now costs, and how often it is fallen
	local spec1 = Progression.difficulty(C, 3, 1)
	spec1.seed = Progression.seedFor(C, 3, 1)
	local m1 = VaultFloor.build(C, spec1, MazeGen, Rng)
	local _, falls = VaultPath.climbAttempts(C, m1)
	local climb = VaultPath.climbSeconds(C, m1)

	-- the pacing promise: nothing the game generates may pass Config.Collapse.MaxSeconds
	local worst = 0
	for tier = 1, #C.Tiers do
		for f = 1, 200 do
			local sp = Progression.difficulty(C, tier, f)
			sp.seed = Progression.seedFor(C, tier, f)
			local mm = VaultFloor.build(C, sp, MazeGen, Rng)
			worst = math.max(worst, VaultPath.countdown(C, mm, sp.slack, VaultFloor))
		end
	end

	local cells, prev, mono = {}, math.huge, true
	for _, f in ipairs(OBBY_FLOORS) do
		local pop = population(3, f, 120, 12, 7 * f)
		local rate = rateAt(pop, BETA, slackAt(CHOSEN.S0, CHOSEN.Min, CHOSEN.K, CHOSEN.p, f))
		if rate > prev + 1e-9 then mono = false end
		prev = rate
		cells[#cells + 1] = string.format("%5.1f", rate)
	end
	print(string.format(" %.2f%s | %5.2f  %5.2f  | %4ds | %s | %s",
		pm, pm == shipped and "*" or " ", climb, falls, worst,
		table.concat(cells, " "), mono and "yes" or "NO"))
end
C.Ascent.ModelMissChance = shipped
print("")
print("* = shipped. MaxSeconds is " .. C.Collapse.MaxSeconds .. "s; a worst-cd above it is a BLOCK.")

print("")
print("done")
