-- Rene tester for Codes. Kjør: luau tests/Codes.spec.luau
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- normalize
eq(Codes.normalize("  SkyHigh  "), "SKYHIGH", "normalize trims + uppercases")
eq(Codes.normalize("welcome"), "WELCOME", "normalize uppercases")

-- gyldig innløsning
local ok, reward, reason = Codes.redeem("welcome", {}, Config.Codes)
eq(ok, true, "valid code ok")
eq(reason, "ok", "valid reason ok")
eq(reward.jump, Config.Codes["WELCOME"].jump, "reward payload correct")

-- case-insensitiv
local ok2 = Codes.redeem("  sKyHiGh ", {}, Config.Codes)
eq(ok2, true, "case-insensitive + trimmed")

-- ukjent kode
local ok3, _, reason3 = Codes.redeem("NOTREAL", {}, Config.Codes)
eq(ok3, false, "unknown rejected")
eq(reason3, "unknown", "unknown reason")

-- allerede innløst
local ok4, _, reason4 = Codes.redeem("welcome", { WELCOME = true }, Config.Codes)
eq(ok4, false, "already redeemed rejected")
eq(reason4, "already", "already reason")

-- tom
local ok5, _, reason5 = Codes.redeem("   ", {}, Config.Codes)
eq(ok5, false, "empty rejected")
eq(reason5, "empty", "empty reason")

print(string.format("Codes: %d passed, %d failed", passed, failed))
assert(failed == 0, "Codes tests failed")
