-- Seed.spec — the shift seed. Run: luau tests/Seed.spec.luau
--
-- DESIGN.md §7.1: seed = fmix(fmix(fmix(fmix(WorldSeed) xor (userId % 1000003)) xor shifts) xor salt).
-- Two traps from docs/new-game-checklist.md live here: "Seed overflow" (a double silently drops the
-- low bits of any product past 2^53) and "Replayable RNG" (consecutive raw seeds give the repo's
-- LCG nearly the same first draw, 99.8% of the time [M 0]).
local Seed = require("../src/shared/Seed")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local TWO32 = 4294967296

-- An independent exact 32-bit multiply: schoolbook on base-256 digits. Every intermediate here is
-- under 2^20, so it cannot lose a bit, and it shares no code with Seed.mul32's 16-bit halves.
local function refMul32(a: number, b: number): number
	local ad, bd = {}, {}
	for i = 1, 4 do
		ad[i] = (a // (256 ^ (i - 1))) % 256
		bd[i] = (b // (256 ^ (i - 1))) % 256
	end
	local col = { 0, 0, 0, 0 }
	for i = 1, 4 do
		for j = 1, 5 - i do
			col[i + j - 1] += ad[i] * bd[j]
		end
	end
	local out, carry = 0, 0
	for k = 1, 4 do
		local v = col[k] + carry
		out += (v % 256) * 256 ^ (k - 1)
		carry = v // 256
	end
	return out
end

local function refFmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = refMul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = refMul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

--============================================================ mul32 is exact

do
	local edges = { 0, 1, 2, 3, 255, 256, 65535, 65536, 65537, 0x7FFFFFFF, 0x80000000, 0x85EBCA6B,
		0xC2B2AE35, 0xFFFFFFFE, 0xFFFFFFFF }
	local bad = 0
	for _, a in edges do
		for _, b in edges do
			if Seed.mul32(a, b) ~= refMul32(a, b) then
				bad += 1
				if bad <= 3 then
					print(string.format("  mul32(%.0f, %.0f) = %.0f, exact %.0f", a, b, Seed.mul32(a, b), refMul32(a, b)))
				end
			end
		end
	end
	eq(bad, 0, "mul32 matches an exact 32-bit multiply on all " .. (#edges * #edges) .. " edge pairs")

	-- CONTROL: the naive product really is wrong at the top edge, so the comparison above can see
	-- the defect it is guarding against. (2^32-1)^2 mod 2^32 = 1.
	eq(refMul32(0xFFFFFFFF, 0xFFFFFFFF), 1, "CONTROL: the reference gets (2^32-1)^2 mod 2^32 right")
	truthy((0xFFFFFFFF * 0xFFFFFFFF) % TWO32 ~= 1, "CONTROL: a plain double multiply loses the low bits there")

	local rng = Rng.new(99)
	local randomBad = 0
	for _ = 1, 20000 do
		local a = Rng.step(rng)
		local b = Rng.step(rng)
		if Seed.mul32(a, b) ~= refMul32(a, b) then randomBad += 1 end
	end
	eq(randomBad, 0, "mul32 matches the exact multiply on 20,000 random pairs")
end

--============================================================ fmix is murmur3's finalizer

do
	local bad = 0
	local rng = Rng.new(7)
	for i = 0, 4999 do
		local x = if i < 100 then i else Rng.step(rng)
		if Seed.fmix(x) ~= refFmix(x) then bad += 1 end
	end
	eq(bad, 0, "fmix agrees with an independently built murmur3 fmix32 on 5,000 inputs")
	eq(Seed.fmix(0), 0, "fmix(0) = 0")
	eq(Seed.fmix(1), 0x514E28B7, "fmix(1) = 0x514E28B7, murmur3's published value")
end

--============================================================ forShift: range, determinism

do
	local out = 0
	local nonInt = 0
	local cases = {
		{ 1, 0, 0 }, { -1, 0, 0 }, { -2, 5, 123 }, -- Studio test players have negative ids
		{ 9007199254740991, 3, 0xFFFFFFFF }, -- the largest exact double as a user id
		{ 2 ^ 40 + 17, 1e6, 12345 }, -- Roblox ids exceed 2^32
		{ 123456789, 0, 0 },
	}
	for _, c in cases do
		local s = Seed.forShift(Config, c[1], c[2], c[3])
		if type(s) ~= "number" or s < 0 or s >= TWO32 then out += 1 end
		if type(s) == "number" and s % 1 ~= 0 then nonInt += 1 end
	end
	eq(out, 0, "every seed lands in [0, 2^32), negative and huge user ids included")
	eq(nonInt, 0, "every seed is an integer")

	eq(Seed.forShift(Config, 777, 4, 99), Seed.forShift(Config, 777, 4, 99), "same inputs, same seed")
	truthy(Seed.forShift(Config, 777, 4, 99) ~= Seed.forShift(Config, 777, 5, 99), "the next shift differs")
	truthy(Seed.forShift(Config, 777, 4, 99) ~= Seed.forShift(Config, 777, 4, 100), "a different salt differs")
	truthy(Seed.forShift(Config, 777, 4, 99) ~= Seed.forShift(Config, 778, 4, 99), "a different player differs")

	-- The formula, spelled out once from DESIGN.md §7.1 with the reference fmix, so a reordering of
	-- the xor chain (salt before shifts, say) is a failure rather than a silent change.
	local function refSeed(uid, shifts, salt)
		local h = refFmix(Config.WorldSeed % TWO32)
		h = refFmix(bit32.bxor(h, uid % 1000003))
		h = refFmix(bit32.bxor(h, shifts % TWO32))
		return refFmix(bit32.bxor(h, salt % TWO32))
	end
	local mismatch = 0
	local rng = Rng.new(3)
	for _ = 1, 2000 do
		local uid = Rng.step(rng) * 1000 + Rng.below(rng, 1000)
		local shifts = Rng.below(rng, 5000)
		local salt = Rng.step(rng)
		if Seed.forShift(Config, uid, shifts, salt) ~= refSeed(uid, shifts, salt) then mismatch += 1 end
	end
	eq(mismatch, 0, "forShift is exactly the DESIGN.md 7.1 chain on 2,000 random inputs")
end

--============================================================ the cart's own seeds

-- REVIEW-1 pass 3, exploit finding 3. The whole shift came from ONE 32-bit LCG state, and the tray
-- a client can read pins it down: a brute force found the seed in 18 s and predicted the 22 cart
-- items. The cart now comes from two more 32-bit keys the tray never touches: item n's own seed is
-- fmix(fmix(k1 xor n) xor k2).
do
	eq(type(Seed.cartSeeds), "function", "Seed.cartSeeds exists")
	if type(Seed.cartSeeds) == "function" then
		local a = Seed.cartSeeds(Config, 123456789, 987654321)
		local count, distinct, inRange = 0, {}, true
		local nDistinct = 0
		for n = Config.Shift.TraySlots + 1, Config.Shift.Items do
			local v = a[n]
			count += 1
			if type(v) ~= "number" or v < 0 or v >= TWO32 or v % 1 ~= 0 then inRange = false end
			if v ~= nil and not distinct[v] then
				distinct[v] = true
				nDistinct += 1
			end
		end
		eq(count, Config.Shift.Items - Config.Shift.TraySlots, "one seed per cart item")
		eq(a[Config.Shift.TraySlots], nil, "... and none for a tray item")
		truthy(inRange, "every cart seed is a 32-bit integer")
		eq(nDistinct, count, "every cart item gets a different seed")
		eq(a[9], refFmix(bit32.bxor(refFmix(bit32.bxor(123456789, 9)), 987654321)), "item 9's seed is fmix(fmix(k1 xor 9) xor k2)")
		local b = Seed.cartSeeds(Config, 123456789, 987654322)
		local c = Seed.cartSeeds(Config, 123456790, 987654321)
		local sameB, sameC = 0, 0
		for n = Config.Shift.TraySlots + 1, Config.Shift.Items do
			if a[n] == b[n] then sameB += 1 end
			if a[n] == c[n] then sameC += 1 end
		end
		eq(sameB, 0, "changing k2 changes every cart seed")
		eq(sameC, 0, "changing k1 changes every cart seed")
	end
end

--============================================================ consecutive shifts do not repeat

do
	-- [M 0]: raw consecutive seeds repeat the first letter 99.8% of the time; hashed, 24.4%, against
	-- 25.0% for independent draws. Asserted to 25% +- 1.5% over 20,000 consecutive shifts.
	local N = 20000
	local same, prev = 0, nil
	for shift = 0, N do
		local letter = Rng.below(Rng.new(Seed.forShift(Config, 123456, shift, 987654321)), 4)
		if prev ~= nil and letter == prev then same += 1 end
		prev = letter
	end
	local rate = same / N
	print(string.format("  hashed first letter repeats on %.2f%% of consecutive shifts", rate * 100))
	truthy(math.abs(rate - 0.25) <= 0.015, "hashed first letter repeats 25% +- 1.5% of the time")

	-- CONTROL: the unhashed seed really does repeat, so this measurement can tell the two apart.
	local rawSame, rawPrev = 0, nil
	for shift = 0, N do
		local letter = Rng.below(Rng.new(123456 * 4096 + shift), 4)
		if rawPrev ~= nil and letter == rawPrev then rawSame += 1 end
		rawPrev = letter
	end
	truthy(rawSame / N > 0.9, string.format("CONTROL: raw consecutive seeds repeat (%.1f%%)", rawSame / N * 100))
end

print(string.format("Seed: %d passed, %d failed", passed, failed))
if failed > 0 then error("Seed tests failed") end
