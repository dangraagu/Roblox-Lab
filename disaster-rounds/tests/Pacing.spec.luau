-- Pacing: the brag moment and the long-term goals, measured on the real modules (tests/RoundModel.luau).
-- Run: luau tests/Pacing.spec.luau     (about a minute)
--
-- docs/complete-game-standard.md §2: "A brag moment within about 30-45 minutes of normal play, and a long-term goal
-- beyond it. Measure the minutes with a pacing model in tests/." DESIGN.md §13 asks this file to assert:
--   * a normal player's brag (band 5, Falling Sky, 21 survivals) median inside 30-45 min and within 5 min of 35.2;
--   * the fast and slow players' medians inside 30-45 min;
--   * every band's median stay at least 2 minutes;
--   * band 6 (New Dawn) under 4 h for a normal player; the Codex 24/24 under 4 h for a normal player;
--   * the fairness floor: the bot (0.6 s reaction, no lapses) survives every disaster at every Heat.
-- design/pacing_model.py was the design-time model; this one replaces it and prints the same tables.
local RoundModel = require("./RoundModel")
local Config = require("../src/shared/Config")
local Round = require("../src/shared/Round")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local pct = RoundModel.pct

local R = RoundModel.newRand(20261007)
local t0 = os.clock()
local tables = RoundModel.tables(Config, R, { rounds = 150, maps = 60, profiles = { "fast", "normal", "slow", "bot" } })

--======================================================================= per-round tables

print("aimed rings per player per round (mean), Heat 0-5:")
for _, sched in { "meteor", "other" } do
	local row = {}
	for heat = 0, 5 do table.insert(row, string.format("%.1f", tables.ringsN[sched .. ":" .. heat])) end
	print("  " .. sched .. ": " .. table.concat(row, " / "))
end
print("P(survive a round) = the disaster x the rings, Heat 0-5:")
local avg = {}
for _, pname in { "fast", "normal", "slow", "bot" } do
	for _, kind in Config.Disasters.Kinds do
		local row = {}
		for heat = 0, 5 do table.insert(row, string.format("%.3f", RoundModel.pSurvive(tables, pname, kind, heat))) end
		print(string.format("  %-6s %-7s %s", pname, kind, table.concat(row, " ")))
	end
	local a = {}
	for heat = 0, 5 do
		local s = 0
		for _, kind in Config.Disasters.Kinds do s += RoundModel.pSurvive(tables, pname, kind, heat) end
		a[heat] = s / 4
	end
	avg[pname] = a
	print(string.format("  %-6s average %.3f -> %.3f", pname, a[0], a[5]))
end
do
	local worst = 1
	for _, kind in Config.Disasters.Kinds do
		for heat = 0, 5 do worst = math.min(worst, RoundModel.pSurvive(tables, "bot", kind, heat)) end
	end
	eq(worst, 1, "the bot (0.6 s, no lapses) survives every disaster at every Heat: the fairness floor")
	truthy(avg.normal[0] > avg.normal[5] and avg.slow[0] > avg.slow[5], "Heat makes it harder for humans")
	truthy(avg.fast[0] >= avg.normal[0] and avg.normal[0] >= avg.slow[0], "faster players survive more")
	local shares = tables.quakeShare
	print(string.format("quake broken share p50 %.2f, max %.2f; the bot's tightest quake margin %.2f s",
		pct(shares, 0.5), pct(shares, 1), tables.quakeMargin))
	truthy(tables.quakeMargin > 0.5, string.format("the bot always had time to spare on a crack (%.2f s)", tables.quakeMargin))
end

--======================================================================= sessions

local S = 1500
local cyc = Round.cycleSeconds(Config.Round)
print(string.format("sessions: %d of 4 h per profile, a round every %d s", S, cyc))
local res = {}
for _, pname in { "normal", "fast", "slow" } do
	res[pname] = {}
	for _ = 1, S do table.insert(res[pname], RoundModel.session(Config, R, tables, pname, 240)) end
end
local bands = Config.Env.Bands
local function bandTimes(pname: string, b: number): { number }
	local out = {}
	for _, r in res[pname] do
		if r.bandT[b] then table.insert(out, r.bandT[b]) end
	end
	return out
end
for b = 2, #bands do
	local parts = {}
	for _, pname in { "normal", "fast", "slow" } do
		local v = bandTimes(pname, b)
		table.insert(parts, string.format("%s %.1f / %.1f / %.1f", pname, pct(v, 0.1), pct(v, 0.5), pct(v, 0.9)))
	end
	print(string.format("  band %d %-12s (%3d survivals): %s", b, bands[b].name, bands[b].from, table.concat(parts, " | ")))
end

local brag = 5
eq(bands[brag].id, Config.Brag.BandId, "band 5 is the brag")
local lo, hi = Config.Pacing.BragMinutes[1], Config.Pacing.BragMinutes[2]
for _, pname in { "normal", "fast", "slow" } do
	local m = pct(bandTimes(pname, brag), 0.5)
	truthy(m >= lo and m <= hi, string.format("%s player: the brag (Falling Sky) at %.1f min median, inside %d-%d", pname, m, lo, hi))
end
do
	local m = pct(bandTimes("normal", brag), 0.5)
	truthy(math.abs(m - 35.2) <= 5, string.format("normal brag %.1f min is within 5 min of DESIGN.md's 35.2", m))
	-- every band's median stay is at least 2 minutes
	for _, pname in { "normal", "fast", "slow" } do
		local stays = {}
		for b = 2, #bands - 1 do
			local d = {}
			for _, r in res[pname] do
				if r.bandT[b] and r.bandT[b + 1] then table.insert(d, r.bandT[b + 1] - r.bandT[b]) end
			end
			local med = pct(d, 0.5)
			table.insert(stays, string.format("%.1f", med))
			truthy(med >= 2, string.format("%s: band %d (%s) lasts %.1f min (median) before the next", pname, b, bands[b].name, med))
		end
		local first = pct(bandTimes(pname, 2), 0.5)
		truthy(first >= 2, string.format("%s: band 1 lasts %.1f min", pname, first))
		print(string.format("  %s median minutes in bands 2..%d: %s (band 1: %.1f)", pname, #bands - 1, table.concat(stays, " / "), first))
	end
	local dawn = bandTimes("normal", #bands)
	truthy(#dawn >= S * 0.5 and pct(dawn, 0.5) < 240, string.format("New Dawn (band 6) for a normal player: %.1f min median, under 4 h", pct(dawn, 0.5)))
end

-- MAX HEAT, the best streak, the Codex
for _, pname in { "normal", "fast", "slow" } do
	local mh, b30, b60, b240, c30, c60, surv = {}, {}, {}, {}, {}, {}, {}
	for _, r in res[pname] do
		if r.maxHeatT then table.insert(mh, r.maxHeatT) end
		table.insert(b30, r.bestAt[30] or 0)
		table.insert(b60, r.bestAt[60] or 0)
		table.insert(b240, r.bestAt[240] or 0)
		table.insert(c30, r.codexAt[30] or 0)
		table.insert(c60, r.codexAt[60] or 0)
		table.insert(surv, r.survived / 4)
	end
	print(string.format("  %-6s first MAX HEAT %.1f / %.1f / %.1f min (%d%% in 4 h); best streak at 30/60/240 min %d / %d / %d; Codex at 30/60 min %d / %d; %.1f survivals an hour",
		pname, pct(mh, 0.1), pct(mh, 0.5), pct(mh, 0.9), math.floor(100 * #mh / S), pct(b30, 0.5), pct(b60, 0.5), pct(b240, 0.5),
		pct(c30, 0.5), pct(c60, 0.5), pct(surv, 0.5)))
end
do
	local cs = {}
	for _ = 1, 300 do
		local r = RoundModel.session(Config, R, tables, "normal", 60 * 40, true)
		if r.codexT then table.insert(cs, r.codexT / 60) end
	end
	local med = pct(cs, 0.5)
	print(string.format("  normal Codex 24/24: %.1f / %.1f / %.1f h (%d of 300 within 40 h)", pct(cs, 0.1), med, pct(cs, 0.9), #cs))
	truthy(med < 4, string.format("the Codex 24/24 for a normal player: %.1f h median, under 4 h", med))
end
do
	local firsts = {}
	for _, r in res.normal do table.insert(firsts, r.first) end
	print(string.format("  first time on the island after joining: %.1f / %.1f / %.1f s, max %.1f s",
		pct(firsts, 0.1), pct(firsts, 0.5), pct(firsts, 0.9), pct(firsts, 1)))
	truthy(pct(firsts, 1) <= Config.Round.IntermissionSeconds + 20, "nobody waits more than 40 s for their first time on the island")
end
print(string.format("  (model ran in %.0f s)", os.clock() - t0))

print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
