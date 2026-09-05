--!strict
-- Ren ukentlig Geode-logikk. `now` (unix-tid) sendes inn, så testbart uten Roblox.
-- Uke-bøtte = floor((now - Epoch)/WeekSeconds); roterende garantert eksklusiv gem.

local Geode = {}

-- Hvilken uke-indeks er `now` i? (>=0; før epoch clampes til 0)
function Geode.weekIndex(now: number, gc: any): number
	local w = math.floor((now - gc.Epoch) / gc.WeekSeconds)
	if w < 0 then return 0 end
	return w
end

-- Hvilken eksklusiv tier gir denne ukens Geode?
function Geode.exclusiveFor(now: number, gc: any): number
	local w = Geode.weekIndex(now, gc)
	local idx = (w % #gc.Rotation) + 1
	return gc.Rotation[idx]
end

-- Kan spilleren knuse en Geode nå? (én pr uke; profile.lastGeodeWeek lagres)
function Geode.canCrack(profile: any, now: number, gc: any): boolean
	return (profile.lastGeodeWeek or -1) ~= Geode.weekIndex(now, gc)
end

-- Prøv å knuse ukens Geode. Returnerer ok(boolean), reason(string), tier(number?).
-- reasons: "ok" | "already" | "poor"
function Geode.crack(profile: any, now: number, gc: any): (boolean, string, number?)
	if not Geode.canCrack(profile, now, gc) then
		return false, "already", nil
	end
	if profile.dust < gc.CostDust then
		return false, "poor", nil
	end
	profile.dust -= gc.CostDust
	profile.lastGeodeWeek = Geode.weekIndex(now, gc)
	return true, "ok", Geode.exclusiveFor(now, gc)
end

return Geode
