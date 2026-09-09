-- Collapse — IS THE VAULT WINNABLE AT ALL? Run: luau tests/Collapse.spec.luau
--
-- This is the spec the game shipped without, and the one that made Silver and Gold unwinnable.
--
-- Vault Runners is a footrace against a rising kill plane. Every other spec in this repo checks
-- that the maze is well formed, that the gems bank correctly, that the wall merge covers every
-- cell — and not one of them ever asked how LONG the maze takes to walk. The countdown was three
-- typed-in numbers (70 / 80 / 90) and the plane's speed was (vault height) / (countdown), so
-- every storey added made the plane rise FASTER through the lower ones. An adversarial review
-- walked the BFS-optimal route at WalkSpeed 16 with the climb costed at ZERO seconds and died on
-- storey 0 of Silver at 13.7 seconds of 80. 1200 banked gems bought a vault nobody could clear.
--
-- So this file does not check a constant. It SIMULATES the best possible runner:
--
--   * the route is BFS through the maze that was actually generated, entry cell to stair cell,
--     storey by storey — the shortest walk that exists in that vault;
--   * they move at Config.Movement.WalkSpeed and never hesitate, never backtrack, never miss;
--   * the collapse underneath them is RunState.planeY over the model VaultFloor.build returned,
--     and the kill test is RunState.caught — the same function the server calls;
--   * they must survive every storey AND escape with real seconds left over, at every tier and
--     across a spread of floors.
--
-- The runner in here is strictly better than any human: a human cannot see the maze from above.
-- So the margins asserted below are a CEILING on how good the game feels, not a floor. If this
-- spec is tight, the real game is unplayable.
--
-- The two thresholds are absolute SECONDS on purpose. The countdown is derived by multiplying
-- the measured route by Config.Collapse.Slack, and a spec that re-asserted that multiplication
-- would only be checking that multiplication still multiplies. Seconds are a different yardstick.

local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local VaultFloor = require("../src/shared/VaultFloor")
local VaultPath = require("../src/shared/VaultPath")
local RunState = require("../src/shared/RunState")
local MazeGen = require("../src/shared/MazeGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local C = Config

-- Seconds the BFS-optimal runner must have left when they touch the exit pad. Below this the
-- vault is a stopwatch, not a game: nobody who reads a corridor before entering it clears it.
local MIN_ESCAPE_SLACK = 8
-- ...and seconds to spare over the plane at every storey's kill line on the way up. A run that
-- dies on storey 0 with 60 seconds still on the clock is the exact defect this file exists for.
local MIN_STOREY_SLACK = 4
-- The player has to be able to pick something up or the run banks nothing. One gem per storey is
-- the floor of the floor — the real game asks for most of them.
local MIN_GEM_SLACK = 2

-- Floors chosen to straddle every step of Config.Curve: 6 adds a cell, 10 adds a storey, 5 adds
-- gems, and the collapse tightens every floor until it bottoms out. 40 is well past every cap,
-- so it is the hardest floor the game can generate.
local FLOORS = { 1, 2, 6, 7, 10, 11, 16, 21, 31, 40 }

-- The exact order the server uses: build the vault, THEN measure it for a countdown. Doing it
-- the other way round is the whole defect — a countdown decided before the maze exists cannot
-- know how big the maze is.
local function buildFloor(tier, floor)
	local spec = Progression.difficulty(C, tier, floor)
	spec.seed = Progression.seedFor(C, tier, floor)
	local model = VaultFloor.build(C, spec, MazeGen, Rng)
	spec.collapseSeconds = VaultPath.countdown(C, model, spec.slack, VaultFloor)
	return model, spec
end

--============================================================================ the simulation

-- Walk the optimal route and report, per storey, how much clear air the runner had over the
-- collapse when they left it — and how many seconds were left on the clock when they escaped.
--
-- Height is modelled the way the vault is built: standing on storey s puts the root at
-- s * storeyHeight + RunnerRootHeight, and the climb lifts it linearly to the next one. The kill
-- test is RunState.caught, so this simulation and the live server cannot disagree about what
-- "the collapse got you" means.
local function simulate(model, spec)
	local run = RunState.start(C, spec, 0)
	local m = VaultPath.measure(C, model)
	local dt = C.Run.TickSeconds

	local worstStorey, worstMargin = nil, math.huge
	local diedAt, diedOn = nil, nil

	for s = 0, model.storeys - 1 do
		local standing = s * model.storeyHeight + C.Run.RunnerRootHeight
		-- ...tick through the walk across this storey, so a plane that catches the runner
		-- mid-corridor is caught here and not just at the end of the leg.
		local t = m.arriveAt[s + 1]
		while t < m.leaveAt[s + 1] and diedAt == nil do
			t = math.min(t + dt, m.leaveAt[s + 1])
			if RunState.caught(run, model, standing, t) then diedAt, diedOn = t, s end
		end
		if diedAt ~= nil then break end

		-- How far under the runner's kill line the plane still was as they reached the stair.
		local left = m.leaveAt[s + 1]
		local margin = (model.killLines[s + 1] - RunState.planeY(run, model, left))
			/ math.max(1e-9, (model.killPlane.endY - model.killPlane.startY) / run.collapseSeconds)
		if margin < worstMargin then worstMargin, worstStorey = margin, s end

		if s < model.storeys - 1 then
			-- The climb. The runner rises 18 studs in ~5 seconds against a plane doing well under
			-- one stud a second, so this leg is not where anybody dies — but it is ticked anyway
			-- rather than assumed, because "not where anybody dies" is a claim about numbers that
			-- have all just changed.
			local from, to = m.leaveAt[s + 1], m.leaveAt[s + 1] + m.climbSeconds
			local t2 = from
			while t2 < to and diedAt == nil do
				t2 = math.min(t2 + dt, to)
				local frac = (t2 - from) / math.max(1e-9, to - from)
				if RunState.caught(run, model, standing + frac * model.storeyHeight, t2) then
					diedAt, diedOn = t2, s
				end
			end
			if diedAt ~= nil then break end
		end
	end

	return {
		died = diedAt ~= nil, diedAt = diedAt, diedOn = diedOn,
		escapeAt = m.totalSeconds,
		escapeSlack = run.collapseSeconds - m.totalSeconds,
		worstStorey = worstStorey, worstStoreySlack = worstMargin,
		countdown = run.collapseSeconds,
		measure = m,
	}
end

--============================================================================ every tier, every floor

for tier = 1, #C.Tiers do
	local name = C.Tiers[tier].name
	for _, floor in ipairs(FLOORS) do
		local model, spec = buildFloor(tier, floor)
		local r = simulate(model, spec)
		local where = string.format("%s floor %d", name, floor)

		ok(not r.died, string.format(
			"%s: the BFS-optimal runner is caught on storey %s at %.1fs of %.1fs — the vault is UNWINNABLE",
			where, tostring(r.diedOn), r.diedAt or -1, r.countdown))

		if not r.died then
			ok(r.escapeSlack >= MIN_ESCAPE_SLACK, string.format(
				"%s: optimal escape at %.1fs of %.1fs leaves %.1fs, under the %ds a real player needs",
				where, r.escapeAt, r.countdown, r.escapeSlack, MIN_ESCAPE_SLACK))
			ok(r.worstStoreySlack >= MIN_STOREY_SLACK, string.format(
				"%s: only %.1fs of clear air over the collapse leaving storey %s, under %ds",
				where, r.worstStoreySlack, tostring(r.worstStorey), MIN_STOREY_SLACK))

			-- ...and the run has to be worth making. A vault you can only cross empty-handed
			-- banks nothing, and banking is the entire economy.
			local detour = 0
			for s = 0, model.storeys - 1 do
				local d = r.measure.gemDetour[s + 1]
				ok(d ~= nil, string.format("%s: storey %d has a reachable gem at all", where, s))
				detour += d or 0
			end
			ok(r.escapeSlack - detour >= MIN_GEM_SLACK, string.format(
				"%s: one gem per storey costs %.1fs of the %.1fs spare — nothing left to bank with",
				where, detour, r.escapeSlack))
		end
	end
end

--============================================================================ pacing

-- A countdown that is CORRECT can still be unplayable. The derivation will happily hand out
-- fourteen minutes for a 8x8x7 vault, all of it lost on one death — which is what the old
-- Config.Curve caps (MaxCells 8, MaxStoreys 7) would have produced once the countdown started
-- tracking the maze. Nothing clamps the countdown, because clamping is how it became unwinnable
-- in the first place; the CAPS are what hold this down, and this is the assertion that holds
-- the caps. Every floor, not a sample: the maze is random, so a floor nobody thought to check is
-- exactly where the outlier lives.
-- ...and while every one of those floors is being built anyway, check the DEADLINES on all of
-- them. The ten floors sampled above get a full tick-by-tick simulation; these 360 get the same
-- inequality without the ticking, which is what actually decides it:
--
--     leaveAt(s) + MIN_STOREY_SLACK  <=  frac(s) * countdown
--
-- Sampling is not enough here and this is not theory. The per-storey half of the derivation only
-- BINDS on a lopsided vault — one whose ground floor happens to generate a much longer route
-- than the storeys above it. Deleting that half of VaultPath.countdown outright left all ten
-- sampled floors green, because on a maze with even storeys the total-route constraint dominates
-- and hides it. The mazes are random; the floor where the ground storey is the long one is not a
-- floor anybody would have thought to sample.
do
	local worst, worstAt, shortest, shortAt = 0, "", math.huge, ""
	local tightest, tightestAt = math.huge, ""
	local tightestExit, tightestExitAt = math.huge, ""
	for tier = 1, #C.Tiers do
		for floor = 1, 200 do
			local model, spec = buildFloor(tier, floor)
			local t = spec.collapseSeconds
			if t > worst then worst, worstAt = t, C.Tiers[tier].name .. " floor " .. floor end
			if t < shortest then shortest, shortAt = t, C.Tiers[tier].name .. " floor " .. floor end

			local m = VaultPath.measure(C, model)
			for s = 0, model.storeys - 2 do
				local deadline = VaultFloor.planeFractionAt(model, model.killLines[s + 1]) * t
				local margin = deadline - m.leaveAt[s + 1]
				if margin < tightest then
					tightest = margin
					tightestAt = string.format("%s floor %d, storey %d (route %.1fs, deadline %.1fs of %ds)",
						C.Tiers[tier].name, floor, s, m.leaveAt[s + 1], deadline, t)
				end
			end
			local exitMargin = t - m.totalSeconds
			if exitMargin < tightestExit then
				tightestExit = exitMargin
				tightestExitAt = string.format("%s floor %d (route %.1fs of %ds)",
					C.Tiers[tier].name, floor, m.totalSeconds, t)
			end
		end
	end
	ok(worst <= C.Collapse.MaxSeconds, string.format(
		"the longest run the game can generate is %ds (%s), over the %ds a player will sit through",
		worst, worstAt, C.Collapse.MaxSeconds))
	ok(shortest >= C.Collapse.MinSeconds, string.format(
		"the shortest is %ds (%s), under the %ds floor", shortest, shortAt, C.Collapse.MinSeconds))
	ok(tightest >= MIN_STOREY_SLACK, string.format(
		"the tightest storey in the whole game leaves %.1fs over the collapse, under %ds — %s",
		tightest, MIN_STOREY_SLACK, tightestAt))
	ok(tightestExit >= MIN_ESCAPE_SLACK, string.format(
		"the tightest escape in the whole game leaves %.1fs, under %ds — %s",
		tightestExit, MIN_ESCAPE_SLACK, tightestExitAt))
	print(string.format("  3 tiers x 200 floors: countdown %ds..%ds  tightest storey +%.1fs  tightest escape +%.1fs",
		shortest, worst, tightest, tightestExit))
end

--============================================================================ the model itself

-- The defect in one assertion. Under the old model the plane's speed was (height)/(countdown)
-- with a hand-typed countdown, so a taller vault swept its LOWER storeys faster and the deadline
-- for storey 0 arrived EARLIER the bigger the maze got. Whatever the numbers are, that must
-- never be true again: more storeys can only ever mean more time down at the bottom.
--
-- The tolerance is ONE SECOND because VaultPath.countdown rounds the countdown up to a whole
-- second, and storey 0's deadline is a fraction of it — so the deadline can wobble by up to
-- frac(0) * 1s between two vaults that are otherwise identically paced. It is the quantisation,
-- not slack in the assertion: the model this replaces dropped 16.7s -> 12.0s -> 9.4s -> 7.7s ->
-- 6.5s across these same five vaults, and every one of those steps is bigger than a second.
local QUANTISATION = 1.0
do
	local prev = nil
	for _, storeys in ipairs({ 3, 4, 5, 6, 7 }) do
		local spec = Progression.difficulty(C, 1, 1)
		spec.seed = Progression.seedFor(C, 1, 1)
		spec.storeys = storeys
		local model = VaultFloor.build(C, spec, MazeGen, Rng)
		spec.collapseSeconds = VaultPath.countdown(C, model, spec.slack, VaultFloor)
		local run = RunState.start(C, spec, 0)
		-- When does the collapse reach a runner standing on storey 0?
		local frac = VaultFloor.planeFractionAt(model, model.killLines[1])
		local deadline = frac * run.collapseSeconds
		if prev ~= nil then
			ok(deadline >= prev - QUANTISATION, string.format(
				"a %d-storey vault gives storey 0 %.1fs, LESS than the %d-storey vault's %.1fs — "
					.. "adding storeys must never shorten the deadline underneath them",
				storeys, deadline, storeys - 1, prev))
		end
		prev = deadline
	end
end

-- ...and the same for the tiers as configured, which is where a player actually meets it.
do
	local prev, prevName = nil, nil
	for tier = 1, #C.Tiers do
		local model, spec = buildFloor(tier, 1)
		local run = RunState.start(C, spec, 0)
		local deadline = VaultFloor.planeFractionAt(model, model.killLines[1]) * run.collapseSeconds
		if prev ~= nil then
			ok(deadline >= prev - QUANTISATION, string.format(
				"%s gives storey 0 %.1fs, less than %s's %.1fs — the tiers are inverted",
				C.Tiers[tier].name, deadline, prevName, prev))
		end
		prev, prevName = deadline, C.Tiers[tier].name
	end
end

--============================================================================ the route measurement

do
	local model = buildFloor(1, 1)
	local m = VaultPath.measure(C, model)

	-- One cell step crosses TWO fine cells. Halving this is the single easiest way to make every
	-- vault in the game look twice as winnable as it is.
	eq(VaultPath.studsPerStep(model), 2 * model.cellSize, "one maze step is two fine cells of walking")
	eq(m.secondsPerStep, 2 * model.cellSize / C.Movement.WalkSpeed, "...at the configured walk speed")
	eq(m.climbSeconds, 6 * C.Movement.ClimbSecondsPerStep, "a storey is six jumped steps")

	-- The route must actually be a route: monotonic, and every storey's walk non-zero (the entry
	-- and exit cells are opposite corners, so a zero-length leg means BFS found nothing).
	local mono = true
	for s = 0, model.storeys - 1 do
		if m.leaveAt[s + 1] <= m.arriveAt[s + 1] then mono = false end
		if s > 0 and m.arriveAt[s + 1] <= m.leaveAt[s] then mono = false end
	end
	ok(mono, "the timeline moves forward: arrive, walk, climb, arrive again")
	eq(m.totalSeconds, m.leaveAt[model.storeys], "the escape IS the last storey's walk finishing")

	-- BFS, not "the number of cells". A 4x4 maze's opposite corners are at least 6 steps apart
	-- (the Manhattan distance) and at most every cell in it.
	for s = 0, model.storeys - 1 do
		ok(m.walkSteps[s + 1] >= 2 * (model.cells - 1),
			string.format("storey %d's route is at least the Manhattan distance", s))
		ok(m.walkSteps[s + 1] <= model.cells * model.cells,
			string.format("storey %d's route does not revisit cells", s))
	end
end

--============================================================================ report

do
	print("")
	for tier = 1, #C.Tiers do
		for _, floor in ipairs({ 1, 10, 40 }) do
			local model, spec = buildFloor(tier, floor)
			local r = simulate(model, spec)
			print(string.format(
				"  %-13s f%-3d %dx%d x%d storeys  countdown %5.1fs  optimal %5.1fs  spare %5.1fs  worst storey %s +%.1fs%s",
				C.Tiers[tier].name, floor, model.cells, model.cells, model.storeys,
				r.countdown, r.escapeAt, r.escapeSlack, tostring(r.worstStorey), r.worstStoreySlack,
				r.died and "  DIED" or ""))
		end
	end
	print("")
end

print(string.format("Collapse: %d passed, %d failed", passed, failed))
if failed > 0 then error("Collapse spec failed", 0) end
