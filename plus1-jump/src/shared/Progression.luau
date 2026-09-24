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

-- ── Høyde <-> progresjon (himmel-båndene i Sky.client leser disse) ─────────────
-- Tårnets geometri er helt bestemt av Config.Tower: etasje t starter på toppen av etasje t-1,
-- og hver av TilesPerTier plattformer ligger stepHeight(t) over den forrige. Så høyde og
-- "etasjer klatret" er samme tall i to enheter. tests/Altitude.spec.luau sjekker dette mot
-- TowerGen, og robloxemu/check_plus1_sky.luau mot Part-ene serveren faktisk bygger.

-- Studs fra sokkelen (BaseY) til toppen av etasje n. Lukket form (kalles hver frame).
function Progression.climbHeight(n: number, tw: any): number
	n = math.floor(math.max(n, 0))
	if n == 0 then return 0 end
	local spt = tw.StepPerTier
	local uncapped = n
	if spt > 0 then
		uncapped = math.min(n, math.max(0, math.floor((tw.StepMax - tw.StepMin) / spt) + 1))
	end
	local sum = uncapped * tw.StepMin + spt * uncapped * (uncapped - 1) / 2
	sum += (n - uncapped) * tw.StepMax
	return tw.TilesPerTier * sum
end

-- Etasjer klatret (kontinuerlig) i høyde y: (t-1) + i/TilesPerTier på plattform i i etasje t.
-- Under sokkelen og NaN gir 0.
function Progression.tierProgressAtY(y: number, tw: any): number
	local h = y - tw.BaseY
	if not (h > 0) then return 0 end
	if h == math.huge then return math.huge end
	local hi = 1
	while Progression.climbHeight(hi, tw) <= h and hi < 2 ^ 40 do
		hi *= 2
	end
	local lo = 0 -- invariant: climbHeight(lo) <= h < climbHeight(hi)
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if Progression.climbHeight(mid, tw) <= h then lo = mid else hi = mid end
	end
	local tierHeight = tw.TilesPerTier * Progression.stepHeight(lo + 1, tw)
	return lo + (h - Progression.climbHeight(lo, tw)) / tierHeight
end

-- Etasje-NUMMERET du står i ved gulv-høyde y (plattform-senter-høyde): 0 på sokkelen, t fra første
-- plattform i etasje t og opp til (ikke med) første plattform i etasje t+1. Samme tall som serveren
-- krediterer og HUD/topp-10 viser, så himmelens bånd-navn og «85 🚀» på tavla aldri er uenige.
function Progression.tierAtY(y: number, tw: any): number
	local p = Progression.tierProgressAtY(y, tw)
	local first = 1 / tw.TilesPerTier
	if not (p >= first - 1e-6) then return 0 end
	if p == math.huge then return math.huge end
	return math.floor(p - first + 1e-6) + 1
end

-- Invers av tierProgressAtY.
function Progression.yAtProgress(p: number, tw: any): number
	if not (p > 0) then return tw.BaseY end
	local n = math.floor(p)
	local frac = p - n
	return tw.BaseY + Progression.climbHeight(n, tw) + frac * tw.TilesPerTier * Progression.stepHeight(n + 1, tw)
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

-- Skal HUD-en fremheve REBIRTH-knappen? (review 2026-09-17) Rebirth sender deg til sokkelen, og med
-- hopp-taket og reachability-invarianten gjør den aldri klatringen raskere. En HUD som lyste opp hver
-- rebirth (10, 18, 26 …) tok en vanlig spiller vekk fra verdensrommet (46-226 min i stedet for 35).
-- Den FØRSTE fremheves (alle lærer at den finnes); senere er tilgjengelige men rolige til beste etasje
-- har nådd HighlightAgainAtBestTier (siste himmel-bånd). Serverens regler (canRebirth) er uendret.
function Progression.rebirthHighlighted(highestTier: number, bestTier: number, rebirthCount: number, rb: any): boolean
	if not Progression.canRebirth(highestTier, rebirthCount, rb) then return false end
	if rebirthCount < (rb.HighlightFirstRebirths or 0) then return true end
	return bestTier >= (rb.HighlightAgainAtBestTier or 0)
end

return Progression
