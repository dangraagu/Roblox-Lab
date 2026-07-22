--!strict
-- Ren kjøpslogikk for perks (kun Mynter, skrives til data.perks). INGEN Roblox-API
-- og INGEN `script` — testbar med luau CLI. Serveren er autoritativ; klienten
-- sender bare ønsket. Muterer BARE ved suksess.
--   `perks` = PerkDefs-modulen (må ha :byId(id)). `data` = spillerens tabell.

local PerkService = {}

function PerkService.owns(data, id)
	return data.perks ~= nil and data.perks[id] == true
end

function PerkService.canBuy(perks, data, id)
	local p = perks.byId(id)
	if not p then return false, "unknown" end
	if PerkService.owns(data, id) then return false, "owned" end
	local price = p.coinPrice
	if not price or price <= 0 then return false, "notforsale" end
	if (data.coins or 0) < price then return false, "insufficient" end
	return true, "ok"
end

function PerkService.buy(perks, data, id)
	local ok, reason = PerkService.canBuy(perks, data, id)
	if not ok then return false, reason end
	local p = perks.byId(id)
	data.coins = (data.coins or 0) - p.coinPrice
	data.perks = data.perks or {}
	data.perks[id] = true
	return true, "ok"
end

return PerkService
