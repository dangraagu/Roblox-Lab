-- Rene tester for TowerGen (deterministisk etasje-generering).
-- Kjør: luau tests/TowerGen.spec.luau
local TowerGen = require("../src/shared/TowerGen")
local P = require("../src/shared/Progression")
local Config = require("../src/shared/Config")

local cfg = { Tower = Config.Tower, Jump = Config.Jump, WorldSeed = Config.WorldSeed }
local tw = Config.Tower

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local function deepEq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deepEq(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- Determinisme: samme etasje + frø -> identisk oppsett
for _, t in ipairs({ 1, 5, 37, 250 }) do
	local x = TowerGen.tier(t, cfg)
	local y = TowerGen.tier(t, cfg)
	truthy(deepEq(x, y), "tier " .. t .. " deterministic")
end

-- Struktur på en etasje
local T = TowerGen.tier(7, cfg)
eq(#T.platforms, tw.TilesPerTier, "platform count = TilesPerTier")
eq(T.tier, 7, "tier index echoed")
eq(T.stepHeight, P.stepHeight(7, tw), "stepHeight matches Progression")
eq(#T.hazards, P.hazardCount(7, tw), "hazard count matches Progression")

-- Plattform-høyder stiger med i*stepHeight (topp = exitHeight)
local heightsOk = true
for i, p in ipairs(T.platforms) do
	if math.abs(p.dy - i * T.stepHeight) > 1e-6 then heightsOk = false end
end
truthy(heightsOk, "platform dy = i*stepHeight")
eq(T.exitHeight, tw.TilesPerTier * T.stepHeight, "exitHeight = top platform height")

-- Horisontal senter-til-senter avstand mellom påfølgende plattformer == TileSize+gap
-- (langs én akse; den andre uendret), så HOPP-gapet alltid = gap.
local reach = tw.TileSize + T.gap
local prevx, prevz = 0, 0
local reachOk = true
for _, p in ipairs(T.platforms) do
	local ddx = math.abs(p.dx - prevx)
	local ddz = math.abs(p.dz - prevz)
	-- nøyaktig én akse flyttet med `reach`, den andre 0
	local moved = (math.abs(ddx - reach) < 1e-6 and ddz < 1e-6)
		or (math.abs(ddz - reach) < 1e-6 and ddx < 1e-6)
	if not moved then reachOk = false end
	prevx, prevz = p.dx, p.dz
end
truthy(reachOk, "each hop is exactly TileSize+gap along one axis")

-- Hindringer festet fra plattform 2 og utover (aldri den første)
local T2 = TowerGen.tier(60, cfg) -- høy nok til å ha hindringer
truthy(#T2.hazards >= 1, "tier60 has hazards")
local hazNotOnFirst = true
for _, h in ipairs(T2.hazards) do
	if math.abs(h.dy - T2.platforms[1].dy) < 1e-9 and math.abs(h.dx - T2.platforms[1].dx) < 1e-9 then
		hazNotOnFirst = false
	end
end
truthy(hazNotOnFirst, "hazards never on first platform")

-- Ulike etasjer gir ulikt oppsett (frø skiller)
truthy(not deepEq(TowerGen.tier(10, cfg), TowerGen.tier(11, cfg)), "different tiers differ")

-- Ulik WorldSeed gir ulikt oppsett for samme etasje
local cfg2 = { Tower = Config.Tower, Jump = Config.Jump, WorldSeed = Config.WorldSeed + 1 }
truthy(not deepEq(TowerGen.tier(5, cfg), TowerGen.tier(5, cfg2)), "different world seed differs")

-- Plattform-sentre i verden (review 2026-09-17: klient-scenery skal holde seg unna tårnet). Samme
-- stabling som serveren: etasje 1 på (0, BaseY, 0), hver neste etasje på toppen av forrige.
do
	local all = TowerGen.platformCentres(cfg, 1, 50)
	eq(#all, 50 * tw.TilesPerTier, "platformCentres returns every platform of tiers 1..50")
	local ox, oy, oz = 0, tw.BaseY, 0
	local ok, k = true, 0
	for t = 1, 50 do
		local gen = TowerGen.tier(t, cfg)
		for i, p in ipairs(gen.platforms) do
			k += 1
			local c = all[k]
			if not (c and c.tier == t and c.idx == i and math.abs(c.x - (ox + p.dx)) < 1e-9
				and math.abs(c.y - (oy + p.dy)) < 1e-9 and math.abs(c.z - (oz + p.dz)) < 1e-9) then
				ok = false
			end
		end
		ox, oy, oz = ox + gen.exitDx, oy + gen.exitHeight, oz + gen.exitDz
	end
	truthy(ok, "in climbing order, stacked exactly the way the server builds the tower")
	local part = TowerGen.platformCentres(cfg, 40, 44)
	eq(#part, 5 * tw.TilesPerTier, "a tier range returns just those tiers")
	eq(part[1].tier, 40, "starting at the first tier asked for")
	truthy(math.abs(part[1].x - all[39 * tw.TilesPerTier + 1].x) < 1e-9 and math.abs(part[1].y - all[39 * tw.TilesPerTier + 1].y) < 1e-9,
		"at the same world position as in the full tower")
	eq(#TowerGen.platformCentres(cfg, 5, 4), 0, "an empty range is empty")
end

print(string.format("TowerGen: %d passed, %d failed", passed, failed))
assert(failed == 0, "TowerGen tests failed")
