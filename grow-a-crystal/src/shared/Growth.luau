--!strict
-- Ren vekst-matte. Offline-vekst = differanse i tidsstempel (now - plantedAt); ingen
-- live-simulering trengs. Alt sendes inn, så testbart i luau-CLI.

local Growth = {}

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Growth-multiplier fra booster-nivå (høyere = raskere vekst).
function Growth.growthMult(growthLevel: number, boosterCfg: any): number
	return 1 + (growthLevel or 0) * boosterCfg.Growth.BasePerLevel
end

-- Effektive sekunder pr stadium for en seed av gitt tier, etter growth-multiplier.
function Growth.secondsPerStage(seedTier: number, gc: any, growthMult: number): number
	return gc.SecondsPerStage[seedTier] / growthMult
end

-- Antall FULLFØRTE stadier ved tidspunkt `now` (clampet til StageCount). dt<0 => 0.
function Growth.stagesElapsed(plantedAt: number, now: number, seedTier: number, gc: any, growthMult: number): number
	local dt = now - plantedAt
	if dt <= 0 then return 0 end
	local per = Growth.secondsPerStage(seedTier, gc, growthMult)
	return clamp(math.floor(dt / per), 0, gc.StageCount)
end

-- Moden = alle stadier fullført.
function Growth.isMature(plantedAt: number, now: number, seedTier: number, gc: any, growthMult: number): boolean
	return Growth.stagesElapsed(plantedAt, now, seedTier, gc, growthMult) >= gc.StageCount
end

-- Kontinuerlig fremdrift 0..1 (for UI-progressbar).
function Growth.progress(plantedAt: number, now: number, seedTier: number, gc: any, growthMult: number): number
	local dt = now - plantedAt
	if dt <= 0 then return 0 end
	local total = gc.SecondsPerStage[seedTier] / growthMult * gc.StageCount
	return clamp(dt / total, 0, 1)
end

-- Sekunder igjen til moden (0 om allerede moden), for UI-nedtelling.
function Growth.secondsToMature(plantedAt: number, now: number, seedTier: number, gc: any, growthMult: number): number
	local total = gc.SecondsPerStage[seedTier] / growthMult * gc.StageCount
	local left = (plantedAt + total) - now
	if left < 0 then return 0 end
	return left
end

return Growth
