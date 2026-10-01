-- Spec for Medals: a run's medal against the day's perfect line P, ranks, torches, time text.
-- Run: luau tests/Medals.spec.luau
--
-- Medals are relative to P (the tight line, Dungeon.tightLine, stored as perfectMs), never to a
-- cell-count par: a par would make days with many turns far easier to medal (DESIGN §3.2).
-- Thresholds (REVIEW-1, on the tight P): Silver <= 1.71 P, Gold <= 1.33 P, Sealer <= 1.18 P, Bronze =
-- any finish. The first build's 1.60 / 1.25 / 1.10 were on its looser centre-line P.
local Medals = require("../src/shared/Medals")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local cfg = Config

--================================================================ grading, exact at the edges
local P = 27340 -- ms
eq(Medals.grade(32261, P, cfg), "Sealer", "1.18 P rounded down (32261 ms) is Sealer")
eq(Medals.grade(32262, P, cfg), "Gold", "one ms more is Gold")
eq(Medals.grade(36362, P, cfg), "Gold", "1.33 P rounded down is Gold")
eq(Medals.grade(36363, P, cfg), "Silver", "one ms more is Silver")
eq(Medals.grade(46751, P, cfg), "Silver", "1.71 P rounded down is Silver")
eq(Medals.grade(46752, P, cfg), "Bronze", "one ms more is Bronze")
eq(Medals.grade(899999, P, cfg), "Bronze", "any finish is at least Bronze")
eq(Medals.grade(20000, P, cfg), "Sealer", "a time under P (no walk can, but the grader must not care) is Sealer")

eq(Medals.thresholdMs(P, "Sealer", cfg), 32261, "the Sealer threshold shown in the antechamber")
eq(Medals.thresholdMs(P, "Gold", cfg), 36362, "the Gold threshold")
eq(Medals.thresholdMs(P, "Silver", cfg), 46751, "the Silver threshold")

-- the thresholds shown must earn the medal they name (no off-by-one between the card and the grader)
do
	local bad = 0
	for p = 22000, 34000, 7 do
		for _, m in { "Silver", "Gold", "Sealer" } do
			local t = Medals.thresholdMs(p, m, cfg)
			if Medals.tier(Medals.grade(t, p, cfg)) < Medals.tier(m) then bad += 1 end
			if Medals.tier(Medals.grade(t + 1, p, cfg)) >= Medals.tier(m) then bad += 1 end
		end
	end
	eq(bad, 0, "for 1715 values of P, the shown threshold earns the medal and one ms more does not")
end

eq(Medals.tier(nil), 0, "no medal is tier 0")
eq(Medals.tier("Bronze"), 1, "Bronze tier 1")
eq(Medals.tier("Silver"), 2, "Silver tier 2")
eq(Medals.tier("Gold"), 3, "Gold tier 3")
eq(Medals.tier("Sealer"), 4, "Sealer tier 4")
eq(Medals.tier("Platinum"), 0, "an unknown medal name is tier 0 (fails closed)")
eq(Medals.grade(0 / 0, P, cfg), nil, "a NaN time earns nothing")
eq(Medals.grade(30000, 0, cfg), nil, "a day with no perfect line grades nothing")

--================================================================ ranks
local function life(t) return t end
eq(Medals.rank(life({ doors = 0, goldDays = 0, sealerDays = 0, bestStreak = 0 }), cfg), 0, "no Door opened: no rank")
eq(Medals.rank(life({ doors = 1, goldDays = 0, sealerDays = 0, bestStreak = 1 }), cfg), 1, "first Door: Wanderer")
eq(Medals.rank(life({ doors = 2, goldDays = 1, sealerDays = 0, bestStreak = 2 }), cfg), 2, "first Gold: Gilded")
eq(Medals.rank(life({ doors = 2, goldDays = 1, sealerDays = 1, bestStreak = 2 }), cfg), 3, "first Sealer: Sealer")
eq(Medals.rank(life({ doors = 9, goldDays = 3, sealerDays = 0, bestStreak = 7 }), cfg), 4, "a 7-day streak: Warden")
eq(Medals.rank(life({ doors = 9, goldDays = 3, sealerDays = 0, bestStreak = 6 }), cfg), 2, "6 days is not Warden")
eq(Medals.rank(life({ doors = 40, goldDays = 35, sealerDays = 30, bestStreak = 3 }), cfg), 5, "30 Sealer days: Keeper")
eq(Medals.rank(life({ doors = 40, goldDays = 35, sealerDays = 29, bestStreak = 3 }), cfg), 3, "29 is not Keeper")
eq(Medals.rank(nil, cfg), 0, "no profile: no rank")
eq(Medals.rankLabel(5, cfg), "Keeper of the Same Door", "the Keeper label")
eq(Medals.rankLabel(0, cfg), "", "no rank, no label")

--================================================================ torches keep clear of the reserved colours
do
	local function dist(a, b)
		return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
	end
	local worst = math.huge
	for r = 0, 5 do
		local c = Medals.torch(r, cfg)
		worst = math.min(worst, dist(c, cfg.Colours.SealGold), dist(c, cfg.Colours.HazardRed))
	end
	truthy(worst >= cfg.Colours.MinColourDistance,
		string.format("every torch colour keeps >= %d from seal-gold and hazard-red (closest %.1f)", cfg.Colours.MinColourDistance, worst))
end

--================================================================ time text
eq(Medals.formatTime(27340), "27.34", "under a minute: seconds and hundredths")
eq(Medals.formatTime(27349), "27.34", "hundredths are truncated, never rounded up past the real time")
eq(Medals.formatTime(151050), "2:31.05", "over a minute: m:ss.cc")
eq(Medals.formatTime(0), "0.00", "zero")
eq(Medals.formatTime(nil), "--", "no time")
-- the finish card reads a duration: "27.34 s" under a minute, "2:31.05" over it (never "2:31.05 s",
-- which every first run's card showed: a first run takes 2-3 minutes)
eq(Medals.formatDuration(27340), "27.34 s", "a duration under a minute carries its unit")
eq(Medals.formatDuration(59999), "59.99 s", "…up to the last hundredth before a minute")
eq(Medals.formatDuration(60000), "1:00.00", "a minute or more reads as m:ss.cc with no stray unit")
eq(Medals.formatDuration(151050), "2:31.05", "…as a first run's card does")
eq(Medals.formatDuration(nil), "--", "no time")

print(string.format("Medals: %d passed, %d failed", passed, failed))
if failed > 0 then error("Medals spec failed", 0) end
