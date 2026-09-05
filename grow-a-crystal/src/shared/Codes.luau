--!strict
-- Ren innløsnings-logikk for koder. Ingen Roblox-avhengigheter — server kaller den,
-- CLI tester den. Muterer ingenting: returnerer resultat + belønning, kalleren lagrer.

local Codes = {}

-- Normaliser brukerens input: trim + store bokstaver, så "skyhigh" == " SkyHigh ".
function Codes.normalize(input: string): string
	return (string.upper((string.gsub(input, "^%s*(.-)%s*$", "%1"))))
end

-- Prøv å løse inn en kode.
--   input          : rå tekst fra spilleren
--   redeemed       : sett { [CODE]=true } over koder spilleren alt har brukt
--   codesTable     : Config.Codes ({ [CODE] = { jump = n } })
-- Returnerer: ok(boolean), reward(any?), reason(string)
--   reasons: "ok" | "empty" | "unknown" | "already"
function Codes.redeem(input: string, redeemed: { [string]: boolean }, codesTable: any): (boolean, any?, string)
	local code = Codes.normalize(input)
	if code == "" then
		return false, nil, "empty"
	end
	local reward = codesTable[code]
	if reward == nil then
		return false, nil, "unknown"
	end
	if redeemed[code] then
		return false, nil, "already"
	end
	return true, reward, "ok"
end

return Codes
