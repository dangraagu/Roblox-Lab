-- Rene logikk-tester for Contributors. Kjør med luau CLI:  luau tests/Contributors.spec.luau
-- (Ingen Roblox-API. Testene dekker den nye logikken: case-insensitiv match og
--  idempotent belønning. `has`/`list` mot den LIVE lista testes for tom-tilstand.)

local Contributors = require("../src/shared/Contributors")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- _matches: case-insensitiv match mot en injisert liste (både brukernavn + visningsnavn)
local L = { ["own-distribution6314"] = "Own-Distribution6314" }
eq(Contributors._matches("Own-Distribution6314", nil, L), true, "username match")
eq(Contributors._matches("OWN-DISTRIBUTION6314", nil, L), true, "case-insensitive username")
eq(Contributors._matches("someoneelse", "Own-Distribution6314", L), true, "displayname match")
eq(Contributors._matches("own-distribution6314", nil, {}), false, "empty list -> no match")
eq(Contributors._matches("nobody", "nobody", L), false, "unlisted -> no match")
eq(Contributors._matches(nil, nil, L), false, "nil-safe")

-- shouldReward: idempotens (én gang) + kun bidragsytere
eq(Contributors.shouldReward(true, {}), true, "contributor, no gift -> reward")
eq(Contributors.shouldReward(true, { contrib1 = true }), false, "already rewarded -> no")
eq(Contributors.shouldReward(true, { other = true }), true, "other gift only -> still reward")
eq(Contributors.shouldReward(false, {}), false, "not contributor -> no")
eq(Contributors.shouldReward(false, { contrib1 = true }), false, "not contributor, has flag -> no")
eq(Contributors.shouldReward(true, nil), true, "contributor, nil gifts -> reward")

-- REWARD-config sanity
eq(Contributors.REWARD.id, "contrib1", "reward id stable (matches gifts key)")
eq(type(Contributors.REWARD.coins), "number", "reward coins numeric")
eq(type(Contributors.REWARD.gems), "number", "reward gems numeric")

-- has / list mot den LIVE lista (tom til en hjelper legges inn)
eq(Contributors.has(nil), false, "nil player -> false")
eq(Contributors.has({ Name = "anyone", DisplayName = "anyone" }), false, "empty live list -> false")
eq(#Contributors.list(), 0, "live list empty initially")

print(string.format("Contributors: %d passed, %d failed", passed, failed))
assert(failed == 0, "Contributors tests failed")
