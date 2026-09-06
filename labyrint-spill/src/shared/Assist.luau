--!strict
-- Ren "Hjelp meg"-logikk (guiden). INGEN Roblox-API og INGEN `script` — testbar
-- med luau CLI (se tests/Assist.spec.luau). Serveren er autoritativ; klienten
-- sender bare et ønske (uten argumenter) og får en tilstand tilbake.
--
-- HVORFOR: hvert nivå er vanskeligere enn det forrige, så før eller siden treffer
-- alle en vegg og slutter å spille. Guiden er utveien: står du fast, kan du kjøpe
-- en lysende rute til utgangen for MYNTER — for ÉN kjøring.
--
-- Guiden gir ALDRI gratis fremgang:
--   * Den koster mynter du har spilt deg til.
--   * Den kan bare kjøpes etter EKTE mislykkede forsøk på NØYAKTIG dette nivået,
--     talt på serveren (`fails`) — så den kan ikke brukes som speedrun-verktøy.
--   * Den hopper ikke over noe. Du må fortsatt gå ut selv, forbi feller og
--     monstre, og "accepted" krever fortsatt nøyaktig accepted+1 (Progression).
--   * En kjøring med guide gir INGEN tidsrekord (se Progression.recordEligible),
--     så rekordtavla kan ikke kjøpes.
--
-- Rute-uthentingen tar avstands-funksjonen INN som argument. Delte moduler skal
-- ALDRI kreve hverandre via sti — `require("./X")` er ugyldig i Roblox.

local Assist = {}

export type Config = {
	Enabled: boolean,
	OfferAfterFails: number,
	MinRunSeconds: number?,
	BasePrice: number,
	PricePerLevel: number,
	MaxPrice: number,
	MaxTrailParts: number?,
}

export type Stuck = { level: number, fails: number }

-- Pris for en guide på et nivå: vokser med nivået, men har både gulv og tak.
function Assist.price(level: number, cfg: Config): number
	local l = math.max(1, math.floor(tonumber(level) or 1))
	local p = math.floor(cfg.BasePrice + cfg.PricePerLevel * l)
	-- MaxPrice er ALLTID taket, også hvis noen skriver et gulv høyere enn taket
	-- (da blir prisen taket, ikke en overraskende dyr guide).
	local hi = cfg.MaxPrice
	local lo = math.min(cfg.BasePrice, hi)
	return math.max(lo, math.min(hi, p))
end

-- Skal tilbudet vises? Bare etter nok mislykkede forsøk på NØYAKTIG dette nivået.
function Assist.shouldOffer(stuck: Stuck?, level: number, cfg: Config): boolean
	if not cfg.Enabled then return false end
	if type(stuck) ~= "table" then return false end
	if (stuck :: Stuck).level ~= level then return false end
	return ((stuck :: Stuck).fails or 0) >= cfg.OfferAfterFails
end

-- Får spilleren kjøpe akkurat nå? -> ok, grunn, pris.
-- `data` = spillerens tabell (mynter), `alreadyActive` = guide alt kjøpt i denne
-- kjøringen.
function Assist.canBuy(data: any, stuck: Stuck?, level: number, alreadyActive: boolean, cfg: Config): (boolean, string, number)
	if not cfg.Enabled then return false, "disabled", 0 end
	local price = Assist.price(level, cfg)
	if alreadyActive then return false, "active", price end
	if not Assist.shouldOffer(stuck, level, cfg) then return false, "notstuck", price end
	if (data.coins or 0) < price then return false, "insufficient", price end
	return true, "ok", price
end

-- Trekk prisen. Muterer BARE ved suksess (samme mønster som PerkService.buy).
function Assist.buy(data: any, stuck: Stuck?, level: number, alreadyActive: boolean, cfg: Config): (boolean, string, number)
	local ok, reason, price = Assist.canBuy(data, stuck, level, alreadyActive, cfg)
	if not ok then return false, reason, price end
	data.coins = (data.coins or 0) - price
	return true, "ok", price
end

-- Var dette et EKTE forsøk? Døde du, teller det alltid. Gikk du frivillig ut
-- igjen, må du ha vært inne en liten stund — ellers kunne man låst opp tilbudet
-- ved å gå inn og ut av døra tre ganger på rad uten å prøve i det hele tatt.
function Assist.countsAsFail(runSeconds: number?, voluntary: boolean?, cfg: Config): boolean
	if not voluntary then return true end
	return (tonumber(runSeconds) or 0) >= (cfg.MinRunSeconds or 0)
end

-- Tell ett mislykket forsøk (død eller frivillig retur til lobbyen). Bytter
-- spilleren nivå, starter tellingen forfra på det nye nivået.
function Assist.noteFail(stuck: Stuck?, level: number): Stuck
	if type(stuck) ~= "table" or (stuck :: Stuck).level ~= level then
		return { level = level, fails = 1 }
	end
	return { level = level, fails = ((stuck :: Stuck).fails or 0) + 1 }
end

-- Nullstill tellingen når nivået faktisk ble fullført.
function Assist.noteClear(stuck: Stuck?, level: number): Stuck?
	if type(stuck) == "table" and (stuck :: Stuck).level == level then
		return { level = level, fails = 0 }
	end
	return stuck
end

-- Tynn ut en rute til høyst `maxPoints` merker, jevnt fordelt, men behold ALLTID
-- første og siste punkt. (Uten dette ville en lang rute blitt kuttet på midten,
-- så guiden stoppet halvveis og pekte spilleren ut i ingenting.)
function Assist.thin(route: { { number } }?, maxPoints: number?): { { number } }?
	if route == nil then return nil end
	local cap = maxPoints or 0
	if cap <= 0 or #route <= cap then return route end
	local step = math.ceil(#route / cap)
	local out = {}
	for i = 1, #route, step do out[#out + 1] = route[i] end
	if out[#out] ~= route[#route] then out[#out + 1] = route[#route] end
	return out
end

-- Ruta start -> utgang som en liste finrute-celler { {x,y}, ... }, eller nil hvis
-- utgangen er uinnåbar. `distFn(grid, gCols, gRows, x, y)` sendes INN (serveren
-- gir Medals.dist) og skal returnere et avstandskart "x,y" -> antall steg.
-- Vi måler fra UTGANGEN og går nedover gradienten fra starten.
function Assist.route(distFn: any, grid: any, gCols: number, gRows: number,
	fromFine: { number }, toFine: { number }, maxSteps: number?): { { number } }?
	local dist = distFn(grid, gCols, gRows, toFine[1], toFine[2])
	local function key(x: number, y: number): string return x .. "," .. y end
	local x, y = fromFine[1], fromFine[2]
	local d = dist[key(x, y)]
	if d == nil then return nil end
	local out = { { x, y } }
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local guard = maxSteps or 20000
	while d > 0 do
		guard -= 1
		if guard <= 0 then return nil end
		local moved = false
		for _, dir in ipairs(dirs) do
			local nx, ny = x + dir[1], y + dir[2]
			if dist[key(nx, ny)] == d - 1 then
				x, y, d = nx, ny, d - 1
				out[#out + 1] = { x, y }
				moved = true
				break
			end
		end
		if not moved then return nil end   -- skal ikke skje på et sammenhengende kart
	end
	return out
end

return Assist
