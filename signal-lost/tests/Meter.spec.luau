-- Meter.spec — the SIGNAL meter (DESIGN.md §2.4): bars = clamp(5 - floor(d), 1, 5), where d is the
-- straight-line distance in modules between the centre of the module you are in and the relay's.
-- Run: luau tests/Meter.spec.luau
local Config = require("../src/shared/Config")
local Meter = require("../src/shared/Meter")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

for _, c in {
	{ 0, 5, "in the relay module: five bars" },
	{ 1, 4, "next to it: four" },
	{ math.sqrt(2), 4, "diagonal (1.41): four" },
	{ 2, 3, "two away: three" },
	{ 3, 2, "three away: two" },
	{ 3.99, 2, "just under four: two" },
	{ 4, 1, "four away: one bar" },
	{ math.sqrt(50), 1, "7.07 away: one bar" },
	{ 1e9, 1, "anywhere beyond: one bar, never zero" },
} do
	eq(Meter.bars(Config, c[1]), c[2], c[3])
end
eq(Meter.bars(Config, -3), 5, "a negative distance clamps to five")
eq(Meter.bars(Config, 0 / 0), 1, "NaN reads as far (one bar)")

-- distance between module ids on an n x n grid (id = y n + x + 1)
eq(Meter.distance(5, 1, 1), 0, "same module: 0")
eq(Meter.distance(5, 1, 2), 1, "one step along x")
eq(Meter.distance(5, 1, 6), 1, "one step along y")
truthy(math.abs(Meter.distance(5, 1, 7) - math.sqrt(2)) < 1e-12, "diagonal: sqrt 2")
eq(Meter.distance(6, 1, 36), math.sqrt(50), "corner to corner on 6x6: sqrt 50")
do
	local sym = true
	for n = 3, 6 do
		for a = 1, n * n do
			for b = 1, n * n do
				if Meter.distance(n, a, b) ~= Meter.distance(n, b, a) then sym = false end
				if Meter.bars(Config, Meter.distance(n, a, b)) ~= Meter.bars(Config, Meter.distance(n, b, a)) then sym = false end
			end
		end
	end
	truthy(sym, "distance and bars are symmetric")
end
eq(Meter.between(Config, 6, 8, 8), 5, "between(): the relay module itself reads five")
eq(Meter.between(Config, 6, 1, 36), 1, "between(): the far corner reads one")

print(string.format("Meter: %d passed, %d failed", passed, failed))
assert(failed == 0, "Meter tests failed")
