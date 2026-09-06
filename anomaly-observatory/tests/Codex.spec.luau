-- Pure tests for Codex (Field Guide set). Run: luau tests/Codex.spec.luau
local Codex = require("../src/shared/Codex")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function approx(a, b, msg)
	if math.abs(a - b) < 1e-9 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local set = {}
eq(Codex.count(set), 0, "empty count 0")
eq(Codex.completion(set, 24), 0, "empty completion 0")
eq(Codex.completion(set, 0), 0, "completion with total 0 -> 0 (no divide-by-zero)")

eq(Codex.discover(set, "figure_end"), true, "first discover is new")
eq(Codex.discover(set, "figure_end"), false, "second discover not new")
eq(Codex.has(set, "figure_end"), true, "has after discover")
eq(Codex.has(set, "nope"), false, "has false for unknown")
eq(Codex.count(set), 1, "count 1 after one discover")

Codex.discover(set, "door_extra")
Codex.discover(set, "lights_out")
eq(Codex.count(set), 3, "count 3")
approx(Codex.completion(set, 24), 3 / 24, "completion 3/24")

-- full completion
do
	local full = {}
	for i = 1, 5 do Codex.discover(full, "a" .. i) end
	approx(Codex.completion(full, 5), 1, "completion full = 1")
end

local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- --------------------------------------------------- REGRESSION: stale ids / over-100%
-- A returning player's persisted set can hold ids that a later catalog renamed or dropped.
-- count() counts them all, so an unclamped completion() read > 1.0 and the HUD showed
-- nonsense like "27/24".

-- completion is clamped at 1.0 when the set holds MORE ids than `total`
do
	local stale = {}
	for i = 1, 27 do Codex.discover(stale, "id_" .. i) end
	eq(Codex.count(stale), 27, "stale set counts all 27 persisted ids")
	truthy(Codex.count(stale) > 24, "set really is bigger than total (guard is not vacuous)")
	eq(Codex.completion(stale, 24), 1, "completion clamped to 1.0 when set > total")
	truthy(Codex.completion(stale, 24) <= 1, "completion never exceeds 1.0")
	eq(Codex.completion(stale, 1), 1, "completion clamped hard at 1.0")
end

-- countKnown filters ids the catalog no longer recognises
do
	local mixed = {}
	for _, id in { "figure_end", "door_extra", "lights_out", "OLD_removed", "OLD_renamed" } do
		Codex.discover(mixed, id)
	end
	local catalog = { figure_end = true, door_extra = true, lights_out = true, scope_gone = true }
	local isKnown = function(id: string): boolean
		return catalog[id] == true
	end

	eq(Codex.count(mixed), 5, "count() still counts stale ids (behaviour unchanged)")
	eq(Codex.countKnown(mixed, isKnown), 3, "countKnown drops the 2 unknown ids")
	approx(Codex.completion(mixed, 4, isKnown), 3 / 4, "completion with filter is honest 3/4")
	approx(Codex.completion(mixed, 4), 1, "completion without filter clamps 5/4 -> 1")

	-- an all-stale profile reads as 0, not as a bogus streak
	local allStale = { OLD_a = true, OLD_b = true }
	eq(Codex.countKnown(allStale, isKnown), 0, "countKnown 0 when every id is stale")
	eq(Codex.completion(allStale, 4, isKnown), 0, "completion 0 when every id is stale")
	eq(Codex.countKnown({}, isKnown), 0, "countKnown 0 on empty set")
end

-- clamping does not disturb the normal path
do
	local fresh = {}
	Codex.discover(fresh, "a")
	Codex.discover(fresh, "b")
	approx(Codex.completion(fresh, 24), 2 / 24, "normal completion unaffected by clamp")
	eq(Codex.completion(fresh, 2), 1, "exactly-complete still 1.0")
	eq(Codex.completion(fresh, -5), 0, "negative total -> 0")
end

print(string.format("Codex: %d passed, %d failed", passed, failed))
if failed > 0 then error("Codex tests failed") end
