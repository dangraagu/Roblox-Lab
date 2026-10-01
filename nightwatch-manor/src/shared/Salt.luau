--!strict
-- Salt.luau — the generator the server plans every manor from. PURE (tests/Salt.spec.luau).
--
-- docs/complete-game-standard.md §1: a seed a player could memorise gets a server-only salt, and a salt on a 32-bit
-- seed that also drives visible geometry is not enough (fork-tower REVIEW-4). The manor IS visible geometry, and
-- Rng.luau is an LCG with 32 bits of state, so any seeding of it has at most 2^32 manors: a script that has seen the
-- foyer could try them all offline and read off the exit. So the server does not seed Rng at all. For every attempt at
-- a night it draws two fresh 32-bit halves from its own `Random` (Main.server.luau, never replicated) and plans from
-- Salt.new(a, b): two independent LCG streams (different multipliers), stepped together, combined and passed through
-- a 32-bit avalanche mix (murmur3's finaliser). 2^64 states; the LCGs' weak low bits never reach the output, and the
-- output is read through its HIGH bits anyway (`below`, as Rng.below).
--
-- The algorithm is public on purpose (it ships in ReplicatedStorage with Manor); the halves are the secret.
-- Same interface as Rng (`next`, `below`), so `Manor.plan` takes either.

local Salt = {}
Salt.__index = Salt

local HALF = 4294967296 -- 2^32
Salt.HALF = HALF

-- stream 1: Numerical Recipes; stream 2: Borland/Delphi. Both full-period mod 2^32 (c odd, a - 1 divisible by 4).
local A1, C1 = 1664525, 1013904223
local A2, C2 = 134775813, 1

-- (x * y) mod 2^32 for x, y in [0, 2^32), exact in doubles: split y into 16-bit halves.
local function mul32(x: number, y: number): number
	local lo = y % 65536
	local hi = (y - lo) / 65536
	return (x * lo + ((x * hi) % 65536) * 65536) % HALF
end

local function mix(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x85EBCA6B)
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = mul32(x, 0xC2B2AE35)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

export type Salt = typeof(setmetatable({} :: { s1: number, s2: number }, Salt))

function Salt.valid(a: any, b: any): boolean
	local function ok(v: any): boolean
		return type(v) == "number" and v == v and v % 1 == 0 and v >= 0 and v < HALF
	end
	return ok(a) and ok(b)
end

function Salt.new(a: number, b: number): Salt
	assert(Salt.valid(a, b), "Salt.new: each half must be a whole number in [0, 2^32)")
	return setmetatable({ s1 = a, s2 = b }, Salt)
end

-- Raw next step -> integer in [0, 2^32).
function Salt.step(self: Salt): number
	self.s1 = (A1 * self.s1 + C1) % HALF
	self.s2 = (mul32(A2, self.s2) + C2) % HALF
	return mix(bit32.bxor(self.s1, bit32.lrotate(self.s2, 16)))
end

-- Float in [0, 1).
function Salt.next(self: Salt): number
	return Salt.step(self) / HALF
end

-- Integer in [1, n], from the high bits (as Rng.below).
function Salt.below(self: Salt, n: number): number
	local hi = math.floor(n)
	assert(hi >= 1, "Salt.below: n must be >= 1")
	local v = math.floor(Salt.next(self) * hi) + 1
	if v > hi then
		v = hi
	elseif v < 1 then
		v = 1
	end
	return v
end

return Salt
