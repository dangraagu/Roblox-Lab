--!strict
-- Ren, deterministisk generator for én tårn-etasje. Ingen Roblox-avhengigheter:
-- returnerer bare tall/tabeller (relative offsets), så den kan enhets-testes og er
-- IDENTISK for alle spillere (frø = WorldSeed + etasjenummer). Serveren gjør
-- offsets om til faktiske Part-er stablet oppover.
--
-- Hver etasje = TilesPerTier plattformer. Hver plattform ligger `stepHeight` OVER
-- forrige og `gap` (kant-til-kant) unna i en valgt himmelretning (forover-bias), så
-- HORISONTAL hoppdistanse alltid = gap (liten, klarerbar) mens VERTIKAL utfordring
-- vokser med etasjen. Progression vokter at stepHeight er klarerbart.

-- Kryss-modul require som virker BÅDE i Roblox (script.Parent) og luau-CLI (rel. sti).
-- `script` er nil i CLI, så short-circuit hindrer at script.Parent evalueres der.
local Progression = (script and require(script.Parent.Progression)) or require("./Progression")
local Rng = (script and require(script.Parent.Rng)) or require("./Rng")

local TowerGen = {}

-- Himmelretninger (dx, dz) i plattform-steg. Forover (+Z) veies tyngst så banen
-- klatrer fremover men slingrer litt til sidene (aldri bakover -> ingen overlapp).
local DIRS = {
	{ 0, 1 }, { 0, 1 }, { 0, 1 }, -- forover x3 (bias)
	{ 1, 0 },                     -- høyre
	{ -1, 0 },                    -- venstre
}

local HAZARD_KINDS = { "spike", "saw", "pendulum" }

-- Deterministisk etasje-oppsett for etasje `t`.
--   config = { Tower = <Config.Tower>, Jump = <Config.Jump>, WorldSeed = number }
-- Returnerer:
--   { tier, stepHeight, gap, exitDx, exitDz, exitHeight,
--     platforms = { { dx, dz, dy, size }, ... },   -- dy = høyde over etasje-origo
--     hazards   = { { dx, dz, dy, kind }, ... } }
function TowerGen.tier(t: number, config: any): any
	assert(t >= 1, "TowerGen.tier: tier must be >= 1")
	local tw = config.Tower
	local rng = Rng.new(config.WorldSeed + t)

	local step = Progression.stepHeight(t, tw)
	local gap = Progression.gap(t, tw)
	local reach = tw.TileSize + gap -- senter-til-senter horisontal avstand

	local platforms = {}
	local cx, cz = 0, 0 -- horisontal cursor (i studs), starter på etasje-origo
	for i = 1, tw.TilesPerTier do
		local d = Rng.pick(rng, DIRS)
		cx += d[1] * reach
		cz += d[2] * reach
		platforms[i] = { dx = cx, dz = cz, dy = i * step, size = tw.TileSize }
	end

	local hazards = {}
	local hCount = Progression.hazardCount(t, tw)
	for _ = 1, hCount do
		-- Fest hindringen til en tilfeldig plattform (ikke den første, så spilleren
		-- alltid har et trygt fotfeste inn i etasjen).
		local pIdx = Rng.int(rng, math.min(2, tw.TilesPerTier), tw.TilesPerTier)
		local p = platforms[pIdx]
		hazards[#hazards + 1] = {
			dx = p.dx, dz = p.dz, dy = p.dy, kind = Rng.pick(rng, HAZARD_KINDS),
		}
	end

	local last = platforms[tw.TilesPerTier]
	return {
		tier = t,
		stepHeight = step,
		gap = gap,
		exitDx = last.dx,
		exitDz = last.dz,
		exitHeight = last.dy, -- topp-plattformens høyde over etasje-origo
		platforms = platforms,
		hazards = hazards,
	}
end

return TowerGen
