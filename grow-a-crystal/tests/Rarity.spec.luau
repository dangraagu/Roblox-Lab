-- Rene tester for Rarity (refraction-gacha). Kjør: luau tests/Rarity.spec.luau
local Rarity = require("../src/shared/Rarity")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local rc = Config.Refraction
local MAX = Config.MaxTier

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

-- upgradeChance
approx(Rarity.upgradeChance(1, 1, rc), 0.50, "tier1 base chance")
approx(Rarity.upgradeChance(2, 1, rc), 0.35, "tier2 base chance")
truthy(Rarity.upgradeChance(1, 2, rc) > Rarity.upgradeChance(1, 1, rc), "luck raises chance")
eq(Rarity.upgradeChance(1, 100, rc), rc.MaxChance, "chance clamped at MaxChance")
eq(Rarity.upgradeChance(MAX, 1, rc), 0, "top tier cannot upgrade")

-- luckMult
approx(Rarity.luckMult(0, Config.Boosters), 1, "luckMult level0 = 1")
approx(Rarity.luckMult(10, Config.Boosters), 1 + 10 * 0.15, "luckMult level10")

-- roll bounds: final in [seedTier, MAX], deterministic per rng seed
local within, det = true, true
for s = 1, 500 do
	local a = Rng.new(s)
	local f = Rarity.roll(1, 1, a, rc, MAX)
	if f < 1 or f > MAX then within = false end
	local b = Rng.new(s)
	if Rarity.roll(1, 1, b, rc, MAX) ~= f then det = false end
end
truthy(within, "roll stays in [seedTier, MAX]")
truthy(det, "roll deterministic given rng seed")

-- seedTier == MAX -> stays MAX
eq(Rarity.roll(MAX, 5, Rng.new(1), rc, MAX), MAX, "mythic seed stays mythic")

-- roll never below seedTier
local okFloor = true
for s = 1, 300 do
	if Rarity.roll(3, 1, Rng.new(s), rc, MAX) < 3 then okFloor = false end
end
truthy(okFloor, "final never below seedTier")

-- luck raises AVERAGE final tier (statistical, deterministic seeds)
local function avgFinal(luck, n)
	local sum = 0
	for s = 1, n do sum += Rarity.roll(1, luck, Rng.new(s * 7 + 3), rc, MAX) end
	return sum / n
end
truthy(avgFinal(3, 2000) > avgFinal(1, 2000), "higher luck -> higher average tier")

print(string.format("Rarity: %d passed, %d failed", passed, failed))
assert(failed == 0, "Rarity tests failed")
