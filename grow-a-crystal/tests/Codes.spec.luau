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
