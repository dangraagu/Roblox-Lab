-- Pure tests for Rng. Run: luau tests/Rng.spec.luau
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- determinism: same seed -> same sequence
do
	local a, b = Rng.new(42), Rng.new(42)
	local same = true
	for _ = 1, 100 do
		if a:next() ~= b:next() then same = false end
	end
	truthy(same, "same seed -> identical sequence")
end

-- different seeds -> (almost surely) different first value
do
	local a, b = Rng.new(1), Rng.new(2)
	truthy(a:next() ~= b:next(), "different seeds diverge")
end

-- next() in [0, 1)
do
	local within = true
	local a = Rng.new(7)
	for _ = 1, 1000 do
		local v = a:next()
		if v < 0 or v >= 1 then within = false end
	end
	truthy(within, "next() in [0,1)")
end

-- int() inclusive bounds + range
do
	local a = Rng.new(9)
	local lo, hi, within = false, false, true
	for _ = 1, 5000 do
		local v = a:int(1, 6)
		if v < 1 or v > 6 then within = false end
		if v == 1 then lo = true end
		if v == 6 then hi = true end
	end
	truthy(within, "int in [1,6]")
	truthy(lo and hi, "int hits both inclusive bounds")
	eq(Rng.new(3):int(5, 5), 5, "int(min==max) == min")
end

-- pick returns list members
do
	local a = Rng.new(11)
	local list = { "x", "y", "z" }
	local ok = true
	for _ = 1, 200 do
		local v = a:pick(list)
		if v ~= "x" and v ~= "y" and v ~= "z" then ok = false end
	end
	truthy(ok, "pick returns a member")
end

-- seed normalization: negative + float seeds are valid, non-negative state
do
	truthy(Rng.new(-5):next() >= 0, "negative seed normalises")
	truthy(Rng.new(3.9):next() >= 0, "float seed floors")
	local a, b = Rng.new(-5), Rng.new(-5)
	truthy(a:next() == b:next(), "negative seed still deterministic")
end

-- ---------------------------------------------------------------- Rng.below (high bits)
-- REGRESSION: Rng.int draws from the LCG's LOW-order bits (state % span). Low bits of an
-- LCG mod 2^32 have period <= 2^k, so an even/power-of-two span collapses the draw onto a
-- handful of the seed's lowest bits. Rng.below must derive from the HIGH bits instead.

-- in-range for n = 1, 2, 8 (power of two) and 24; never n+1, never 0
do
	for _, n in { 1, 2, 8, 24 } do
		local a = Rng.new(1234 + n)
		local within, sawOver, sawUnder = true, false, false
		for _ = 1, 20000 do
			local v = a:below(n)
			if v ~= math.floor(v) then within = false end
			if v > n then within = false; sawOver = true end
			if v < 1 then within = false; sawUnder = true end
		end
		truthy(within, "below(" .. n .. ") stays in [1, n] and is integral")
		truthy(not sawOver, "below(" .. n .. ") never returns n+1")
		truthy(not sawUnder, "below(" .. n .. ") never returns < 1")
	end
	eq(Rng.new(77):below(1), 1, "below(1) == 1")
end

-- hits EVERY value (no constant / collapsed output) for a power-of-two and a non-power range
do
	for _, n in { 2, 8, 24 } do
		local a = Rng.new(555)
		local seen, distinct = {}, 0
		for _ = 1, 20000 do
			local v = a:below(n)
			if not seen[v] then seen[v] = true; distinct += 1 end
		end
		eq(distinct, n, "below(" .. n .. ") hits all " .. n .. " values")
	end
end

-- deterministic per seed
do
	local a, b = Rng.new(31337), Rng.new(31337)
	local same = true
	for _ = 1, 500 do
		if a:below(8) ~= b:below(8) then same = false end
	end
	truthy(same, "below deterministic for a given seed")
end

-- THE SHIPPED BUG: seeds whose LOW BITS ARE ZERO (what the overflowing passSeed produced).
-- One draw from a FRESH Rng per seed. Rng.int(1,8) here yields ONE distinct value for every
-- such seed; Rng.below must still spread across the whole range.
do
	local seen, distinct = {}, 0
	for i = 1, 3000 do
		local v = Rng.new(i * 2048):below(8)
		if not seen[v] then seen[v] = true; distinct += 1 end
	end
	eq(distinct, 8, "below(8) varies across low-bits-zero seeds (i*2048)")

	-- and document the weakness it replaced, so the guard can't silently rot
	local ints, intDistinct = {}, 0
	for i = 1, 3000 do
		local v = Rng.new(i * 2048):int(1, 8)
		if not ints[v] then ints[v] = true; intDistinct += 1 end
	end
	eq(intDistinct, 1, "int(1,8) DOES collapse on low-bits-zero seeds (documents why below exists)")
end

-- rejects n < 1
do
	truthy(not (pcall(function() return Rng.new(1):below(0) end)), "below(0) asserts")
	truthy(not (pcall(function() return Rng.new(1):below(-3) end)), "below(-3) asserts")
end

-- pick now rides the high-bit path: a power-of-two-length list must not collapse
do
	local list = { "a", "b", "c", "d", "e", "f", "g", "h" }
	local seen, distinct = {}, 0
	for i = 1, 3000 do
		local v = Rng.new(i * 2048):pick(list)
		if not seen[v] then seen[v] = true; distinct += 1 end
	end
	eq(distinct, 8, "pick spreads over an 8-element list on low-bits-zero seeds")
end

print(string.format("Rng: %d passed, %d failed", passed, failed))
if failed > 0 then error("Rng tests failed") end
