-- readcost.measure.luau — WHAT MUST READING COST?
--
-- Run: luau tests/readcost.measure.luau
--
-- This is a measurement, not an assertion. It exists because Config.Fork.ReadSeconds is a number
-- somebody has to choose, and choosing it by taste is how a game ends up with a mechanic nobody
-- uses (free) or one everybody skips (expensive). REVIEW-2's headline finding was that the whole
-- inscription mechanic was dominated: the star count was printed on every door, so the best way to
-- play was to never read anything. Hiding the stars fixes WHO has the information. This file fixes
-- WHAT IT COSTS to get it.
--
-- ── THE TRADE, stated so it can be measured ──────────────────────────────────
--
-- With the trait and its power hidden until the inscription is read, a player has exactly two
-- strategies that need no outside knowledge:
--
--   READ  — pay ReadSeconds on every fork, learn which door is the trap AND what each door gives,
--           then take the safe one. Zero penalty sections.
--   GUESS — pay nothing, pick a door by a coin. The trap side is a fair coin (Fork.luau keeps it
--           that way on purpose), so half the floors build the penalty section.
--
-- The trap's only cost is TIME — a penalty section is PenaltyExtraPlatforms longer and
-- PenaltyExtraHazards busier, never steeper (Section.luau). So the read has to be priced in the
-- same currency, and the price that makes this a real decision rather than a formality is the one
-- where the two strategies finish a ten-floor run in about the same wall clock.
--
-- ── THE TIME MODEL, and every assumption in it ───────────────────────────────
--
-- 1. A section is crossed platform by platform. Roblox keeps a character's horizontal velocity
--    while it is airborne, so the ground speed governs and a hop between two platform CENTRES
--    costs (TileSize + gap) / WalkSpeed seconds. `gap` is the level's own gap from Section.shape.
-- 2. A section of `count` platforms costs `count` hops: the fork pad onto platform 1, then
--    count - 1 hops up. Identical in shape for both strategies, so the fork pad, the doors and the
--    walk to the next fork all cancel and are left out.
-- 3. WalkSpeed is the speed the player ACTUALLY HAS on that floor — Config.WalkSpeed plus the
--    speed of every trait taken so far, clamped upward exactly as the server's traitTotals does.
--    The two strategies collect different traits, so they climb at different speeds, and using the
--    traitless 16 for both would have overstated the break-even by about a third (it is reported
--    below as the upper bound it is).
-- 4. A hazard hit costs one hop: hitting it returns the player to that platform's own clear band,
--    and the checkpoint has already moved up with them. `HIT_RATE` is how often a player actually
--    walks into one. It is the one number here that is not derived from anything, so the answer is
--    reported across the whole range 0 .. 1 and the shipping number is taken from HIT_RATE = 0 —
--    the perfect climber, who gets the SMALLEST justified read cost.
-- 5. Jump height does not enter: every rise is clearable by construction (Section.spec) and the
--    airborne time is already paid for by the horizontal speed above.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Fork = require("../src/shared/Fork")
local Section = require("../src/shared/Section")

local SEEDS = 5000
local FLOORS = Config.Tower.Floors

local traitById = {}
for _, t in ipairs(Config.Traits) do
	traitById[t.id] = t
end

-- The server's traitTotals, speed half only.
local function speedAfter(picks: { string }): number
	local speed = Config.WalkSpeed
	for _, id in ipairs(picks) do
		local t = traitById[id]
		if t then
			speed += t.speed or 0
		end
	end
	return math.max(speed, Config.WalkSpeed)
end

local function reachAt(level: number): number
	local _, gap = Section.shape(Config, level, false)
	return Config.Tower.TileSize + gap
end

-- Seconds spent inside one floor's section.
local function sectionSeconds(level: number, penalty: boolean, speed: number, hitRate: number): number
	local _, _, count, hazards = Section.shape(Config, level, penalty)
	return (count + hazards * hitRate) * reachAt(level) / speed
end

-- One run, one strategy. `pick(floor)` returns the slot the strategy takes.
local function play(plan, pick, hitRate: number, fixedSpeed: number?)
	local picks, seconds, score, traps = {}, 0, 0, 0
	for level = 1, FLOORS do
		local floor = plan.floors[level]
		local slot = pick(floor, level)
		local door = floor.doors[slot]
		picks[#picks + 1] = door.traitId
		local trait = traitById[door.traitId]
		score += (trait and trait.power or 0)
		local penalty = Fork.isTrap(floor, slot)
		if penalty then
			traps += 1
		end
		seconds += sectionSeconds(level, penalty, fixedSpeed or speedAfter(picks), hitRate)
	end
	return seconds, score, traps
end

local function safeSlot(floor)
	return 3 - floor.trapDoor
end
local function strongSlot(floor)
	local p1 = traitById[floor.doors[1].traitId].power
	local p2 = traitById[floor.doors[2].traitId].power
	return if p1 >= p2 then 1 else 2
end

--============================================================================ the sweep

local function sweep(hitRate: number, fixedSpeed: number?)
	local readerT, guesserT, greedyT = 0, 0, 0
	local readerS, guesserS, greedyS = 0, 0, 0
	local guesserTraps, greedyTraps = 0, 0
	for seed = 1, SEEDS do
		local plan = Fork.plan(Config, seed, Rng)
		-- The guesser's coin is its own stream, seeded off the run seed so the sweep is
		-- reproducible and never borrows Fork's own randomness.
		local coin = Rng.new(seed * 7919 + 13)
		local rt, rs = play(plan, safeSlot, hitRate, fixedSpeed)
		local gt, gs, gtr = play(plan, function()
			return if coin:next() < 0.5 then 1 else 2
		end, hitRate, fixedSpeed)
		local xt, xs, xtr = play(plan, strongSlot, hitRate, fixedSpeed)
		readerT += rt; readerS += rs
		guesserT += gt; guesserS += gs; guesserTraps += gtr
		greedyT += xt; greedyS += xs; greedyTraps += xtr
	end
	return {
		readerT = readerT / SEEDS, guesserT = guesserT / SEEDS, greedyT = greedyT / SEEDS,
		readerS = readerS / SEEDS, guesserS = guesserS / SEEDS, greedyS = greedyS / SEEDS,
		guesserTraps = guesserTraps / SEEDS, greedyTraps = greedyTraps / SEEDS,
	}
end

print(string.format("Fork Tower — what must a read cost?  (%d run seeds x %d floors)", SEEDS, FLOORS))
print("")
print("  hit rate | reader s | guesser s | guesser extra s | break-even read s")
print("  ---------+----------+-----------+-----------------+------------------")
for _, hitRate in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
	local r = sweep(hitRate)
	local extra = r.guesserT - r.readerT
	local breakEven = extra / FLOORS
	print(string.format("     %.2f  |  %7.2f |   %7.2f |         %7.2f |            %.3f",
		hitRate, r.readerT, r.guesserT, extra, breakEven))
end
print("")

-- The upper bound: the same question asked of a player whose speed never grows. Reported because
-- it is the number a traitless-baseline reading of the config would give, and it is 30-odd per
-- cent too generous.
do
	local r = sweep(0, Config.WalkSpeed)
	print(string.format("  traitless upper bound (WalkSpeed fixed at %d, hit rate 0): break-even %.3f s",
		Config.WalkSpeed, (r.guesserT - r.readerT) / FLOORS))
end
print("")

--============================================================================ the shipping number

local SHIPPING = Config.Fork.ReadSeconds
print(string.format("  Config.Fork.ReadSeconds = %.2f s", SHIPPING))
print("")
for _, hitRate in ipairs({ 0, 0.5 }) do
	local r = sweep(hitRate)
	local readTotal = r.readerT + SHIPPING * FLOORS
	print(string.format("  hit rate %.2f: READ %.2f s (%.2f climbing + %.2f reading), GUESS %.2f s -> read is %+.1f%%",
		hitRate, readTotal, r.readerT, SHIPPING * FLOORS, r.guesserT,
		100 * (readTotal - r.guesserT) / r.guesserT))
end
print("")

-- Per seed, not just on the mean: a number that balances two averages can still lose on nine
-- runs out of ten.
do
	local readerWins, guesserWins, ties, worstReader, worstGuesser = 0, 0, 0, 0, 0
	local trapHist = {}
	for seed = 1, SEEDS do
		local plan = Fork.plan(Config, seed, Rng)
		local coin = Rng.new(seed * 7919 + 13)
		local rt = play(plan, safeSlot, 0) + SHIPPING * FLOORS
		local gt, _, gtr = play(plan, function()
			return if coin:next() < 0.5 then 1 else 2
		end, 0)
		trapHist[gtr] = (trapHist[gtr] or 0) + 1
		local d = 100 * (rt - gt) / gt
		if d > worstReader then worstReader = d end
		if -d > worstGuesser then worstGuesser = -d end
		if math.abs(d) < 1e-9 then ties += 1 elseif d < 0 then readerWins += 1 else guesserWins += 1 end
	end
	print(string.format("  per seed at %.2f s: READ faster on %d, GUESS faster on %d, tied %d (of %d)",
		SHIPPING, readerWins, guesserWins, ties, SEEDS))
	print(string.format("  worst case for a reader %+.1f%%, worst case for a guesser %+.1f%%",
		worstReader, -worstGuesser))
	local parts = {}
	for n = 0, FLOORS do
		if trapHist[n] then parts[#parts + 1] = string.format("%d:%d", n, trapHist[n]) end
	end
	print("  traps a guesser ate, by count: " .. table.concat(parts, " "))
end
print("")

do
	local r = sweep(0)
	print(string.format("  score: READ-safe %.2f, GUESS %.2f, READ-greedy %.2f", r.readerS, r.guesserS, r.greedyS))
	print(string.format("  traps eaten: READ 0.00, GUESS %.2f, READ-greedy %.2f of %d floors",
		r.guesserTraps, r.greedyTraps, FLOORS))
	local greedyTotal = r.greedyT + SHIPPING * FLOORS
	print(string.format("  READ-greedy total %.2f s vs GUESS %.2f s -> %+.1f%%",
		greedyTotal, r.guesserT, 100 * (greedyTotal - r.guesserT) / r.guesserT))
end
