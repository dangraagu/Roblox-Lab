--!strict
-- Spesielle spillere: får "gudemodus" (fly + gå gjennom vegger + udødelig) OG
-- start-gaven. Match på Roblox-BRUKERNAVN (Player.Name, unikt) ELLER visningsnavn
-- (Player.DisplayName), begge små bokstaver (robust mot store/små bokstaver).
-- Legg til flere navn i `names` ved behov.
--
-- MERK: visningsnavn er IKKE unikt — en fremmed kan sette samme visningsnavn og
-- få gudemodus. Greit for et lite venne-spill. Vil du være streng: match kun på
-- Player.Name (fjern DisplayName-sjekken under).

local GodUsers = {}

-- små bokstaver
local names = {
	miospille = true,   -- brukernavn (Player.Name)
	licyspille = true,  -- visningsnavn (Player.DisplayName)
}

function GodUsers.has(plr)
	if not plr then return false end
	if names[string.lower(plr.Name)] then return true end
	if plr.DisplayName and names[string.lower(plr.DisplayName)] then return true end
	return false
end

return GodUsers
