--!strict
-- Ren økonomi-logikk. Server-autoritativ: hver kjøps-funksjon validerer og muterer
-- profilen KUN ved suksess (som maze ShopService). Ingen Roblox-avhengigheter.
--
-- Profil-felt brukt her: dust (number), seeds ({[tier]=count}), chambers (number),
-- luckLevel (number), growthLevel (number).

local Economy = {}

local function floor(x: number): number
	return math.floor(x)
end

-- Dust for å høste en krystall av FINAL (etter-refraksjon) tier.
function Economy.harvestDust(finalTier: number, doubleDust: boolean, ec: any): number
	local base = ec.DustValue[finalTier] or 0
	return base * (doubleDust and 2 or 1)
end

-- Totalt antall sokler gitt antall kamre.
function Economy.totalSockets(chambers: number, ec: any): number
	return chambers * ec.SocketsPerChamber
end

-- Er en seed-tier låst opp i butikken gitt antall kamre?
function Economy.seedShopUnlocked(seedTier: number, chambers: number, ec: any): boolean
	local need = ec.SeedShopUnlockedByChamber[seedTier]
	if not need then return false end
	return chambers >= need
end

-- Kostnad for NESTE kammer når du eier `chambers` nå.
function Economy.chamberCost(chambers: number, ec: any): number
	return floor(ec.ChamberBaseCost * (ec.ChamberGrowth ^ (chambers - 1)))
end

-- Kostnad for å heve en booster fra nåværende `level` til level+1.
function Economy.boosterCost(level: number, def: any): number
	return floor(def.BaseCost * (def.CostGrowth ^ level))
end

-- Kjøp én seed av base-tier. Returnerer ok(boolean), reason(string).
-- reasons: "ok" | "locked" | "poor"
function Economy.buySeed(profile: any, seedTier: number, ec: any): (boolean, string)
	if not Economy.seedShopUnlocked(seedTier, profile.chambers, ec) then
		return false, "locked"
	end
	local cost = ec.SeedCost[seedTier]
	if not cost or profile.dust < cost then
		return false, "poor"
	end
	profile.dust -= cost
	profile.seeds[seedTier] = (profile.seeds[seedTier] or 0) + 1
	return true, "ok"
end

-- Kjøp ett kammer. reasons: "ok" | "max" | "poor"
function Economy.buyChamber(profile: any, ec: any): (boolean, string)
	if profile.chambers >= ec.MaxChambers then
		return false, "max"
	end
	local cost = Economy.chamberCost(profile.chambers, ec)
	if profile.dust < cost then
		return false, "poor"
	end
	profile.dust -= cost
	profile.chambers += 1
	return true, "ok"
end

-- Kjøp ett booster-nivå. kind = "Luck" | "Growth". reasons: "ok" | "max" | "poor" | "unknown"
function Economy.buyBooster(profile: any, kind: string, bc: any): (boolean, string)
	local def = bc[kind]
	if not def then return false, "unknown" end
	local key = (kind == "Luck") and "luckLevel" or "growthLevel"
	local level = profile[key] or 0
	if level >= def.MaxLevel then
		return false, "max"
	end
	local cost = Economy.boosterCost(level, def)
	if profile.dust < cost then
		return false, "poor"
	end
	profile.dust -= cost
	profile[key] = level + 1
	return true, "ok"
end

return Economy
