--!strict
-- Ren kjøps-/eierskapslogikk for tema-butikken. INGEN Roblox-API og INGEN
-- global `script` — alt går via parametre, så den kan testes med luau CLI.
-- Serveren er autoritativ: den kaller disse på sin egen playerData-tabell,
-- validerer, og lagrer. Klienten sender bare ønsker.
--
-- `themes` = Themes-modulen (må ha :byId(id)). `data` = spillerens tabell:
--   { coins=number, gems=number, owned={ [id]=true }, theme=string }

local ShopService = {}

function ShopService.owns(data, themeId)
	return data.owned ~= nil and data.owned[themeId] == true
end

-- Kan spilleren kjøpe dette temaet med denne valutaen? -> (ok, grunn)
function ShopService.canBuy(themes, data, themeId, payWith)
	local t = themes.byId(themeId)
	if not t then return false, "unknown" end
	if ShopService.owns(data, themeId) then return false, "owned" end
	local price
	if payWith == "coins" then
		price = t.coinPrice
	elseif payWith == "gems" then
		price = t.gemPrice
	else
		return false, "badcurrency"
	end
	if not price or price <= 0 then return false, "notforsale" end
	local bal = if payWith == "coins" then (data.coins or 0) else (data.gems or 0)
	if bal < price then return false, "insufficient" end
	return true, "ok"
end

-- Utfør kjøpet. Muterer BARE ved suksess. -> (ok, grunn)
function ShopService.buy(themes, data, themeId, payWith)
	local ok, reason = ShopService.canBuy(themes, data, themeId, payWith)
	if not ok then return false, reason end
	local t = themes.byId(themeId)
	if payWith == "coins" then
		data.coins = (data.coins or 0) - t.coinPrice
	else
		data.gems = (data.gems or 0) - t.gemPrice
	end
	data.owned = data.owned or {}
	data.owned[themeId] = true
	return true, "ok"
end

-- Velg et eid tema som aktivt. -> (ok, grunn)
function ShopService.select(themes, data, themeId)
	local t = themes.byId(themeId)
	if not t then return false, "unknown" end
	if not ShopService.owns(data, themeId) then return false, "notowned" end
	data.theme = themeId
	return true, "ok"
end

return ShopService
