--!strict
-- Perks (oppgraderinger) kjøpt med Mynter. Eies PERMANENT (kjøp én gang -> alltid
-- på). Effektene brukes pr spiller: fakkel/fart/skjold av serveren, minikart av
-- klienten. Priser i mynter. Ren data — brukes av server, klient og tester.

local Perks = {}

Perks.List = {
	{ id = "torch",   name = "Lengre fakkel", desc = "Større lyskule rundt deg.",           coinPrice = 300, torchBonus = 22 },
	{ id = "shield",  name = "Ekstra liv",    desc = "Overlev ett treff pr nivå (skjold).", coinPrice = 600 },
	{ id = "speed",   name = "Fartsboost",    desc = "Litt raskere gange.",                 coinPrice = 500, speedBonus = 3 },
	{ id = "minimap", name = "Minikart",      desc = "Se et lite kart over labyrinten.",    coinPrice = 800 },
}

local index = {}
for _, p in ipairs(Perks.List) do
	index[p.id] = p
end

function Perks.byId(id)
	return index[id]
end

return Perks
