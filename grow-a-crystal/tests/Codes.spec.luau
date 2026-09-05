-- Rene tester for Codes. Kjør: luau tests/Codes.spec.luau
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

eq(Codes.normalize("  Crystal  "), "CRYSTAL", "normalize trims + uppercases")

local ok, reward, reason = Codes.redeem("welcome", {}, Config.Codes)
eq(ok, true, "valid code ok"); eq(reason, "ok", "ok reason")
eq(reward.dust, 100, "welcome dust reward")

local okG, rewardG = Codes.redeem("geode", {}, Config.Codes)
eq(okG, true, "geode code ok"); eq(rewardG.seedTier, 3, "geode grants seedTier 3")

local ok3, _, reason3 = Codes.redeem("NOPE", {}, Config.Codes)
eq(ok3, false, "unknown rejected"); eq(reason3, "unknown", "unknown reason")

local ok4, _, reason4 = Codes.redeem("welcome", { WELCOME = true }, Config.Codes)
eq(ok4, false, "already redeemed rejected"); eq(reason4, "already", "already reason")

local ok5, _, reason5 = Codes.redeem("   ", {}, Config.Codes)
eq(ok5, false, "empty rejected"); eq(reason5, "empty", "empty reason")

print(string.format("Codes: %d passed, %d failed", passed, failed))
assert(failed == 0, "Codes tests failed")
