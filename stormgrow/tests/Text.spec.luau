-- Spec for Text: the number and clock formats every toast and the HUD use. Run: luau tests/Text.spec.luau
local Text = require("../src/shared/Text")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

eq(Text.int(0), "0", "zero")
eq(Text.int(5), "5", "one digit")
eq(Text.int(999), "999", "three digits")
eq(Text.int(1000), "1,000", "a thousand gets a comma")
eq(Text.int(300000), "300,000", "the brag threshold")
eq(Text.int(11000000), "11,000,000", "the last band")
eq(Text.int(-1500), "-1,500", "a negative number keeps its sign")
eq(Text.int(12.7), "12", "a fraction is floored (coins are whole)")

eq(Text.short(950), "950", "short: under a thousand is exact")
eq(Text.short(1200), "1.2K", "short: thousands")
eq(Text.short(35000), "35K", "short: no .0")
eq(Text.short(1500000), "1.5M", "short: millions")
eq(Text.short(11000000), "11M", "short: 11M")
eq(Text.short(2.5e9), "2.5B", "short: billions")

eq(Text.clock(0), "0:00", "clock zero")
eq(Text.clock(12), "0:12", "clock seconds")
eq(Text.clock(72), "1:12", "clock minutes")
eq(Text.clock(12.2), "0:13", "clock rounds UP (never shows 0:00 while time is left)")
eq(Text.clock(3725), "62:05", "clock does not roll into hours")
eq(Text.clock(-3), "0:00", "clock never goes negative")

print(string.format("Text: %d passed, %d failed", passed, failed))
assert(failed == 0, "Text tests failed")
