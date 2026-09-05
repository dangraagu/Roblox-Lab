-- Rene tester for Geode (uke-bøtte + rotasjon). Kjør: luau tests/Geode.spec.luau
local Geode = require("../src/shared/Geode")
local Config = require("../src/shared/Config")

local gc = Config.Geode
local W = gc.WeekSeconds
local E = gc.Epoch

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- weekIndex
eq(Geode.weekIndex(E, gc), 0, "epoch = week 0")
eq(Geode.weekIndex(E + W, gc), 1, "one week later = week 1")
eq(Geode.weekIndex(E + 2 * W + 5, gc), 2, "mid week 2")
eq(Geode.weekIndex(E - 100, gc), 0, "before epoch clamped to 0")

-- exclusiveFor (rotation {4,5,6,5})
eq(Geode.exclusiveFor(E, gc), 4, "week0 -> 4")
eq(Geode.exclusiveFor(E + W, gc), 5, "week1 -> 5")
eq(Geode.exclusiveFor(E + 2 * W, gc), 6, "week2 -> 6")
eq(Geode.exclusiveFor(E + 3 * W, gc), 5, "week3 -> 5")
eq(Geode.exclusiveFor(E + 4 * W, gc), 4, "week4 wraps -> 4")

-- canCrack / crack
local p = { dust = 1000, lastGeodeWeek = -1 }
truthy(Geode.canCrack(p, E, gc), "fresh profile can crack")
local ok, reason, tier = Geode.crack(p, E, gc)
eq(ok, true, "crack ok"); eq(reason, "ok", "ok reason"); eq(tier, 4, "week0 exclusive tier 4")
eq(p.dust, 0, "geode cost spent"); eq(p.lastGeodeWeek, 0, "week recorded")
local ok2, r2 = Geode.crack(p, E, gc)
eq(ok2, false, "cannot crack twice same week"); eq(r2, "already", "already reason")
-- next week can crack again (if affordable)
p.dust = 1000
local ok3, r3, t3 = Geode.crack(p, E + W, gc)
eq(ok3, true, "next week crackable"); eq(t3, 5, "week1 exclusive tier 5")
-- poor
local pp = { dust = 500, lastGeodeWeek = -1 }
local okp, rp = Geode.crack(pp, E, gc)
eq(okp, false, "poor cannot crack"); eq(rp, "poor", "poor reason"); eq(pp.dust, 500, "dust unchanged")

print(string.format("Geode: %d passed, %d failed", passed, failed))
assert(failed == 0, "Geode tests failed")
