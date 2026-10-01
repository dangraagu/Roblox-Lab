-- Pacing: when does a normal player reach the brag moment? Run: luau tests/Pacing.spec.luau
--
-- docs/complete-game-standard.md §2: "a brag moment within about 30-45 minutes of normal play ...
-- Measure the minutes with a pacing model in tests/". The brag moment is the FIRST Sealer medal
-- ("THE DOOR IS SEALED", a run within SealerPct of the day's perfect line). The model (tests/RunnerModel,
-- on the game's own generator) plays daily sessions: 30 / 20 / 15 minutes a UTC day for the fast /
-- normal / slow profile, a new Door each day, up to MAXDAYS days, and counts cumulative minutes of
-- play until each medal first lands. It also measures the hazard rate with the game's own schedule.
--
-- Asserted (DESIGN §6.3):
--   * the normal profile's median cumulative minutes to the first Sealer is within [30, 45];
--   * fast <= normal <= slow for the first Silver and Gold, and fast <= normal for the Sealer;
--   * the normal near-miss rate (an impact within 12 studs) is within [1/3, 1/2] per running minute;
--   * no profile's first run comes near the 900 s run cap.
local X = require("./RunnerModel")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local cfg = Config
local PLAYERS, MAXDAYS = 120, 14
local ORDER = { "silver", "gold", "sealer" }
local MULTS = { silver = cfg.Medals.SilverPct / 100, gold = cfg.Medals.GoldPct / 100, sealer = cfg.Medals.SealerPct / 100 }

-- the days: one per (player, day), shared by every profile so the profiles are compared on the same Doors
local days = {}
for pl = 1, PLAYERS do
	days[pl] = {}
	for d = 1, MAXDAYS do
		days[pl][d] = X.makeDay(cfg, pl * 1000003 + d * 7919)
	end
end

local results = {}
for _, pname in { "fast", "normal", "slow" } do
	local prof = X.PROFILES[pname]
	local cum = { silver = {}, gold = {}, sealer = {} }
	local onDay = { silver = {}, gold = {}, sealer = {} }
	local never = { silver = 0, gold = 0, sealer = 0 }
	local daysWith = { silver = 0, gold = 0, sealer = 0 }
	local near, hits, running, firstRuns, dayCount = 0, 0, 0, {}, 0
	for pl = 1, PLAYERS do
		local total = 0
		local got = {}
		for d = 1, MAXDAYS do
			local day = days[pl][d]
			local thr = {}
			for i, k in ORDER do thr[i] = day.perfect * MULTS[k] end
			local res = X.day(cfg, day, prof, X.rng(pl * 31 + d * 17), thr, prof.sessionMin)
			dayCount += 1
			for i, k in ORDER do
				if res.reached[i] then daysWith[k] += 1 end
				if not got[k] and res.reached[i] then
					got[k] = true
					table.insert(cum[k], (total + res.reached[i]) / 60)
					table.insert(onDay[k], d)
				end
			end
			total += res.clock
			near += res.near
			hits += res.hits
			running += res.running
			table.insert(firstRuns, res.firstRun)
		end
		for _, k in ORDER do if not got[k] then never[k] += 1 end end
	end
	results[pname] = { cum = cum, onDay = onDay, never = never, daysWith = daysWith, dayCount = dayCount,
		nearRate = near / (running / 60), hitRate = hits / (running / 60), firstRuns = firstRuns }
	print(string.format("%s (%d-min sessions, %d players, up to %d days):", pname, prof.sessionMin, PLAYERS, MAXDAYS))
	for _, k in ORDER do
		local c = cum[k]
		if #c > 0 then
			print(string.format("   first %-6s (x%.2f P): cumulative min p10 %.1f p50 %.1f p90 %.1f | day p50 %d p90 %d | never in %d days: %d | earned on %.0f%% of days",
				k, MULTS[k], X.pct(c, 0.1), X.pct(c, 0.5), X.pct(c, 0.9), X.pct(onDay[k], 0.5), X.pct(onDay[k], 0.9), MAXDAYS, never[k],
				daysWith[k] / dayCount * 100))
		else
			print(string.format("   first %-6s: never reached (%d of %d players)", k, never[k], PLAYERS))
		end
	end
	print(string.format("   first run: p50 %.0f s, p90 %.0f s, max %.0f s", X.pct(firstRuns, 0.5), X.pct(firstRuns, 0.9), X.pct(firstRuns, 1)))
	print(string.format("   hazards: %.3f near-misses per running minute (one per %.1f min); a runner ignoring warnings: %.3f hits/min",
		results[pname].nearRate, 1 / results[pname].nearRate, results[pname].hitRate))
end

local N, F, S = results.normal, results.fast, results.slow
local sealerP50 = X.pct(N.cum.sealer, 0.5)
truthy(sealerP50 >= 30 and sealerP50 <= 45,
	string.format("BRAG MOMENT: the normal profile's first Sealer lands at a median of %.1f cumulative minutes, inside [30, 45]", sealerP50))
truthy(X.pct(F.cum.silver, 0.5) <= X.pct(N.cum.silver, 0.5) and X.pct(N.cum.silver, 0.5) <= X.pct(S.cum.silver, 0.5), "Silver: fast <= normal <= slow")
truthy(X.pct(F.cum.gold, 0.5) <= X.pct(N.cum.gold, 0.5) and X.pct(N.cum.gold, 0.5) <= X.pct(S.cum.gold, 0.5), "Gold: fast <= normal <= slow")
truthy(X.pct(F.cum.sealer, 0.5) <= sealerP50, "Sealer: fast <= normal")
truthy(N.nearRate >= 1 / 3 and N.nearRate <= 1 / 2,
	string.format("the normal near-miss rate %.3f/min is about one per 2-3 minutes", N.nearRate))
for _, pn in { "fast", "normal", "slow" } do
	truthy(X.pct(results[pn].firstRuns, 1) < cfg.RunCapSeconds * 0.8,
		string.format("%s: the slowest first run (%.0f s) stays well under the %d s run cap", pn, X.pct(results[pn].firstRuns, 1), cfg.RunCapSeconds))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
