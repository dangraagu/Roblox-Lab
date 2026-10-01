-- Spec for Day: which Door it is, when the next one opens. Run: luau tests/Day.spec.luau
--
-- The day is UTC and the Door number counts from Door #1 on 2026-09-30 (dayIndex 20726, computed
-- with Python's datetime). Everything here is pure arithmetic on os.time()-style unix seconds.
local Day = require("../src/shared/Day")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local cfg = Config.Day

-- 2026-09-30 00:00:00 UTC = 20726 * 86400 = 1790726400 (written out, not recomputed from the module)
local D1 = 1790726400
eq(Day.index(D1, cfg), 20726, "2026-09-30 00:00 UTC is day 20726")
eq(Day.index(D1 + 86399, cfg), 20726, "one second before midnight is still day 20726")
eq(Day.index(D1 + 86400, cfg), 20727, "midnight UTC starts day 20727")
eq(Day.index(D1 - 1, cfg), 20725, "one second earlier is the day before")
eq(Day.doorNumber(20726, cfg), 1, "2026-09-30 is Door #1")
eq(Day.doorNumber(20727, cfg), 2, "the next day is Door #2")

eq(Day.secondsToNext(D1, cfg), 86400, "at midnight the next Door is a whole day away")
eq(Day.secondsToNext(D1 + 86399, cfg), 1, "one second before midnight: 1 s to go")
eq(Day.secondsToNext(D1 + 3600 * 5 + 61, cfg), 86400 - 18061, "mid-morning")

eq(Day.clock(0), "00:00:00", "clock formats zero")
eq(Day.clock(3661), "01:01:01", "clock formats h:m:s with zero padding")
eq(Day.clock(86399), "23:59:59", "the largest countdown")
eq(Day.clock(-5), "00:00:00", "a negative countdown clamps to zero")

eq(Day.recordKey(20726), "d_20726", "the Days store key")
eq(Day.boardScope(20726), "d20726", "the board scope")
truthy(#Day.recordKey(99999999) <= 50, "a DataStore key stays within 50 characters")

-- fractional and junk input never produce a fractional or NaN day
eq(Day.index(D1 + 0.75, cfg), 20726, "fractional seconds floor into the day")
eq(Day.index(0 / 0, cfg), 0, "NaN time is day 0 (fails closed: no record exists for day 0)")

print(string.format("Day: %d passed, %d failed", passed, failed))
if failed > 0 then error("Day spec failed", 0) end
