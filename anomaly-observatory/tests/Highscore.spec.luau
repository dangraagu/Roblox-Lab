-- Spec for Highscore: the Field Guide board's value encoding (queued job A, design approved 2026-09-16).
-- Run: luau tests/Highscore.spec.luau
--
-- The board ranks on Field Guide completion (anomaly TYPES caught, 0..the catalog's size), ties broken by
-- who reached that count FIRST. One OrderedDataStore integer carries both:
--     value = caught * 2e9 + (2e9 - reachedAtUnix)
-- so a descending sort puts more types first and, among equals, the earlier time first. Everything a
-- store can hand back is clamped: a fabricated or corrupted value can never show more than the catalog's
-- size, and the board's query range leaves anything above it out altogether.
local Highscore = require("../src/shared/Highscore")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local CAP = 24
local T0 = 1790000000 -- 2026-09-21, a plausible reachedAt

-- ------------------------------------------------------------------ encode / decode
do
	eq(Highscore.SCALE, 2000000000, "the scale is 2e9, as designed")
	local v = Highscore.encode(7, T0, CAP)
	eq(v, 7 * 2000000000 + (2000000000 - T0), "value = caught * 2e9 + (2e9 - reachedAt)")
	eq(v % 1, 0, "the value is an integer (an OrderedDataStore rejects anything else)")
	local c, at = Highscore.decode(v, CAP)
	eq(c, 7, "decode gives the count back")
	eq(at, T0, "and the time it was reached")
	for _, n in { 1, 12, 23, 24 } do
		local cc, aa = Highscore.decode(Highscore.encode(n, T0 + n, CAP), CAP)
		truthy(cc == n and aa == T0 + n, "round trip at " .. n .. " types")
	end
	truthy(Highscore.encode(CAP, 1, CAP) < 2 ^ 53, "the largest value stays exact in a double (< 2^53)")
end

-- ------------------------------------------------------------------ ordering
do
	local function sorted(list)
		table.sort(list, function(a, b) return a.v > b.v end) -- GetSortedAsync(false, ...)
		return list
	end
	local rows = sorted({
		{ who = "late 10", v = Highscore.encode(10, T0 + 500, CAP) },
		{ who = "early 10", v = Highscore.encode(10, T0 + 5, CAP) },
		{ who = "any 11", v = Highscore.encode(11, T0 + 99999, CAP) },
		{ who = "early 9", v = Highscore.encode(9, T0 - 99999, CAP) },
	})
	eq(rows[1].who, "any 11", "more types caught ranks first, however late")
	eq(rows[2].who, "early 10", "among equal counts the one who got there FIRST ranks higher")
	eq(rows[3].who, "late 10", "then the later one")
	eq(rows[4].who, "early 9", "fewer types rank below, however early")
	truthy(Highscore.encode(1, 1, CAP) > Highscore.encode(0, 1, CAP), "one type beats none")
end

-- ------------------------------------------------------------------ the cap: nothing can show more than the catalog
do
	local c = Highscore.decode(Highscore.encode(99, T0, CAP), CAP)
	eq(c, CAP, "encode clamps a count above the catalog to the catalog's size")
	local c2 = Highscore.decode(99 * 2000000000 + 5, CAP)
	eq(c2, CAP, "decode clamps a FABRICATED stored value to the catalog's size")
	local c3 = Highscore.decode(1e15, CAP)
	eq(c3, CAP, "and an absurd one")
	local c4 = Highscore.decode(-5, CAP)
	eq(c4, 0, "a negative value decodes to nothing caught")
	local c5 = Highscore.decode(0 / 0, CAP)
	eq(c5, 0, "NaN decodes to nothing caught")
	eq(Highscore.decode(Highscore.encode(-3, T0, CAP), CAP), 0, "a negative count is clamped to 0")
	eq(Highscore.decode(Highscore.encode(5.7, T0, CAP), CAP), 5, "a fractional count is floored")
	local lo, hi = Highscore.range(CAP)
	eq(lo, 2000000000, "the board's query starts at one type caught")
	eq(hi, (CAP + 1) * 2000000000 - 1, "and ends at the catalog's size, with any tie-break")
	truthy(Highscore.encode(CAP, 1, CAP) <= hi and Highscore.encode(CAP, 2 ^ 31, CAP) <= hi, "every honest value is inside the range")
	truthy(Highscore.encode(1, T0, CAP) >= lo, "one type caught is inside it")
	truthy(99 * 2000000000 > hi, "a fabricated value above the cap is outside it, so the query leaves it out")
end

-- ------------------------------------------------------------------ time edge cases
do
	-- after 2033-05-18 (unix 2e9) the tie-break runs out: clamped at 0 so the count is never corrupted
	local c, at = Highscore.decode(Highscore.encode(4, 2100000000, CAP), CAP)
	eq(c, 4, "a reachedAt past 2e9 keeps the count intact")
	eq(at, 2000000000, "and reads back as the latest possible time")
	local c2 = Highscore.decode(Highscore.encode(4, -50, CAP), CAP)
	eq(c2, 4, "a nonsense early time keeps the count intact too")
	truthy(Highscore.encode(4, T0, CAP) < Highscore.encode(5, 2100000000, CAP), "no tie-break ever reaches into the next count")
end

-- ------------------------------------------------------------------ keys
do
	eq(Highscore.key(123456), "u_123456", "the key is u_<userId>")
	eq(Highscore.userIdFromKey("u_123456"), 123456, "and parses back")
	eq(Highscore.userIdFromKey("x_1"), nil, "a foreign key is ignored")
	eq(Highscore.userIdFromKey("u_abc"), nil, "a malformed one too")
	eq(Highscore.userIdFromKey(42), nil, "and a non-string")
end

-- Night shift 2026-10-09 (second review): nothing in code stopped a Studio playtest with API access on from writing
-- to the LIVE stores (profiles, best-day board, Field Guide board). Main now refuses in Studio unless
-- Config.Save.AllowStudio, which may only be set in an open place's Config, never in src/.
eq(Config.Save.AllowStudio, false, "Config.Save.AllowStudio is false in src (set it only in a Studio place)")

print(string.format("Highscore: %d passed, %d failed", passed, failed))
assert(failed == 0, "Highscore tests failed")
