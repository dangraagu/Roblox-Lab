--!strict
-- Ren progresjons-matte for +1 Jump. Ingen Roblox-avhengigheter, ingen globaler —
-- alle config-verdier sendes inn, så alt kan testes med luau-CLI.
--
-- Sentral korrektheten: REACHABILITY. Å tråkke en ny plattform gir +1 jump power.
-- StepHeight(t) må aldri overstige det en spiller UTEN rebirth kan hoppe når hen
-- ankommer etasje t. `maxSafeStep(t) >= stepHeight(t)` er invarianten testene vokter.

local Progression = {}

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- Hoppehøyde (studs) for gitt jump power + rebirth-multiplier.
function Progression.jumpHeight(jp: number, mult: number, jc: any): number
	return clamp(jc.BaseJump + jp * jc.JumpPerStep * mult, jc.BaseJump, jc.MaxJumpHeight)
end

-- Jump power en spiller UTEN rebirth har opptjent når hen ankommer START av etasje t
-- (= alle plattformer i etasje 1..t-1). Etasje 1 => 0.
function Progression.jumpPowerAtTierStart(t: number, tw: any): number
	return (t - 1) * tw.TilesPerTier
end

-- Vertikal stigning pr plattform på etasje t (clampet til taket).
function Progression.stepHeight(t: number, tw: any): number
	return clamp(tw.StepMin + (t - 1) * tw.StepPerTier, tw.StepMin, tw.StepMax)
end

-- Horisontal avstand pr plattform på etasje t (clampet — alltid liten/klarerbar).
function Progression.gap(t: number, tw: any): number
	return clamp(tw.GapMin + (t - 1) * tw.GapPerTier, tw.GapMin, tw.GapMax)
end

-- Største stigning en fersk (mult=1) spiller trygt kan klare når hen ankommer etasje t.
function Progression.maxSafeStep(t: number, tw: any, jc: any): number
	local jp = Progression.jumpPowerAtTierStart(t, tw)
	return tw.Safety * Progression.jumpHeight(jp, 1, jc)
end

-- Er etasje t klarerbar for en spiller uten rebirth? (invarianten)
function Progression.isTierReachable(t: number, tw: any, jc: any): boolean
	return Progression.stepHeight(t, tw) <= Progression.maxSafeStep(t, tw, jc)
end

-- Antall hindringer på etasje t.
function Progression.hazardCount(t: number, tw: any): number
	if t < tw.HazardStartTier then return 0 end
	local n = 1 + math.floor((t - tw.HazardStartTier) / tw.HazardEveryNTiers)
	return clamp(n, 0, tw.HazardMax)
end

-- Rebirth-multiplier for gitt antall rebirths (0 => 1x, ingen rebirth ennå).
function Progression.rebirthMultiplier(rebirthCount: number, rb: any): number
	if rebirthCount <= 0 then return 1 end
	local m = rb.Multipliers
	if rebirthCount <= #m then
		return m[rebirthCount]
	end
	-- Utover tabellen: siste multiplier vokser lineært (siste * 2, *3, ...).
	return m[#m] * (rebirthCount - #m + 1)
end

-- Hvilken etasje må nås for NESTE rebirth, gitt hvor mange man alt har.
function Progression.rebirthTierRequired(rebirthCount: number, rb: any): number
	return rb.FirstTierRequired + rebirthCount * rb.TierRequiredPerRebirth
end

-- Kan spilleren rebirthe nå?
function Progression.canRebirth(highestTier: number, rebirthCount: number, rb: any): boolean
	return highestTier >= Progression.rebirthTierRequired(rebirthCount, rb)
end

return Progression
