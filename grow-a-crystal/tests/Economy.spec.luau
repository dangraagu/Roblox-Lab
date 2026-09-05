-- Rene tester for Economy. Kjør: luau tests/Economy.spec.luau
local Economy = require("../src/shared/Economy")
local Config = require("../src/shared/Config")

local ec = Config.Economy
local bc = Config.Boosters

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local function newProfile()
	return { dust = 0, seeds = {}, chambers = 1, luckLevel = 0, growthLevel = 0 }
end

-- harvestDust
eq(Economy.harvestDust(1, false, ec), 1, "shard dust")
eq(Economy.harvestDust(6, false, ec), 1500, "mythic dust")
eq(Economy.harvestDust(1, true, ec), 2, "doubleDust doubles")

-- sockets
eq(Economy.totalSockets(1, ec), 6, "1 chamber = 6 sockets")
eq(Economy.totalSockets(3, ec), 18, "3 chambers = 18 sockets")

-- seed shop unlock gating
truthy(Economy.seedShopUnlocked(1, 1, ec), "shard unlocked at 1 chamber")
truthy(not Economy.seedShopUnlocked(3, 1, ec), "amethyst locked at 1 chamber")
truthy(Economy.seedShopUnlocked(3, 2, ec), "amethyst unlocked at 2 chambers")
truthy(not Economy.seedShopUnlocked(6, 6, ec), "mythic locked at 6 chambers")
truthy(Economy.seedShopUnlocked(6, 7, ec), "mythic unlocked at 7 chambers")

-- chamber / booster cost curves
eq(Economy.chamberCost(1, ec), 500, "first extra chamber = base")
eq(Economy.chamberCost(2, ec), math.floor(500 * 2.2), "chamber cost grows")
eq(Economy.boosterCost(0, bc.Luck), 400, "booster lvl0 cost")
eq(Economy.boosterCost(1, bc.Luck), math.floor(400 * 1.8), "booster cost grows")

-- buySeed
local p = newProfile(); p.dust = 30
local ok, reason = Economy.buySeed(p, 1, ec)
eq(ok, true, "buy shard ok"); eq(p.dust, 20, "dust deducted"); eq(p.seeds[1], 1, "seed added")
local ok2, r2 = Economy.buySeed(p, 3, ec)
eq(ok2, false, "amethyst locked reject"); eq(r2, "locked", "locked reason")
local ok3, r3 = Economy.buySeed(p, 2, ec)
eq(ok3, false, "too poor for quartz"); eq(r3, "poor", "poor reason"); eq(p.dust, 20, "dust unchanged on fail")

-- buyChamber
local pc = newProfile(); pc.dust = 500
local okc = Economy.buyChamber(pc, ec)
eq(okc, true, "buy chamber ok"); eq(pc.chambers, 2, "chamber added"); eq(pc.dust, 0, "dust spent")
local okc2, rc2 = Economy.buyChamber(pc, ec)
eq(okc2, false, "poor chamber"); eq(rc2, "poor", "poor reason chamber")
local pmax = newProfile(); pmax.dust = 1e9; pmax.chambers = ec.MaxChambers
local okm, rm = Economy.buyChamber(pmax, ec)
eq(okm, false, "max chambers reject"); eq(rm, "max", "max reason")

-- buyBooster
local pb = newProfile(); pb.dust = 400
local okb = Economy.buyBooster(pb, "Luck", bc)
eq(okb, true, "buy luck ok"); eq(pb.luckLevel, 1, "luck level up"); eq(pb.dust, 0, "dust spent booster")
local oku, ru = Economy.buyBooster(pb, "Nope", bc)
eq(oku, false, "unknown booster"); eq(ru, "unknown", "unknown reason")
local pbm = newProfile(); pbm.dust = 1e9; pbm.growthLevel = bc.Growth.MaxLevel
local okmx, rmx = Economy.buyBooster(pbm, "Growth", bc)
eq(okmx, false, "growth maxed reject"); eq(rmx, "max", "booster max reason")

print(string.format("Economy: %d passed, %d failed", passed, failed))
assert(failed == 0, "Economy tests failed")
