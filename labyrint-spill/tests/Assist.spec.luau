-- Rene logikk-tester for Assist ("Hjelp meg"-guiden). Kjør med luau CLI:
--   luau tests/Assist.spec.luau
-- (Ingen Roblox-API brukt. Rute-testen kjører mot en EKTE generert labyrint via
--  MazeGen + Medals.dist, slik serveren gjør det.)

local Assist = require("../src/shared/Assist")
local MazeGen = require("../src/shared/MazeGen")
local Medals = require("../src/shared/Medals")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(v, msg) eq(v and true or false, true, msg) end

-- Samme verdier som CONFIG.Assist i src/server/MazeGame.server.luau.
local CFG = { Enabled = true, OfferAfterFails = 3, MinRunSeconds = 8, BasePrice = 40,
	PricePerLevel = 6, MaxPrice = 250, MaxTrailParts = 400 }

--=========================  PRIS  ===============================--
eq(Assist.price(1, CFG), 46, "level 1 -> 40 + 6")
eq(Assist.price(6, CFG), 76, "level 6 (first trap level) -> 76")
eq(Assist.price(35, CFG), 250, "price caps at MaxPrice")
eq(Assist.price(500, CFG), 250, "still capped at level 500")
eq(Assist.price(0, CFG), 46, "level 0 clamps up to 1")
eq(Assist.price(-99, CFG), 46, "negative level clamps up to 1")
truthy(Assist.price(10, CFG) >= CFG.BasePrice, "never cheaper than BasePrice")
-- ombyttet gulv/tak skal ikke kunne kaste
eq(Assist.price(9, { Enabled = true, OfferAfterFails = 3, BasePrice = 300,
	PricePerLevel = 6, MaxPrice = 100 }), 100, "swapped floor/ceiling still clamps")

--=======================  NÅR TILBYS DEN  =======================--
eq(Assist.shouldOffer(nil, 6, CFG), false, "no history -> no offer")
eq(Assist.shouldOffer({ level = 6, fails = 0 }, 6, CFG), false, "0 fails -> no offer")
eq(Assist.shouldOffer({ level = 6, fails = 2 }, 6, CFG), false, "2 fails -> below threshold")
eq(Assist.shouldOffer({ level = 6, fails = 3 }, 6, CFG), true, "3 fails -> offer")
eq(Assist.shouldOffer({ level = 6, fails = 9 }, 6, CFG), true, "more fails -> still offer")
-- EKSPLOIT-VAKT: forsøk på ET nivå gir ikke guide på et ANNET
eq(Assist.shouldOffer({ level = 6, fails = 9 }, 7, CFG), false, "fails on 6 give nothing on 7")
eq(Assist.shouldOffer({ level = 7, fails = 9 }, 6, CFG), false, "fails on 7 give nothing on 6")
eq(Assist.shouldOffer({ level = 6, fails = 9 }, 6,
	{ Enabled = false, OfferAfterFails = 3, BasePrice = 40, PricePerLevel = 6, MaxPrice = 250 }),
	false, "disabled -> never offered")

--=========================  KJØP  ===============================--
do
	local ok, reason = Assist.canBuy({ coins = 1000 }, nil, 6, false, CFG)
	eq(ok, false, "not stuck -> cannot buy")
	eq(reason, "notstuck", "reason notstuck")
end
do
	local ok, reason = Assist.canBuy({ coins = 1000 }, { level = 6, fails = 3 }, 6, true, CFG)
	eq(ok, false, "guide already active this run -> cannot buy again")
	eq(reason, "active", "reason active")
end
do
	local ok, reason, price = Assist.canBuy({ coins = 75 }, { level = 6, fails = 3 }, 6, false, CFG)
	eq(ok, false, "1 coin short -> cannot buy")
	eq(reason, "insufficient", "reason insufficient")
	eq(price, 76, "price reported even when refused")
end
do
	local ok, reason, price = Assist.canBuy({ coins = 76 }, { level = 6, fails = 3 }, 6, false, CFG)
	eq(ok, true, "exactly enough coins -> can buy")
	eq(reason, "ok", "reason ok")
	eq(price, 76, "price 76")
end

-- buy muterer BARE ved suksess
do
	local d = { coins = 500 }
	local ok, _, price = Assist.buy(d, { level = 6, fails = 3 }, 6, false, CFG)
	eq(ok, true, "buy succeeds")
	eq(d.coins, 500 - price, "coins deducted exactly once")
end
do
	local d = { coins = 10 }
	local ok = Assist.buy(d, { level = 6, fails = 3 }, 6, false, CFG)
	eq(ok, false, "buy refused when poor")
	eq(d.coins, 10, "refused buy does NOT touch coins")
end
do
	local d = { coins = 500 }
	Assist.buy(d, { level = 6, fails = 3 }, 6, false, CFG)
	local ok = Assist.buy(d, { level = 6, fails = 3 }, 6, true, CFG)  -- serveren har satt active
	eq(ok, false, "second buy in the same run refused")
	eq(d.coins, 424, "double-buy cannot drain coins twice")
end
do
	local d = { coins = 500 }
	local ok = Assist.buy(d, { level = 6, fails = 3 }, 6, false,
		{ Enabled = false, OfferAfterFails = 3, BasePrice = 40, PricePerLevel = 6, MaxPrice = 250 })
	eq(ok, false, "disabled -> buy refused")
	eq(d.coins, 500, "disabled buy does not charge")
end

--====================  TELLING AV FORSØK  =======================--
do
	local s = Assist.noteFail(nil, 6)
	eq(s.level, 6, "first fail records the level")
	eq(s.fails, 1, "first fail -> 1")
	s = Assist.noteFail(s, 6)
	s = Assist.noteFail(s, 6)
	eq(s.fails, 3, "three fails on the same level -> 3")
	truthy(Assist.shouldOffer(s, 6, CFG), "3 fails unlocks the offer")

	-- bytter nivå -> tellingen starter forfra (ingen overføring av "stuckness")
	local t = Assist.noteFail(s, 7)
	eq(t.level, 7, "level switched")
	eq(t.fails, 1, "count restarts on a new level")
	eq(Assist.shouldOffer(t, 7, CFG), false, "no carried-over offer on the new level")

	-- fullført -> nullstilles
	local c = Assist.noteClear({ level = 6, fails = 5 }, 6)
	eq(c.fails, 0, "clearing the level resets the count")
	eq(Assist.shouldOffer(c, 6, CFG), false, "cleared level no longer offers")
	local other = Assist.noteClear({ level = 6, fails = 5 }, 7)
	eq(other.fails, 5, "clearing a different level leaves the count alone")
end

-- EKSPLOIT-VAKT: gå inn og rett ut igjen skal ikke låse opp tilbudet
eq(Assist.countsAsFail(0.5, true, CFG), false, "instant voluntary exit -> not a try")
eq(Assist.countsAsFail(7.9, true, CFG), false, "just under MinRunSeconds -> not a try")
eq(Assist.countsAsFail(8, true, CFG), true, "at MinRunSeconds -> counts")
eq(Assist.countsAsFail(60, true, CFG), true, "a real attempt counts")
eq(Assist.countsAsFail(0.5, false, CFG), true, "dying counts no matter how fast")
eq(Assist.countsAsFail(nil, false, CFG), true, "death with no clock still counts")
eq(Assist.countsAsFail(0.5, true, { Enabled = true, OfferAfterFails = 3,
	BasePrice = 40, PricePerLevel = 6, MaxPrice = 250 }), true, "no MinRunSeconds -> everything counts")

--=====================  TYNNING AV RUTA  ========================--
do
	local long = {}
	for i = 1, 1000 do long[i] = { i, 0 } end
	local thin = Assist.thin(long, 400)
	truthy(#thin <= 401, "thinned route respects the cap (+ forced last point)")
	eq(thin[1][1], 1, "thinning keeps the first point")
	eq(thin[#thin][1], 1000, "thinning ALWAYS keeps the exit point")

	local short = { { 1, 1 }, { 1, 2 }, { 1, 3 } }
	eq(Assist.thin(short, 400), short, "short route returned untouched")
	eq(Assist.thin(nil, 400), nil, "nil route stays nil")
	eq(Assist.thin(short, 0), short, "cap 0 disables thinning rather than emptying it")
	local two = Assist.thin(long, 2)
	truthy(#two >= 2, "even the tightest cap keeps both ends")
	eq(two[#two][1], 1000, "tightest cap still ends at the exit")
end

--=========================  RUTE  ===============================--
-- Deterministisk RNG-erstatning (luau CLI har ingen Roblox Random).
local Lcg = {}
Lcg.__index = Lcg
function Lcg:NextInteger(a, b)
	self.s = (self.s * 48271) % 2147483647
	return a + (self.s % (b - a + 1))
end
local function rngFor(seed) return setmetatable({ s = seed % 2147483647 }, Lcg) end

do
	local cols, rows = 6, 6
	local grid, gCols, gRows = MazeGen.generate(cols, rows, rngFor(20260721))
	local startFine = { 1, 1 }
	local exitFine = { 2 * (cols - 1) + 1, 2 * (rows - 1) + 1 }
	local route = Assist.route(Medals.dist, grid, gCols, gRows, startFine, exitFine)

	truthy(route ~= nil, "route found on a real maze")
	eq(route[1][1], 1, "route starts at the spawn cell (x)")
	eq(route[1][2], 1, "route starts at the spawn cell (y)")
	eq(route[#route][1], exitFine[1], "route ends at the exit (x)")
	eq(route[#route][2], exitFine[2], "route ends at the exit (y)")

	-- hvert steg er nabo-til-nabo OG står på en åpen rute (aldri gjennom vegg)
	local contiguous, walkable = true, (grid[startFine[2]][startFine[1]] == false)
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		if math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) ~= 1 then contiguous = false end
		if grid[b[2]][b[1]] ~= false then walkable = false end
	end
	truthy(contiguous, "route steps are adjacent")
	truthy(walkable, "route never crosses a wall")

	-- lengden stemmer med den uavhengige BFS-en som regner par-tiden
	local steps = Medals.solveRoute(grid, gCols, gRows, startFine, exitFine, {})
	eq(#route - 1, steps, "route length matches Medals.solveRoute steps")

	-- guiden skal aldri kunne bygges tom / evig
	truthy(#route > 1, "route has more than one point")
	truthy(#route <= gCols * gRows, "route bounded by the grid size")
end

do
	-- uinnåbar utgang -> nil (serveren skal da ikke ta betalt / tegne noe)
	local grid = { [0] = { [0] = false, [1] = true }, [1] = { [0] = true, [1] = false } }
	local route = Assist.route(Medals.dist, grid, 2, 2, { 0, 0 }, { 1, 1 })
	eq(route, nil, "unreachable exit -> nil route")
end

print(string.format("Assist: %d passed, %d failed", passed, failed))
assert(failed == 0, "Assist tests failed")
