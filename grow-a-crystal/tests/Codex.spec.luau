-- Rene tester for Codex. Kjør: luau tests/Codex.spec.luau
local Codex = require("../src/shared/Codex")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg)
	if math.abs(a - b) < 1e-9 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local flags = {}
eq(Codex.discover(flags, 3), true, "first discovery is new")
eq(Codex.discover(flags, 3), false, "re-discovery not new")
truthy(Codex.has(flags, 3), "has after discover")
truthy(not Codex.has(flags, 4), "not has undiscovered")

Codex.discover(flags, 1)
Codex.discover(flags, 2)
eq(Codex.count(flags, 6), 3, "count = 3 of 6")
approx(Codex.completion(flags, 6), 0.5, "completion 0.5")

eq(Codex.count({}, 6), 0, "empty count 0")
approx(Codex.completion({}, 6), 0, "empty completion 0")

print(string.format("Codex: %d passed, %d failed", passed, failed))
assert(failed == 0, "Codex tests failed")
