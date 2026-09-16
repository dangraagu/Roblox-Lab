--!strict
-- Tiny deterministic PRNG (LCG). Pure Luau — same sequence in Studio AND in the
-- luau-CLI (Roblox's `Random` does not exist in the CLI tests). Used so the anomaly
-- roll can be unit-tested and is reproducible per (player, pass).
--
-- Numerical Recipes LCG constants (mod 2^32). State kept in [0, 2^32).

local Rng = {}
Rng.__index = Rng

local MOD = 4294967296 -- 2^32
local A = 1664525
local C = 1013904223

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

-- Seed normalised to a non-negative integer < 2^32.
function Rng.new(seed: number): Rng
	local s = math.floor(seed) % MOD
	if s < 0 then s += MOD end
	return setmetatable({ state = s }, Rng)
end

-- Raw next step -> integer in [0, 2^32).
function Rng.step(self: Rng): number
	self.state = (A * self.state + C) % MOD
	return self.state
end

-- Float in [0, 1).
function Rng.next(self: Rng): number
	return Rng.step(self) / MOD
end

-- Integer in [1, n] inclusive, derived from the HIGH-order bits of the state.
--
-- PREFER THIS over `Rng.int` for small ranges (and ALWAYS for power-of-two ranges):
-- it goes through `Rng.next` (state / 2^32), so the value is decided by the state's
-- most-significant bits, which have the full period of the generator. See the warning
-- on `Rng.int` below for why the modulo path is unsafe here.
--
-- `n` is floored, must be >= 1, and the result is clamped so a float rounding artefact
-- (next() * n rounding up to exactly n) can never return n + 1.
function Rng.below(self: Rng, n: number): number
	local hi = math.floor(n)
	assert(hi >= 1, "Rng.below: n must be >= 1")
	local v = math.floor(Rng.next(self) * hi) + 1
	if v > hi then
		v = hi
	elseif v < 1 then
		v = 1
	end
	return v
end

-- Integer in [min, max] inclusive. Requires min <= max.
--
-- WARNING — LOW-BIT WEAKNESS. This draws from the LOW-order bits of the LCG
-- (`state % span`). In an LCG mod 2^32 the low k bits have period at most 2^k, so when
-- `span` is even — catastrophically when it is a power of two — the result is decided by
-- only the lowest few bits and is patterned/short-cycled, NOT uniform. Worse, it is then a
-- pure function of the seed's low bits: seeds sharing low bits (e.g. every seed produced by
-- a computation that overflowed 2^53 and lost its low bits to zero) return the SAME value
-- forever. Kept as-is only for backwards compatibility with existing callers.
-- For small and/or power-of-two ranges use `Rng.below` instead.
function Rng.int(self: Rng, min: number, max: number): number
	assert(min <= max, "Rng.int: min > max")
	local span = max - min + 1
	return min + (Rng.step(self) % span)
end

-- Pick one element from a non-empty list. Uses the high-bit `Rng.below` path, because a
-- list length that is a power of two would otherwise hit the `Rng.int` weakness above.
-- Still consumes exactly ONE draw.
function Rng.pick(self: Rng, list: { any }): any
	assert(#list > 0, "Rng.pick: empty list")
	return list[Rng.below(self, #list)]
end

return Rng
