--!strict
-- Bidragsytere: spillere som har hjulpet med content (skjermbilder / klipp /
-- feedback som FAKTISK ble brukt i markedsføringen) belønnes I SPILLET.
--
-- Match på Roblox-BRUKERNAVN (Player.Name, unikt) ELLER visningsnavn
-- (Player.DisplayName), begge små bokstaver — samme mønster som GodUsers.
--
-- SLIK LEGGER DU TIL EN HJELPER: når bidraget deres er tatt i bruk, legg
-- brukernavnet (små bokstaver) inn i `names` under, med visningsnavnet som verdi
-- (det som vises på "Bidragsytere"-tavla i lobbyen). Da får de neste gang de blir
-- med: en engangs-bonus (mynter + edelstener) OG navnet sitt permanent på tavla.

local Contributors = {}

-- Engangs-belønning. Serveren sjekker `d.gifts[REWARD.id]` for idempotens (gis én
-- gang, som start-gaven). Moderat — nok til å kjøpe temaer/perks, ikke gud-nivå.
Contributors.REWARD = { id = "contrib1", coins = 25000, gems = 2500 }

-- små bokstaver. TOM til en hjelpers bidrag faktisk er brukt.
-- Format:  ["brukernavn"] = "Visningsnavn til tavla",
local names: { [string]: string } = {
	-- ["owndistribution6314"] = "Own-Distribution6314",  -- eksempel: fyll inn ved bruk
}

-- Ren match-logikk (case-insensitiv) mot en gitt liste. Eksponert for tester.
local function matches(name: any, display: any, list: { [string]: string }): boolean
	if type(name) == "string" and list[string.lower(name)] then return true end
	if type(display) == "string" and list[string.lower(display)] then return true end
	return false
end
Contributors._matches = matches

-- Er spilleren en bidragsyter? (brukernavn ELLER visningsnavn, små bokstaver)
function Contributors.has(plr: any): boolean
	if not plr then return false end
	return matches(plr.Name, plr.DisplayName, names)
end

-- Navn til credits-tavla (visningsnavn, alfabetisk). Tom = ingen ennå.
function Contributors.list(): { string }
	local out = {}
	for _, display in pairs(names) do
		out[#out + 1] = display
	end
	table.sort(out)
	return out
end

-- Ren beslutning: skal engangs-belønningen gis? (bidragsyter + ikke gitt før).
function Contributors.shouldReward(isContributor: boolean, gifts: any): boolean
	if not isContributor then return false end
	if type(gifts) == "table" and gifts[Contributors.REWARD.id] then return false end
	return true
end

return Contributors
