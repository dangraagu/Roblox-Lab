-- Spec for Ledger: the profile's pure bookkeeping. Run: luau tests/Ledger.spec.luau
--
-- What it pins (DESIGN §6.4, §12):
--   * today resets when the UTC day changes; lifetime counters were updated at finish time;
--   * doors / silverDays / goldDays / sealerDays count DAYS, once each, however many runs a day has:
--     they are one-time grants and move only inside applyFinish (the server calls it inside ONE
--     atomic UpdateAsync, and the transform may run more than once, so it must be a pure function of
--     the stored copy it is handed);
--   * the Door streak continues from yesterday, holds on the same day, restarts after a gap;
--   * the brag moment (first Sealer ever) is reported exactly once;
--   * junk from the DataStore is normalised, never trusted.
local Ledger = require("../src/shared/Ledger")
local Medals = require("../src/shared/Medals")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local D = 20726
local NOW = 1790730000
local function finish(p, day, t, medal, at)
	return Ledger.applyFinish(p, { day = day, timeMs = t, medal = medal, at = at or NOW }, Config, Medals)
end

--================================================================ a fresh profile
local p = Ledger.new(Config)
eq(p.v, 1, "profile version 1")
eq(p.life.doors, 0, "no doors yet")
eq(p.today.day, 0, "no day yet")
eq(Medals.rank(p.life, Config), 0, "no rank yet")

--================================================================ first finish: Bronze
do
	local r = finish(p, D, 151000, "Bronze")
	eq(r.improved, true, "the first finish is a best")
	eq(p.today.bestMs, 151000, "today's best is stored")
	eq(p.today.bestAt, NOW, "with when it was reached (the board's tie-break)")
	eq(p.life.doors, 1, "a Door day is counted")
	eq(p.life.streak, 1, "the streak starts at 1")
	eq(p.life.firstDay, D, "the first day is remembered")
	eq(r.rankAfter, 1, "Wanderer")
	eq(r.rankUp, true, "a rank-up is reported")
	eq(r.firstSealer, false, "not the brag moment")
end

--================================================================ same day, more runs: no double counting
do
	local r = finish(p, D, 40000, "Silver")
	eq(p.life.doors, 1, "a second finish on the same day is not a second Door day")
	eq(p.life.silverDays, 1, "the first Silver of the day counts one Silver day")
	eq(p.life.streak, 1, "the streak holds on the same day")
	eq(r.improved, true, "a faster time is an improvement")
	local r2 = finish(p, D, 41000, "Silver")
	eq(r2.improved, false, "a slower time is not")
	eq(p.today.bestMs, 40000, "the best stays the best")
	eq(p.life.silverDays, 1, "a second Silver the same day counts nothing")
	eq(p.today.finishes, 3, "finishes are counted")
end

--================================================================ skipping a tier grants every tier crossed
do
	local r = finish(p, D, 29000, "Sealer")
	eq(p.life.goldDays, 1, "a Sealer day is also a Gold day")
	eq(p.life.sealerDays, 1, "and a Sealer day")
	eq(p.life.silverDays, 1, "Silver was already counted today")
	eq(r.firstSealer, true, "THE DOOR IS SEALED: the first Sealer ever")
	eq(r.rankAfter, 3, "rank Sealer")
	eq(p.today.medal, "Sealer", "today's medal is the best tier")
	local r2 = finish(p, D, 28500, "Sealer")
	eq(r2.firstSealer, false, "the brag moment happens once")
	eq(p.life.sealerDays, 1, "a second Sealer the same day is not a second Sealer day")
end

--================================================================ the next day: streak and reset
do
	local r = finish(p, D + 1, 60000, "Bronze")
	eq(p.today.day, D + 1, "today moved to the new day")
	eq(p.today.bestMs, 60000, "today's best reset with it")
	eq(p.today.finishes, 1, "and its counters")
	eq(p.life.streak, 2, "a finish on the next day continues the streak")
	eq(p.life.doors, 2, "two Door days")
	eq(r.firstSealer, false, "no brag")
	-- a gap of one day restarts it
	finish(p, D + 3, 60000, "Bronze")
	eq(p.life.streak, 1, "a missed day restarts the streak at 1")
	eq(p.life.bestStreak, 2, "the best streak remembers 2")
end

--================================================================ 7 days: Warden
do
	local q = Ledger.new(Config)
	for d = 0, 6 do finish(q, D + d, 60000, "Bronze") end
	eq(q.life.streak, 7, "seven consecutive days")
	eq(Medals.rank(q.life, Config), 4, "Warden")
end

--================================================================ a run that finishes after a later day's finish
do
	local q = Ledger.new(Config)
	finish(q, D + 1, 50000, "Bronze")
	local r = finish(q, D, 30000, "Sealer")
	eq(r.late, true, "a finish for an older day than today's is late")
	eq(q.today.day, D + 1, "it does not roll today back")
	eq(q.life.sealerDays, 0, "and grants nothing: the day it belonged to is already over for the ledger")
	eq(q.today.bestMs, 50000, "today's best is untouched")
end

--================================================================ pure on the copy it is handed
do
	local stored = Ledger.new(Config)
	local a = Ledger.normalize(stored, Config)
	local b = Ledger.normalize(stored, Config)
	finish(a, D, 30000, "Sealer")
	finish(b, D, 30000, "Sealer")
	eq(a.life.sealerDays, b.life.sealerDays, "two invocations on two copies agree (UpdateAsync may retry)")
	eq(stored.life.sealerDays, 0, "normalize hands back a COPY: the stored value is never mutated")
end

--================================================================ posting to the board converges
do
	local q = Ledger.new(Config)
	finish(q, D, 40000, "Silver")
	eq(Ledger.needsPost(q, D), true, "a best that never reached the board needs a post")
	Ledger.markPosted(q, D, 40000)
	eq(Ledger.needsPost(q, D), false, "once posted, it does not")
	finish(q, D, 35000, "Silver")
	eq(Ledger.needsPost(q, D), true, "a better best needs a new post")
	eq(Ledger.needsPost(q, D + 1), false, "a new day with no finish needs nothing")
end

--================================================================ junk from the store
do
	local q = Ledger.normalize({ v = 1, today = { day = "x", bestMs = -5, medal = "Platinum" },
		life = { doors = "7", streak = 1e300, sealerDays = -3 }, [1] = "junk" }, Config)
	eq(q.today.day, 0, "a junk day is day 0")
	eq(q.today.bestMs, nil, "a negative best is dropped")
	eq(q.today.medal, nil, "an unknown medal is dropped")
	eq(q.life.doors, 7, "a numeric string is read as a number")
	eq(q.life.sealerDays, 0, "a negative counter clamps to 0")
	truthy(q.life.streak <= 100000, "an absurd streak is clamped")
	local e = Ledger.normalize(nil, Config)
	eq(e.life.doors, 0, "nil normalises to a fresh profile")
end

--================================================================ the streak a player list may show
-- REVIEW-1 (reviewer 2, finding 4): the stored streak only moves at the next finish, so a streak that
-- broke days ago was still shown in the player list. liveStreak is the streak as of `today`: alive
-- while the last Door day is today or yesterday (a finish today continues it), 0 after a gap.
do
	local life = { streak = 5, lastDay = 20730 }
	eq(Ledger.liveStreak(life, 20730), 5, "a finish today: the streak shows")
	eq(Ledger.liveStreak(life, 20731), 5, "the day after: still alive (a finish today continues it)")
	eq(Ledger.liveStreak(life, 20732), 0, "a whole missed day: the streak is broken and shows 0")
	eq(Ledger.liveStreak(life, 20733), 0, "three days on: 0, not the stored 5")
	eq(Ledger.liveStreak({ streak = 0, lastDay = 0 }, 20730), 0, "never finished: 0")
	eq(Ledger.liveStreak(life, 20729), 5, "a clock behind the record (another server's skew) keeps it")
end

print(string.format("Ledger: %d passed, %d failed", passed, failed))
if failed > 0 then error("Ledger spec failed", 0) end
