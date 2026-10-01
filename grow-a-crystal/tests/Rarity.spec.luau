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

--=========================================================================== the roll's seed (review round 2)
-- The server used to seed each harvest's roll with (os.time()*1000 + socketId*977 + UserId) % M, all of which a
-- client knows (its State push carries `now`), so a script could wait for the second that rolls Mythic. The seed now
-- adds a SALT the server draws for each harvest from its own entropy-seeded Random, never saved and never sent.
-- These pin the pure half: the formula with salt 0 is the old one (the salt is the only change), every salt gives a
-- different seed, the seed stays an integer in [0, M) with every intermediate exact, and a uniform salt leaves the
-- odds exactly where Rarity.roll puts them.
local M = 2147483647
eq(Rarity.SEED_MOD, M, "the seed modulus is 2^31 - 1, as before")
if type(Rarity.rollSeed) ~= "function" then
	failed += 1
	print("FAIL:", "Rarity.rollSeed(now, socketId, userId, salt) exists")
else
	local now, uid = 1790800000, 4242424242
	eq(Rarity.rollSeed(now, 7, uid, 0), (now * 1000 + 7 * 977 + uid) % M, "salt 0 gives the old formula exactly")
	local seen, distinct = {}, 0
	for salt = 0, 999 do
		local s = Rarity.rollSeed(now, 7, uid, salt)
		if not seen[s] then seen[s] = true; distinct += 1 end
	end
	eq(distinct, 1000, "1000 different salts give 1000 different seeds for the same second, socket and player")
	local okRange = true
	for _, c in { { 0, 1, 1, 0 }, { 4102444800, 48, 9999999999, M - 1 }, { now, 48, uid, M - 1 }, { now, 1, 1, 123456789 } } do
		local s = Rarity.rollSeed(c[1], c[2], c[3], c[4])
		if s ~= math.floor(s) or s < 0 or s >= M then okRange = false end
		-- the largest intermediate (year 2100, the largest salt and a 10-digit UserId) stays exact
		if c[1] * 1000 + c[2] * 977 + c[3] + c[4] >= 2 ^ 53 then okRange = false end
	end
	truthy(okRange, "the seed is an integer in [0, M) and every intermediate stays under 2^53")

	-- the odds: exact tier probabilities from Rarity.upgradeChance, against 100 000 rolls with a uniform salt
	-- (a test-side LCG stands in for the server's Random) and 100 000 with the old unsalted formula, one second apart
	local function exact(seedTier: number, luck: number): { number }
		local p, carry = {}, 1
		for t = seedTier, MAX do
			local c = if t < MAX then Rarity.upgradeChance(t, luck, rc) else 0
			p[t] = carry * (1 - c)
			carry *= c
		end
		return p
	end
	local N = 100000
	local saltRng = Rng.new(20260930)
	for _, case in { { 1, 1, "Shard, luck 0" }, { 1, Rarity.luckMult(3, Config.Boosters), "Shard, luck 3" }, { 5, 1, "Legendary, luck 0" } } do
		local seedTier, luck, label = case[1], case[2], case[3]
		local p = exact(seedTier, luck)
		local salted, unsalted = {}, {}
		for i = 1, N do
			local salt = math.floor(saltRng:next() * M)
			local a = Rarity.roll(seedTier, luck, Rng.new(Rarity.rollSeed(now, 1 + i % 48, uid, salt)), rc, MAX)
			salted[a] = (salted[a] or 0) + 1
			local b = Rarity.roll(seedTier, luck, Rng.new(Rarity.rollSeed(now + i, 1 + i % 48, uid, 0)), rc, MAX)
			unsalted[b] = (unsalted[b] or 0) + 1
		end
		local worst, row = 0, {}
		for t = seedTier, MAX do
			local sd = math.sqrt(N * p[t] * (1 - p[t]))
			local zs = if sd > 0 then math.abs((salted[t] or 0) - N * p[t]) / sd else 0
			local zu = if sd > 0 then math.abs((unsalted[t] or 0) - N * p[t]) / sd else 0
			worst = math.max(worst, zs)
			table.insert(row, string.format("%s %.4f/%.4f/%.4f", Config.Tiers[t], p[t], (salted[t] or 0) / N, (unsalted[t] or 0) / N))
			truthy(zu <= 5, string.format("%s, %s: the OLD formula's rate is %.4f against %.4f exact (|z| %.1f, a sanity check of the method)", label, Config.Tiers[t], (unsalted[t] or 0) / N, p[t], zu))
		end
		print(string.format("  odds (exact / salted / old) %-18s %s", label, table.concat(row, "  ")))
		truthy(worst <= 5, string.format("%s: with a uniform salt every tier's rate is within 5 sd of the exact odds (worst |z| %.2f)", label, worst))
	end
end

print(string.format("Rarity: %d passed, %d failed", passed, failed))
assert(failed == 0, "Rarity tests failed")
