-- Pacing.spec.luau - how long a session takes to reach each milestone, measured in Luau on the game's own rules.
-- Run from the game directory: luau tests/Pacing.spec.luau
--
-- docs/complete-game-standard.md section 2: "A brag moment within about 30-45 minutes of normal play, and a
-- long-term goal beyond it. Measure the minutes with a pacing model in tests/." DESIGN.md section 4's minutes came
-- from Python models (econ.py, tune.py, success.py) that are gone; this file replaces them.
--
-- THE BRAG MOMENT is the first Mythic: Bigfoot in your lair, and Mythic Night over Pine Hollow (the gold aurora,
-- UFOs over the ridge, Bigfoot walking the horizon; EYECANDY.md section 2). It is the top of the Journal's rank, the
-- top camp tier and the deepest band of the night, the way space is the top of +1 Jump. THE LONG-TERM GOAL beyond
-- it is the full lair: nine cages, nine Mythics (and the Top Lairs board ranks the best lair income). On the way
-- there the night's fifth band, the gathering, comes when the best lair income reaches Config.Night.GatheringRate.
--
-- What is measured from the real modules (nothing here is a hand-typed game number):
--   * raids: for every camp tier, PoolSize camps from Layout.generateCamp, each solved by Heist.solveRaid under the
--     padded human model (Config.Raid.HumanPad). A raid is one of those camps. The player departs each planned
--     crossing with a normal timing error of `sigma` seconds and is judged by the SERVER's own catch rule
--     (Heist.crossingCaught with pad nil: the latency grace, no padding). The first crossing caught ends the raid.
--   * prices, permits, heat, expansions, jars, sell values, the poacher's theft: Economy and Config.
--   * the pedestals: Offers (P1 Common, P2 your tier, P3 the next tier up; a bought pedestal refills after
--     Economy.BuyTweenSeconds; a rank-up redraws P2 and P3).
--
-- The PLAYER is a model, and these are its assumptions (DESIGN.md section 4's, kept so the numbers compare):
--   * jars are collected every CollectEvery (30) seconds of home time;
--   * a raid takes TimeFactor x the solver's human plan, plus RaidOverhead (10) seconds for the board, the camp
--     sign, the teleports and the walk home; a caught raid ends at the crossing it was caught on;
--   * the poacher is never trapped: from Poacher.FirstAfterSeconds on, every 180-240 s, it takes half of the
--     fullest jar (Economy.theft) once the lair holds Poacher.MinCryptids;
--   * purchases are payback-greedy: every candidate (buy a pedestal into a free cage or over the worst cage, which
--     is released for half its price; unlock a cage and fill it from a pedestal; raid an unlocked, calm camp tier
--     whose permit is affordable) has cost / expected income gained. The player does the best one when it can pay;
--     while saving for it, it does an affordable one only if that pays back before the best one becomes affordable.
--     No re-rolls, no traps, no offline time (offline jars only make it faster).
--   * three players: "normal" (sigma 0.25 s, plan x 2: DESIGN.md's first raider), "casual" (sigma 0.35 s, plan x 3)
--     and "idle" (never raids).

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Economy = require("../src/shared/Economy")
local Offers = require("../src/shared/Offers")
local Layout = require("../src/shared/Layout")
local Heist = require("../src/shared/Heist")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local PoolSize = 100         -- camps per tier the raids are drawn from
local Seeds = 24             -- sessions per player model
local Horizon = 24 * 3600    -- seconds of play simulated at most
local CollectEvery = 30
local RaidOverhead = 10

local MODELS = {
	{ name = "normal", sigma = 0.25, factor = 2, raids = true },
	{ name = "casual", sigma = 0.35, factor = 3, raids = true },
	{ name = "idle", sigma = 0, factor = 1, raids = false },
}

local function normal(rng: any): number
	local u1 = math.max(rng:next(), 1e-12)
	local u2 = rng:next()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

--============================================================================ 1. raids on the real camps

local pools = {}
for tier = 1, #Config.Camps do
	local pool = {}
	for s = 1, PoolSize do
		local C = Layout.generateCamp(Config, Rng, Layout.campSeed(Config, 9100 * tier, s, tier), tier)
		local plan = Heist.solveRaid(Config, Layout, C, { pad = Config.Raid.HumanPad })
		if plan then table.insert(pool, { camp = C, plan = plan }) end
	end
	truthy(#pool == PoolSize, string.format("tier %d: all %d pooled camps are solvable", tier, PoolSize))
	pools[tier] = pool
end

-- A player waiting in front of a gap aims at the MIDDLE of the safe moment to go (DESIGN.md section 5's success
-- model), not at the solver's earliest padded departure. The safe moments are measured with the server's rule:
-- the departures around the planned one at which the crossing is not caught, edges found to 1 ms.
local function departCaught(camp: any, x: any, d: number): boolean
	return Heist.crossingCaught(Config, Layout, camp, { trap = x.trap, depart = d, speed = x.speed, from = x.from, to = x.to }, nil)
end
local function edge(camp: any, x: any, safe: number, dir: number): number
	local step = 0.02
	local d = safe
	while not departCaught(camp, x, d + dir * step) and math.abs(d - safe) < 10 do d += dir * step end
	local lo, hi = d, d + dir * step -- lo safe, hi caught
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		if departCaught(camp, x, mid) then hi = mid else lo = mid end
	end
	return lo
end
local windows = { 0, 0 }
for tier = 1, #Config.Camps do
	for _, entry in pools[tier] do
		for _, x in entry.plan.crossings do
			assert(not departCaught(entry.camp, x, x.depart), "a planned crossing is safe under the server's rule")
			x.safeFrom = edge(entry.camp, x, x.depart, -1)
			x.safeTo = edge(entry.camp, x, x.depart, 1)
			x.aim = (x.safeFrom + x.safeTo) / 2
			windows[1] += 1
			windows[2] += x.safeTo - x.safeFrom
		end
	end
end
truthy(windows[1] > 0, string.format("%d planned crossings measured, mean safe window %.2f s", windows[1], windows[2] / math.max(1, windows[1])))

-- One raid: -> success, seconds of plan time spent (the whole plan, or up to the crossing that caught it).
local function raidOnce(tier: number, sigma: number, rng: any): (boolean, number)
	local pick = pools[tier][rng:below(#pools[tier])]
	for _, x in pick.plan.crossings do
		local moved = { trap = x.trap, depart = x.aim + sigma * normal(rng), speed = x.speed, from = x.from, to = x.to }
		if Heist.crossingCaught(Config, Layout, pick.camp, moved, nil) then
			return false, math.max(0, moved.depart)
		end
	end
	return true, pick.plan.total
end

-- the success chance each player model sees, measured the same way (20 000 raids per tier and sigma)
local successOf = {}
for _, M in MODELS do
	if M.raids then
		successOf[M.name] = {}
		local rng = Rng.new(4242)
		for tier = 1, #Config.Camps do
			local ok = 0
			for _ = 1, 20000 do
				if raidOnce(tier, M.sigma, rng) then ok += 1 end
			end
			successOf[M.name][tier] = ok / 20000
		end
		print(string.format("  raid success, sigma %.2f s: tier 1 %.1f %%, tier 2 %.1f %%, tier 3 %.1f %%, tier 4 %.1f %%", M.sigma,
			100 * successOf[M.name][1], 100 * successOf[M.name][2], 100 * successOf[M.name][3], 100 * successOf[M.name][4]))
	end
end
for tier = 2, #Config.Camps do
	truthy(successOf.normal[tier] <= successOf.normal[tier - 1] + 0.005,
		string.format("a harder camp is never easier: tier %d %.3f vs tier %d %.3f", tier, successOf.normal[tier], tier - 1, successOf.normal[tier - 1]))
end
truthy(successOf.normal[1] > 0.99, string.format("the free tier-1 camp is a sure thing for a normal player (%.3f)", successOf.normal[1]))

--============================================================================ 2. the session

local function avgRate(tier: number): number
	local sum, n = 0, 0
	for _, s in Config.Species do
		if s.tier == tier then sum += s.rate; n += 1 end
	end
	return sum / n
end

local function simulate(M: any, seed: number): any
	local rng = Rng.new(seed * 7919 + 17)
	local offerRng = Rng.new(seed * 104729 + 3)
	local p = Economy.defaultProfile(Config)
	local tutorial = 0
	local rank = 0
	local offers = Offers.initial(Config, offerRng, rank, tutorial)
	local refillAt = { 0, 0, 0 }
	local t = 0
	local busyUntil = 0
	local nextCollect = CollectEvery
	local nextPoacher = Config.Poacher.FirstAfterSeconds
	local pendingRaid: any = nil
	local reached: { [string]: number } = {}
	local stats = { raids = 0, caught = 0, stolen = 0, bought = 0, stolenBy = { 0, 0, 0, 0 } }

	local function mark(name: string)
		if reached[name] == nil then reached[name] = t end
	end
	local function lairRate(): number return Economy.lairRate(Config, p) end
	local function addToJournal(sp: string)
		if not Economy.journalHas(p.journal, sp) then table.insert(p.journal, sp) end
		local newRank = Economy.rank(Config, p.journal)
		if newRank > rank then
			offers = Offers.onRankChange(Config, offerRng, offers, rank, newRank, tutorial)
			rank = newRank
		end
	end
	-- the cage a new cryptid goes into: a free unlocked one, or the worst occupied one (released)
	local function slotFor(): (number?, number)
		local free = Economy.firstEmptyCage(Config, p)
		if free then return free, 0 end
		local worst, worstRate = nil, math.huge
		for i = 1, p.cagesUnlocked do
			local col = Config.World.CageOrder[i]
			local r = Economy.rate(Config, p.cages[col].sp)
			if r < worstRate then worst, worstRate = col, r end
		end
		return worst, worstRate
	end
	local function place(sp: string)
		local col, _ = slotFor()
		if col == nil then return end
		local old = p.cages[col]
		if old.sp ~= "" then
			p.essence += Economy.sellValue(Config, old.sp) + old.jar
		end
		p.cages[col] = { sp = sp, jar = 0 }
		addToJournal(sp)
	end

	local function candidates(): { any }
		local out = {}
		local col, worstRate = slotFor()
		local freeCage = Economy.firstEmptyCage(Config, p) ~= nil
		for slot = 1, Config.Offers.Pedestals do
			local sp = offers[slot]
			if sp ~= "" and refillAt[slot] <= t then
				local r = Economy.rate(Config, sp)
				local price = Economy.price(Config, sp) :: number
				if col and r > worstRate then
					local refund = if freeCage then 0 else Economy.sellValue(Config, p.cages[col].sp)
					table.insert(out, { kind = "buy", slot = slot, cost = price - refund, gain = r - worstRate })
				end
				if not freeCage and p.cagesUnlocked < Config.Economy.MaxCages then
					local exp = Economy.expansionPrice(Config, p.cagesUnlocked) :: number
					table.insert(out, { kind = "expand", slot = slot, cost = exp + price, gain = r })
				end
			end
		end
		if M.raids then
			for tier = 1, #Config.Camps do
				if Economy.campUnlocked(Config, tier, p.journal) and (p.heat["t" .. tier] or 0) <= t then
					local gain = successOf[M.name][tier] * (avgRate(tier) - worstRate)
					if col and gain > 0 then
						table.insert(out, { kind = "raid", tier = tier, cost = Economy.permit(Config, tier), gain = gain })
					end
				end
			end
		end
		for _, c in out do c.payback = c.cost / c.gain end
		return out
	end

	local function act(c: any)
		if c.kind == "raid" then
			-- the server starts a hunt only with a free cage: release the worst one first (Main.server startRaid)
			if Economy.firstEmptyCage(Config, p) == nil then
				local col = slotFor()
				if col then
					p.essence += Economy.sellValue(Config, p.cages[col].sp) + p.cages[col].jar
					p.cages[col] = { sp = "", jar = 0 }
				end
			end
			p.essence -= c.cost
			local ok, spent = raidOnce(c.tier, M.sigma, rng)
			stats.raids += 1
			busyUntil = t + spent * M.factor + RaidOverhead
			pendingRaid = { tier = c.tier, ok = ok }
			return
		end
		if c.kind == "expand" then
			p.essence -= Economy.expansionPrice(Config, p.cagesUnlocked) :: number
			p.cagesUnlocked += 1
		end
		local sp = offers[c.slot]
		p.essence -= Economy.price(Config, sp) :: number
		place(sp)
		stats.bought += 1
		tutorial = math.max(tutorial, 1)
		offers[c.slot] = Offers.draw(Config, offerRng, c.slot, rank, tutorial)
		refillAt[c.slot] = t + Config.Economy.BuyTweenSeconds
	end

	while t < Horizon do
		t += 1
		for col = 1, 9 do
			local c = p.cages[col]
			if c.sp ~= "" then c.jar = Economy.accrue(Config, c.sp, c.jar, 1) end
		end
		if t >= nextPoacher then
			if Economy.cryptidCount(Config, p) >= Config.Poacher.MinCryptids then
				local col = Economy.fullestCage(Config, p)
				if col then p.cages[col].jar -= Economy.theft(Config, p.cages[col].jar) end
			end
			nextPoacher = t + Config.Poacher.IntervalMin + rng:below(Config.Poacher.IntervalMax - Config.Poacher.IntervalMin + 1) - 1
		end
		if t >= busyUntil then
			if pendingRaid then
				local R = pendingRaid
				pendingRaid = nil
				if R.ok then
					local list = Economy.speciesOfTier(Config, R.tier)
					place(list[rng:below(#list)])
					p.heat["t" .. R.tier] = t + Economy.heatSeconds(Config, R.tier)
					stats.stolen += 1
					stats.stolenBy[R.tier] += 1
				else
					stats.caught += 1
				end
				nextCollect = t -- the walk home passes the Collect Pad
			end
			if t >= nextCollect then
				p.essence += Economy.collect(Config, p)
				nextCollect = t + CollectEvery
			end
			for _ = 1, 20 do
				if t < busyUntil then break end
				local cs = candidates()
				if #cs == 0 then break end
				table.sort(cs, function(a, b) return a.payback < b.payback end)
				local best = cs[1]
				local chosen = nil
				if best.cost <= p.essence then
					chosen = best
				else
					local wait = (best.cost - p.essence) / math.max(lairRate(), 1e-9)
					for _, c in cs do
						if c.cost <= p.essence and c.payback <= wait then chosen = c; break end
					end
				end
				if chosen == nil then break end
				act(chosen)
			end
		end
		if rank >= 2 then mark("rare") end
		if rank >= 3 then mark("legendary") end
		if rank >= 4 then mark("mythic") end
		if Economy.lairRate(Config, p) >= Config.Night.GatheringRate then mark("gathering") end
		if #p.journal >= #Config.Species then mark("journal") end
		if p.cagesUnlocked >= Config.Economy.MaxCages then mark("cages") end
		local mythics = 0
		for col = 1, 9 do if Economy.tierOf(Config, p.cages[col].sp) == 4 then mythics += 1 end end
		if mythics >= Config.Economy.MaxCages then mark("nineMythics"); break end
	end
	return { reached = reached, stats = stats }
end

--============================================================================ 3. the minutes

local function median(xs: { number }): number
	local s = table.clone(xs)
	table.sort(s)
	if #s == 0 then return math.huge end
	if #s % 2 == 1 then return s[(#s + 1) / 2] end
	return (s[#s / 2] + s[#s / 2 + 1]) / 2
end

local MILESTONES = { "rare", "legendary", "mythic", "gathering", "journal", "cages", "nineMythics" }
local results = {}
for _, M in MODELS do
	local mins: { [string]: { number } } = {}
	local missing: { [string]: number } = {}
	local raids, caught = 0, 0
	for _, k in MILESTONES do mins[k] = {}; missing[k] = 0 end
	for seed = 1, Seeds do
		local r = simulate(M, seed)
		raids += r.stats.raids
		caught += r.stats.caught
		for _, k in MILESTONES do
			if r.reached[k] then table.insert(mins[k], r.reached[k] / 60) else missing[k] += 1 end
		end
	end
	results[M.name] = { mins = mins, missing = missing }
	local line = {}
	for _, k in MILESTONES do
		local xs = mins[k]
		if #xs == 0 then
			table.insert(line, string.format("%s never", k))
		else
			table.sort(xs)
			table.insert(line, string.format("%s %.1f (%.1f-%.1f)%s", k, median(xs), xs[1], xs[#xs],
				if missing[k] > 0 then string.format(" +%d not in 24 h", missing[k]) else ""))
		end
	end
	print(string.format("  %-6s %s | raids %d, caught %d", M.name, table.concat(line, ", "), raids, caught))
end

-- THE BRAG MOMENT: the normal player's first Mythic, in about 30-45 minutes (median of the sessions)
local normal = results.normal
local brag = median(normal.mins.mythic)
truthy(normal.missing.mythic == 0, string.format("every normal session reaches the first Mythic (%d did not)", normal.missing.mythic))
truthy(brag >= 30 and brag <= 45, string.format("the brag moment (first Mythic, Mythic Night) comes at %.1f min of normal play: inside 30-45", brag))
-- and it is a reach, not a gift: the first Legendary comes clearly before it
truthy(median(normal.mins.legendary) < brag - 5, string.format("the first Legendary (%.1f min) comes well before the brag (%.1f)", median(normal.mins.legendary), brag))
-- THE LONG-TERM GOAL beyond it: nine Mythics takes the normal player at least four times as long
local goal = median(normal.mins.nineMythics)
truthy(goal >= 4 * brag, string.format("the long-term goal (nine Mythics, %.1f min) is at least 4x the brag moment (%.1f)", goal, brag))
-- the night's fifth band (the gathering) is a step on the way: after the brag, before the end goal
local gathering = median(normal.mins.gathering)
truthy(normal.missing.gathering == 0, string.format("every normal session reaches the gathering (%d did not)", normal.missing.gathering))
truthy(gathering > brag + 15 and gathering < goal - 30, string.format("the gathering (%.1f min) comes well after the brag (%.1f) and well before nine Mythics (%.1f)",
	gathering, brag, goal))
-- the casual player gets there too, later; the idle player much later
truthy(median(results.casual.mins.mythic) >= brag, string.format("a casual raider's first Mythic (%.1f) is not before the normal one (%.1f)",
	median(results.casual.mins.mythic), brag))
truthy(median(results.idle.mins.mythic) > 2 * brag, string.format("never raiding takes more than twice as long to the first Mythic (%.1f)",
	median(results.idle.mins.mythic)))

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing tests failed") end
