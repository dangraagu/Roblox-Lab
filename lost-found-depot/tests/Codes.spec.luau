-- Codes.spec — code normalisation and the redeem decision. Run: luau tests/Codes.spec.luau
--
-- The code TABLE is not in this module and not in Config: it lives in src/server/Secret.luau,
-- which never replicates, so unreleased codes cannot be datamined before their article drops
-- (DESIGN.md §8.2). Here it is passed in, and the test builds its own.
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local TABLE = { SORTED = { cash = 250 }, SPRING = { cash = 100 } }

eq(Codes.normalize("  sorted "), "SORTED", "normalize uppercases and trims")
eq(Codes.normalize("SoRtEd"), "SORTED", "normalize is case-blind")

eq(Codes.redeem(Config, "   ", {}, TABLE).reason, "empty", "a blank code is empty")
eq(Codes.redeem(Config, nil, {}, TABLE).reason, "empty", "a nil code is empty")
eq(Codes.redeem(Config, 42, {}, TABLE).reason, "empty", "a number is not a code")
eq(Codes.redeem(Config, { "SORTED" }, {}, TABLE).reason, "empty", "a table is not a code")
eq(Codes.redeem(Config, string.rep("A", 21), {}, TABLE).reason, "long", "21 characters is over the cap")
eq(Codes.redeem(Config, string.rep("A", 20), {}, TABLE).reason, "unknown", "20 characters is allowed through to the lookup")
eq(Codes.redeem(Config, "NOPE", {}, TABLE).reason, "unknown", "an unknown code")

do
	local r = Codes.redeem(Config, " sorted", {}, TABLE)
	eq(r.ok, true, "SORTED redeems")
	eq(r.cash, 250, "... for 250 cash")
	eq(r.code, "SORTED", "... under its normalised name")
	r.cash = 99999
	eq(TABLE.SORTED.cash, 250, "the result is a copy; the table is untouched")
end

eq(Codes.redeem(Config, "SORTED", { SORTED = true }, TABLE).reason, "already", "an already-redeemed code")
eq(Codes.redeem(Config, "SPRING", { SORTED = true }, TABLE).ok, true, "a different code still redeems")
eq(Codes.redeem(Config, "sorted", {}, {}).reason, "unknown", "with an empty table nothing redeems")

print(string.format("Codes: %d passed, %d failed", passed, failed))
if failed > 0 then error("Codes tests failed") end
