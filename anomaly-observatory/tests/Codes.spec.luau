-- Pure tests for Codes (one-time redemption). Run: luau tests/Codes.spec.luau
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- normalize
eq(Codes.normalize("  welcome "), "WELCOME", "normalize upper + trim")
eq(Codes.normalize("Eclipse"), "ECLIPSE", "normalize case")

-- empty
eq(Codes.redeem("   ", {}, Config).reason, "empty", "blank code -> empty")

-- unknown
eq(Codes.redeem("NOPE", {}, Config).reason, "unknown", "unknown code")

-- valid, not yet redeemed
do
	local r = Codes.redeem("welcome", {}, Config)
	eq(r.ok, true, "welcome ok")
	eq(r.reward.hintTokens, 3, "welcome grants 3 hint tokens")
end

-- tint reward
do
	local r = Codes.redeem("ECLIPSE", {}, Config)
	eq(r.ok, true, "eclipse ok")
	eq(r.reward.tint, "gold", "eclipse grants gold tint")
end

-- already redeemed
do
	local redeemed = { WELCOME = true }
	eq(Codes.redeem("WELCOME", redeemed, Config).reason, "already", "already redeemed")
end

-- reward is a copy: mutating it must not touch Config
do
	local r = Codes.redeem("WELCOME", {}, Config)
	r.reward.hintTokens = 9999
	eq(Config.Codes.WELCOME.hintTokens, 3, "reward is a copy, Config untouched")
end

print(string.format("Codes: %d passed, %d failed", passed, failed))
if failed > 0 then error("Codes tests failed") end
