-- Codes.spec.luau — one-time code redemption. Run: luau tests/Codes.spec.luau
local Codes = require("../src/shared/Codes")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

eq(Codes.normalize("  ForK  "), "FORK", "normalize trims and uppercases")
eq(Codes.normalize("welcome"), "WELCOME", "normalize uppercases")

local ok, reward, reason = Codes.redeem("welcome", {}, Config.Codes)
eq(ok, true, "a valid code is accepted")
eq(reason, "ok", "...with reason ok")
eq(reward.skips, Config.Codes["WELCOME"].skips, "...and the configured reward")

eq((Codes.redeem("  fOrK ", {}, Config.Codes)), true, "codes are case-insensitive and trimmed")

local ok3, _, reason3 = Codes.redeem("NOTREAL", {}, Config.Codes)
eq(ok3, false, "an unknown code is rejected")
eq(reason3, "unknown", "...with reason unknown")

local ok4, _, reason4 = Codes.redeem("welcome", { WELCOME = true }, Config.Codes)
eq(ok4, false, "a redeemed code is rejected")
eq(reason4, "already", "...with reason already")

local ok5, _, reason5 = Codes.redeem("   ", {}, Config.Codes)
eq(ok5, false, "whitespace is rejected")
eq(reason5, "empty", "...with reason empty")

local ok6, _, reason6 = Codes.redeem(42, {}, Config.Codes)
eq(ok6, false, "a non-string payload is rejected rather than raising")
eq(reason6, "empty", "...with reason empty")

-- Read-only. A code check that mutated the redeemed set would make the server's atomic
-- redeem-and-flush impossible to reason about: the code would be spent before the write.
local set = {}
Codes.redeem("welcome", set, Config.Codes)
eq(next(set), nil, "redeem does not mark the code itself; the server does that inside its flush")

-- ...and it must not hand out a reference into Config either. The expected value is READ from
-- Config, not written out here: a spec that spells out a tunable turns red when somebody tunes it.
local originalSkips = Config.Codes["WELCOME"].skips
local _, r = Codes.redeem("welcome", {}, Config.Codes)
r.skips = 999
eq(Config.Codes["WELCOME"].skips, originalSkips, "the reward is a copy, not Config's own row")

-- Every configured code has to be worth something, or it is a code that reads as broken.
local empty = {}
for code, cfgReward in pairs(Config.Codes) do
	if (cfgReward.skips or 0) <= 0 then empty[#empty + 1] = code end
end
eq(#empty, 0, "every configured code grants at least one skip (" .. table.concat(empty, ",") .. ")")

-- CONTROL: adding a code the player has not redeemed changes nothing about the existing ones.
local extended = {}
for k, v in pairs(Config.Codes) do extended[k] = v end
extended["BRANDNEW"] = { skips = 3 }
local okA = Codes.redeem("welcome", {}, Config.Codes)
local okB = Codes.redeem("welcome", {}, extended)
eq(okA, okB, "CONTROL: adding a new code does not disturb an existing one")
truthy((Codes.redeem("brandnew", {}, extended)), "CONTROL: ...and the new code really is live")

print(string.format("Codes: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Codes.spec failed", 0)
end
