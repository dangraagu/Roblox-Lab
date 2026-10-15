-- Pacing — the brag moment, the bands, the long-term goal, the hazard rarity and the anti-farm bounds, measured
-- with the pacing model (tests/LineModel.luau) on the GAME's own rules and Config. Run: luau tests/Pacing.spec.luau
--
-- docs/complete-game-standard.md §2: a brag moment in about 30-45 minutes of normal play, a long-term goal beyond
-- it, measured with a pacing model in tests/. DESIGN.md quotes design/model.py; this spec is the authority (it
-- reads Config), and every number it prints is what the build ships. The player profiles are ASSUMPTIONS
-- (Config.Pacing.Profiles): replace `normal` with telemetry after the first real sessions and run this again.
-- About 15 s.

local Config = require("../src/shared/Config")
local LM = require("./LineModel")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local LO, HI = Config.Pacing.BragMinutes[1], Config.Pacing.BragMinutes[2]
local pct = LM.pct
local SEEDS = 20

--============================================================================ the brag moment: the first Rocket
local brag = {}
local runs = {}
for _, p in { "fast", "normal", "slow", "mixed", "bot", "cheapest", "random", "saver", "green", "green60", "anyaffordable" } do
	local rk, buys = {}, {}
	runs[p] = {}
	for seed = 1, SEEDS do
		local o = LM.simulate(p, seed, 90 * 60, { untilRocket = true })
		table.insert(rk, (o.firstRocket or math.huge) / 60)
		table.insert(buys, #o.purchases)
		table.insert(runs[p], o)
	end
	brag[p] = rk
	local function f(x) return if x == math.huge then "never" else string.format("%.1f", x) end
	print(string.format("  %-8s first Rocket at min: p10 %s  median %s  p90 %s   purchases (median) %d", p,
		f(pct(rk, 0.1)), f(pct(rk, 0.5)), f(pct(rk, 0.9)), math.floor(pct(buys, 0.5))))
end
for _, p in { "fast", "normal", "slow" } do
	truthy(pct(brag[p], 0.1) >= LO and pct(brag[p], 0.9) <= HI,
		string.format("the %s player's first Rocket lands in %d-%d min (p10 %.1f, p90 %.1f)", p, LO, HI, pct(brag[p], 0.1), pct(brag[p], 0.9)))
end
truthy(pct(brag.mixed, 0.5) >= LO and pct(brag.mixed, 0.5) <= HI,
	string.format("a player who follows the ★ three times in four lands it in the window too (median %.1f)", pct(brag.mixed, 0.5)))
-- REVIEW-2 R3: a player who taps whatever the panel paints gold or GREEN, not only the ★, lands it in the window too
for _, p in { "green", "green60" } do
	truthy(pct(brag[p], 0.1) >= LO and pct(brag[p], 0.9) <= HI,
		string.format("a player who taps any green button (%s) lands the first Rocket in %d-%d min (p10 %.1f, p90 %.1f)", p, LO, HI, pct(brag[p], 0.1), pct(brag[p], 0.9)))
end
truthy(pct(brag.anyaffordable, 0.5) > HI,
	string.format("CONTROL for the green rule: a player who taps any affordable button, whatever its colour, misses the window (median %.1f)", pct(brag.anyaffordable, 0.5)))
truthy(pct(brag.saver, 0.5) > HI,
	string.format("CONTROL for rule 0: without \"save for the next station\" the first Rocket misses the window (median %s)",
		if pct(brag.saver, 0.5) == math.huge then "never in 90 min" else string.format("%.1f", pct(brag.saver, 0.5))))
truthy(pct(brag.normal, 0.5) - pct(brag.bot, 0.5) < 3,
	string.format("purchasing, not walking skill, sets the pace: the bot is only %.1f min ahead of the normal player",
		pct(brag.normal, 0.5) - pct(brag.bot, 0.5)))

--============================================================================ the bands: every first-run band lasts at least 2 min
do
	local names = { "Junkyard", "Foundry", "Press Works", "Machine Shop", "Robot Works" }
	local line = {}
	for b = 1, 5 do
		local d = {}
		for _, o in runs.normal do
			local a, c = o.tierAt["0:" .. b], o.tierAt["0:" .. (b + 1)]
			if a and c then table.insert(d, (c - a) / 60) end
		end
		eq(#d, SEEDS, names[b] .. ": entered and left in every normal run")
		truthy(pct(d, 0) >= 2, string.format("%s lasts at least 2 min in every normal first run (min %.2f)", names[b], pct(d, 0)))
		table.insert(line, string.format("%s %.1f/%.1f/%.1f", names[b], pct(d, 0), pct(d, 0.5), pct(d, 1)))
		-- entry minutes
	end
	print("  band durations, normal, min/median/max: " .. table.concat(line, ", "))
	local enters = {}
	for b = 1, 6 do
		local e = {}
		for _, o in runs.normal do table.insert(e, (o.tierAt["0:" .. b] or math.huge) / 60) end
		table.insert(enters, string.format("%.1f", pct(e, 0.5)))
	end
	print("  bands entered at min (normal, median), tiers 1-6: " .. table.concat(enters, ", "))
end

--============================================================================ hazards: one per 2-3 minutes, and jams cost an active player nothing
do
	local per, lost, sputters = {}, {}, {}
	for _, o in runs.normal do
		local from = o.tierAt["0:2"] or 0
		table.insert(per, (o.firstRocket - from) / 60 / math.max(1, o.hazardsToRocket or 0))
		table.insert(lost, o.lostIncome / math.max(1e-9, o.idealIncome))
		table.insert(sputters, o.jams)
	end
	print(string.format("  before the first Rocket (normal): a hazard every %.2f min (median), %d sputters, income lost to jams %.4f",
		pct(per, 0.5), math.floor(pct(sputters, 0.5)), pct(lost, 0.5)))
	truthy(pct(per, 0.5) >= 2 and pct(per, 0.5) <= 3, "about one hazard per 2-3 minutes once hazards start")
	truthy(pct(lost, 1) < 0.01, "an active player who fixes every sputter loses under 1% of income to jams")
end

--============================================================================ the first minute
do
	local fb = {}
	for seed = 1, SEEDS do
		local o = LM.simulate("normal", seed, 61)
		table.insert(fb, o.firstBuyAt or math.huge)
	end
	print(string.format("  first purchase after the free Shredder (placed at 3.0 s): median %.1f s (p10 %.1f, p90 %.1f)",
		pct(fb, 0.5), pct(fb, 0.1), pct(fb, 0.9)))
	truthy(pct(fb, 0.9) <= 30, "the first paid purchase comes inside the first half minute")
end

--============================================================================ the long-term goal: the Golden Factory
do
	local golden, first = {}, {}
	for seed = 1, 10 do
		local o = LM.simulate("normal", seed, 3 * 3600, { recycle = true })
		table.insert(golden, (o.goldenAt or math.huge) / 60)
		table.insert(first, o.runs[1] and o.runs[1].finish / 60 or math.huge)
	end
	local g, b = pct(golden, 0.5), pct(brag.normal, 0.5)
	print(string.format("  first recycle at %.1f min, the Golden Factory (4 bolts) at %.1f min (normal, median of 10)", pct(first, 0.5), g))
	truthy(g >= 3 * b, string.format("the Golden Factory is at least 3x the brag moment (%.1f vs %.1f)", g, 3 * b))
	truthy(pct(golden, 1) < 180, "and every normal run reaches it inside 3 hours")
end

--============================================================================ the board: what a script can and cannot gain in 8 hours
do
	local bolts = {}
	for _, p in { "normal", "bot", "afkmacro", "jiggle" } do
		local b = {}
		for seed = 1, 5 do
			table.insert(b, LM.simulate(p, seed, 8 * 3600, { recycle = true }).final.bolts)
		end
		bolts[p] = b
	end
	print(string.format("  Gold Bolts after 8 h from join (median of 5): normal %d, bot %d, auto-buy + auto-recycle macro %d, anti-AFK jiggle %d",
		pct(bolts.normal, 0.5), pct(bolts.bot, 0.5), pct(bolts.afkmacro, 0.5), pct(bolts.jiggle, 0.5)))
	eq(pct(bolts.afkmacro, 1), 0, "an auto-buy + auto-recycle macro that never fixes a jam gains 0 bolts in 8 h")
	eq(pct(bolts.jiggle, 1), 0, "an anti-AFK jiggle gains 0")
	truthy(pct(bolts.bot, 0.5) <= 1.1 * pct(bolts.normal, 0.5), "a perfect bot climbs no faster than 1.1x a normal player")
	truthy(pct(bolts.normal, 0.5) >= 8, "a normal player keeps climbing (8+ bolts in 8 h)")
	for _, p in { "afkmacro", "jiggle" } do
		local g = {}
		for seed = 1, 5 do
			local o = LM.simulate("normal", seed, 35 * 60 + 8 * 3600, { recycle = true, switchAt = { 35 * 60, p } })
			table.insert(g, o.final.bolts - (o.boltsAtSwitch or 0))
		end
		eq(pct(g, 1), 0, "the normal player's 35-minute line handed to the " .. p .. " gains 0 bolts in the next 8 h")
	end
end

--============================================================================ an untended line winds down
do
	for seed = 1, 3 do
		local u = LM.untended(seed, 35 * 60, { 5, 10, 30 })
		print(string.format("  untended 35-min line, seed %d: income now x%.2f / x%.2f / x%.3f of a tended line after 5 / 10 / 30 min",
			seed, u[5].now, u[10].now, u[30].now))
		truthy(u[30].now <= 0.05, "after 30 min left alone the line earns at most 5% of a tended one")
	end
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
