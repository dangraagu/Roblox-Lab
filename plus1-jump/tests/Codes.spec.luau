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

-- Night shift 2026-10-09 (second review): the trim pattern "^%s*(.-)%s*$" backtracks quadratically, and the server
-- passes the player's raw RemoteFunction string straight in. Measured in Studio: 20 000 spaces between two letters
-- took 1.37 s of server time (8 000: 0.22 s), so one call with a long string froze every player's server. A code is
-- short; anything this long is refused quickly and stays unknown.
do
	local evil = "a" .. string.rep(" ", 30000) .. "b"
	local t0 = os.clock()
	local n = Codes.normalize(evil)
	local dt = os.clock() - t0
	eq(dt < 0.05, true, string.format("a 30 000-space input normalizes in under 0.05 s (took %.3f s)", dt))
	eq(#n <= (Codes.MaxInput or 0), true, "and comes back no longer than Codes.MaxInput")
	local ok2, _, why = Codes.redeem(evil, {}, Config.Codes)
	eq(ok2, false, "a huge input redeems nothing")
	eq(why, "unknown", "and is simply an unknown code")
	eq(Codes.normalize("   welcome   "), "WELCOME", "a normal code with spaces still trims after the cap")
end

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
