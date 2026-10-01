-- Spec for Growth: ripeness on the server clock. Run: luau tests/Growth.spec.luau
--
-- Growth is stateless: a crop planted at `at` with grow time `grow` is ripe from at + grow on, so a crop
-- keeps growing while its owner is offline with no code at all (DESIGN.md §8.1). The server is strict; the
-- client shows "ripe" a little LATER, so every tap it offers is one the server accepts.
local Growth = require("../src/shared/Growth")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function approx(a, b, msg)
	if type(a) == "number" and math.abs(a - b) <= 1e-9 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

eq(Growth.isRipe(100, 100, 30), false, "not ripe the moment it is planted")
eq(Growth.isRipe(129.999, 100, 30), false, "not ripe a millisecond early")
eq(Growth.isRipe(130, 100, 30), true, "ripe exactly at at + grow (the server's strict rule)")
eq(Growth.isRipe(10000, 100, 30), true, "and forever after (offline growth needs no code)")

approx(Growth.stage(100, 100, 30), 0, "stage 0 at planting")
approx(Growth.stage(115, 100, 30), 0.5, "half grown half way")
approx(Growth.stage(200, 100, 30), 1, "stage caps at 1")
approx(Growth.stage(50, 100, 30), 0, "a planting time in the future reads as stage 0")

approx(Growth.remaining(112, 100, 30), 18, "18 s left")
approx(Growth.remaining(500, 100, 30), 0, "never negative")

eq(Growth.shownRipe(130, 100, 30, 0.25), false, "the client waits RipeLeadSeconds past the server's moment")
eq(Growth.shownRipe(130.25, 100, 30, 0.25), true, "then shows it ripe")
do
	-- every moment the client shows "ripe", the server accepts the tap (same clock)
	local bad = 0
	for i = 0, 2000 do
		local t = 100 + i * 0.037
		if Growth.shownRipe(t, 100, 30, 0.25) and not Growth.isRipe(t, 100, 30) then bad += 1 end
	end
	eq(bad, 0, "a crop the client shows ripe is always ripe on the server")
end

print(string.format("Growth: %d passed, %d failed", passed, failed))
assert(failed == 0, "Growth tests failed")
