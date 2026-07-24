--!strict
-- Perks (oppgraderinger) kjøpt med Mynter. Eies PERMANENT (kjøp én gang -> alltid
-- på). Effektene brukes pr spiller: fakkel/fart/skjold av serveren, minikart av
-- klienten. Priser i mynter. Ren data — brukes av server, klient og tester.

local Perks = {}

Perks.List = {
	{ id = "torch",   name = "Longer torch",  desc = "Bigger light around you.",            coinPrice = 300, torchBonus = 22 },
	{ id = "shield",  name = "Extra life",    desc = "Survive one hit per level (shield).", coinPrice = 600 },
	{ id = "speed",   name = "Speed boost",   desc = "Walk a little faster.",               coinPrice = 500, speedBonus = 3 },
	{ id = "minimap", name = "Minimap",       desc = "See a small map of the maze.",        coinPrice = 800 },
}

local index = {}
for _, p in ipairs(Perks.List) do
	index[p.id] = p
end

function Perks.byId(id)
	return index[id]
end

return Perks
