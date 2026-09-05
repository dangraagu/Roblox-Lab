--!strict
-- Ren refraction-logikk (gacha-kjernen). Ingen Roblox-avhengigheter — tar en rng inn
-- (Rng-modulen) så den er deterministisk + testbar i luau-CLI. Server lager en fersk
-- rng pr plante så hver innhøsting er et nytt sjansespill.

local Rarity = {}

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Sjanse for å klatre ETT hakk opp fra `fromTier`, gitt luck-multiplier. Clampet til
-- MaxChance så et enkelt steg aldri blir sikkert. Tier uten oppføring (Mythic) = 0.
function Rarity.upgradeChance(fromTier: number, luckMult: number, rc: any): number
	local base = rc.UpgradeChance[fromTier]
	if not base then return 0 end
	return clamp(base * luckMult, 0, rc.MaxChance)
end

-- Rull endelig rarity: start på seedTier, klatre ett hakk om gangen så lenge rullen
-- treffer, stopp ved første bom eller ved maxTier. Returnerer finalTier (>= seedTier).
function Rarity.roll(seedTier: number, luckMult: number, rng: any, rc: any, maxTier: number): number
	local final = seedTier
	while final < maxTier do
		local chance = Rarity.upgradeChance(final, luckMult, rc)
		if rng:next() < chance then
			final += 1
		else
			break
		end
	end
	return final
end

-- luckMult fra booster-nivå (rent, for server + test).
function Rarity.luckMult(luckLevel: number, boosterCfg: any): number
	return 1 + (luckLevel or 0) * boosterCfg.Luck.BasePerLevel
end

return Rarity
