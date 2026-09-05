--!strict
-- Bitte-liten deterministisk PRNG (LCG). Ren Luau — samme sekvens i Studio OG i
-- luau-CLI (Roblox' `Random` finnes ikke i CLI-tester). Brukes så tårn-genereringen
-- kan enhets-testes og er identisk for alle spillere.
--
-- Numerical Recipes LCG-konstantar (mod 2^32). Vi holder tilstanden i [0, 2^32).

local Rng = {}
Rng.__index = Rng

local MOD = 4294967296 -- 2^32
local A = 1664525
local C = 1013904223

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

-- Seed normaliseres til et ikke-negativt heltall < 2^32.
function Rng.new(seed: number): Rng
	local s = math.floor(seed) % MOD
	if s < 0 then s += MOD end
	return setmetatable({ state = s }, Rng)
end

-- Rått neste steg -> heltall i [0, 2^32).
function Rng.step(self: Rng): number
	self.state = (A * self.state + C) % MOD
	return self.state
end

-- Flyttall i [0, 1).
function Rng.next(self: Rng): number
	return Rng.step(self) / MOD
end

-- Heltall i [min, max] inklusivt. Krever min <= max.
function Rng.int(self: Rng, min: number, max: number): number
	assert(min <= max, "Rng.int: min > max")
	local span = max - min + 1
	return min + (Rng.step(self) % span)
end

-- Plukk ett element fra en ikke-tom liste.
function Rng.pick(self: Rng, list: { any }): any
	assert(#list > 0, "Rng.pick: empty list")
	return list[Rng.int(self, 1, #list)]
end

return Rng
