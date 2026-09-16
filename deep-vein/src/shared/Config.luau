--!strict
-- DEEP VEIN ⛏️ — every tunable in one table.
--
-- The pure modules (Mine, Ore, Economy, Prestige) take these values as ARGUMENTS, never as a
-- require, so the whole rule set runs in the luau CLI with no Roblox present. Server and client
-- read Config directly (they are the only two files allowed to know about the engine).

local Config = {}

-- Determinism. Every cave cell is a pure function of this seed, the rebirth count and the
-- cell's coordinates — so two players at the same rebirth are digging the SAME cave, which is
-- the only reason a depth leaderboard means anything.
Config.WorldSeed = 20260909

-- ── The shaft grid ───────────────────────────────────────────────────────────
-- A grid of Parts, deliberately NOT voxel Terrain. A grid answers "what is at this cell and
-- what does breaking it yield" as a pure function, which is testable from the CLI; Terrain
-- can only be asked at runtime by an engine we do not have here.
--
-- Cells are indexed (x, y, z): x and z run 1..GridW across the shaft, y counts DOWNWARD from
-- the surface (y = 0 is the open mouth, y = 1 the first floor you stand on).
Config.Mine = {
	CellSize = 6, -- studs per cell cube; also one "block" of depth
	GridW = 9, -- including the bedrock ring at x/z = 1 and GridW, so 7x7 is diggable
	SolidTopLayers = 1, -- layer 1 is ALWAYS rock: a new player always has a floor
	BaseMaxLayer = 24, -- deepest diggable layer at rebirth 0 — this IS the depth wall
	LayersPerRebirth = 12, -- each rebirth moves the wall this much further down

	-- Cave carving. Coherent value noise, not white noise: a cell is a natural void when the
	-- noise field is above AirThreshold, which produces connected pockets rather than speckle.
	AirThreshold = 0.60,
	NoiseScaleXZ = 3.2, -- lattice pitch, in cells, across the shaft
	NoiseScaleY = 2.6, -- lattice pitch, in cells, with depth
	Octaves = 2,
	OctaveGain = 0.5, -- amplitude of octave 2 relative to octave 1
	OctaveLacunarity = 2.1, -- frequency multiplier per octave

	HardnessPerLayer = 0.035, -- block hit points grow this fraction per layer of depth

	-- …and the ramp STOPS here. The ore weights below clamp at MaxWeight around layer 40, so past
	-- that point the rock is no richer — and an uncapped hardness ramp therefore made every extra
	-- layer strictly worse: measured, expected ore value per hit point peaked at 1.2065 on layer
	-- 40 and fell to 0.3085 by layer 312, a 3.9x DECLINE across exactly the range the last twenty
	-- rebirths open up. A rebirth is sold as "a deeper wall", so a deeper wall that pays less per
	-- swing than the one before it is the ladder eating itself. Placed where the weights finish
	-- saturating; Mine.spec walks all 312 layers and fails if any of them pays under 85% of the
	-- best layer above it.
	HardnessCapLayer = 40,

	RevealBudget = 1600, -- max air cells one break may flood through in a single reveal

	-- …and the budget that actually costs a frame. RevealBudget bounds the AIR the flood walks
	-- through; every one of those cells contributes up to 26 SOLID faces, and a solid face is an
	-- Instance.new("Part") plus a ClickDetector plus four attributes plus a signal connection.
	-- Breaking into a large natural void produced several hundred of those in one synchronous
	-- burst — the frame that should be the game's best moment was the frame it froze, for every
	-- player in the server. The parts are now built by a pump that spends this many per frame and
	-- yields, so the cost of one swing is bounded by a constant no matter how big the cave behind
	-- the wall turns out to be.
	PartsPerFrame = 64,

	ReachStuds = 26, -- ClickDetector activation distance on a rock face
	SwingCooldown = 0.28, -- seconds the server enforces between two swings

	-- ── Streaming: only the layers around the miner hold Parts ───────────────
	--
	-- NOTHING USED TO UNLOAD, AND THE CAVE IS SAVED, so a veteran's whole excavation was rebuilt
	-- on every join and kept for the session. Measured on this table: a fully excavated rebirth-24
	-- shaft is 10 097 Parts (all of them bedrock — see RimCells), an ordinary dig-straight-down is
	-- 11 960, and a lattice dig exposes 19 115. That is what one player costs the renderer, times
	-- however many share the server, in a game whose entire loop is "dig more".
	--
	-- The band is the bound. Parts exist only for layers within StreamLayers of the miner; the
	-- rest are destroyed and rebuilt from `opened` (which IS the cave, and is untouched by any of
	-- this) when the miner comes back. The number is set by the LIGHT, not by taste: the mine has
	-- no sun, and the best lamp in the game is BaseRadius + MaxLevel * PerLevel = 26 + 8*6 = 74
	-- studs = 12.3 layers. 16 layers is 96 studs — a third further than the best lamp money can
	-- buy can light, so nothing a player could have seen is ever missing.
	StreamLayers = 16,
	-- …and how far they have to move before the band is recomputed. Without it the sweep re-derives
	-- the face set every time the miner steps down one cell, for no change at all.
	StreamHysteresis = 4,
	StreamPeriod = 0.35, -- seconds between band checks
	-- Built outright, synchronously, around a teleport destination before the miner is moved there:
	-- DESCEND aims at an opened (empty) cell, and if the floor under it has not been built yet the
	-- miner falls through it to the bottom of the shaft.
	StreamLandingLayers = 2,

	-- The bedrock ring stands this many cells tall above the mouth. One cell is 6 studs and a
	-- Roblox jump clears about 7.2, so a one-cell lip lets a player hop out of the mine and stand
	-- on the roof of the world. Used by Mine.shell.
	RimCells = 3,
}

-- ── Ores ─────────────────────────────────────────────────────────────────────
-- Tier 0 is plain stone: it is mined, it takes hit points, and it is worth nothing. Tiers 1..5
-- are the ores. `MinLayer` gates each one behind depth, so the first hour is copper and iron.
Config.MaxOre = 5
Config.Ores = {
	Names = { [0] = "Stone", "Copper", "Iron", "Gold", "Diamond", "Obsidian" },
	-- RGB, used for the block in the world and the HUD row.
	Color = {
		[0] = { 92, 96, 108 },
		{ 198, 118, 66 }, -- Copper
		{ 176, 184, 196 }, -- Iron
		{ 244, 200, 72 }, -- Gold
		{ 128, 232, 246 }, -- Diamond
		{ 152, 92, 224 }, -- Obsidian
	},
	-- Cash per unit, before the rebirth multiplier. The top of the ladder used to be 1400 against
	-- a 4-cell obsidian population, which put 46% of a whole rebirth-0 shaft into FOUR cells:
	-- finding them or not was the difference between buying the first rebirth and mining the
	-- entire cave. Flattening the top two tiers (1400 -> 800, 340 -> 240) and making them commoner
	-- (below) takes that to 15.7%, which Mine.spec now asserts.
	Value = { [0] = 0, 6, 20, 70, 240, 800 },
	Hardness = { [0] = 10, 18, 30, 52, 92, 165 }, -- block hit points at layer 0
	Yield = { [0] = 0, 1, 1, 1, 1, 1 }, -- ore units a broken block drops

	-- Depth weighting, the Rarity table of this game. A tier's chance is 0 above MinLayer, then
	-- BaseWeight at MinLayer, drifting by DepthGain per layer below it, clamped to MaxWeight.
	-- Copper's DepthGain is NEGATIVE: it thins out as you go down, which is what makes the
	-- deep biomes read as different rather than just richer.
	--
	-- MINLAYER IS MEASURED IN THE SAME UNITS AS Mine.BaseMaxLayer AND HAS TO FIT INSIDE IT.
	-- Obsidian shipped at MinLayer 26 against a rebirth-0 depth wall of 24: Ore.weight returned
	-- zero for it at every layer a pre-rebirth player could stand on, so the deepest tier in the
	-- game — the one the store description promises and the one the first rebirth is meant to pay
	-- for — could not spawn at all. Diamond was legal but produced six cells in the entire shaft.
	-- The ladder below is spread over the 24 layers that actually exist, and the census in
	-- Mine.spec plus the reachability gate in Ore.spec now fail if either number drifts out from
	-- under the other.
	--
	-- THE LADDER ALSO HAS TO FIT INSIDE ONE SHAFT'S WORTH OF DIGGING. Spread over layers
	-- 1/4/9/14/19 with the old base weights, a rebirth-0 shaft held 7 diamond and 4 obsidian
	-- cells — a census floor of 3 with a margin of one cell, and a first rebirth that was a
	-- lottery over four blocks. Every tier now starts shallower and commoner: measured on the
	-- rebirth-0 shaft, 110 copper / 91 iron / 49 gold / 27 diamond / 10 obsidian, and the richest
	-- four cells are 15.7% of the shaft rather than 46%.
	MinLayer = { 1, 3, 6, 10, 14 },
	BaseWeight = { 0.150, 0.100, 0.060, 0.036, 0.018 },
	DepthGain = { -0.0022, 0.0013, 0.0018, 0.0016, 0.0012 },
	MaxWeight = { 0.150, 0.150, 0.110, 0.080, 0.060 },
}

-- ── Economy ──────────────────────────────────────────────────────────────────
Config.Economy = {
	StartCash = 0,

	-- Pickaxe tier 1..5. Power is damage per swing; Cost[t] is what it costs to REACH tier t
	-- (Cost[1] = 0, you start with it).
	Pickaxe = {
		Names = { "Rusty Pick", "Steel Pick", "Carbide Drill", "Plasma Drill", "Singularity Bore" },
		Power = { 5, 12, 28, 68, 170 },
		Cost = { 0, 260, 2100, 16000, 140000 },
		MaxTier = 5,
	},

	-- Backpack: how many ore units you can carry before you must surface and sell.
	Backpack = { BaseCapacity = 12, PerLevel = 6, MaxLevel = 12, BaseCost = 130, CostGrowth = 1.55 },

	-- Lamp: the PointLight radius on your character. The mine preset has no sun underground,
	-- so this is the difference between seeing a vein and walking past it.
	Lamp = { BaseRadius = 26, PerLevel = 6, MaxLevel = 8, BaseCost = 160, CostGrowth = 1.6 },
}

-- ── Prestige / Rebirth ───────────────────────────────────────────────────────
-- Wipes cash, haul, upgrades and this run's depth; keeps rebirths, best depth and total cash.
-- In exchange: a permanent cash multiplier, a deeper depth wall, and a NEW cave seed.
--
-- THE PRICE IS CHARGED AGAINST A FINITE SHAFT, AND IT IS NOW QUOTED IN ONE. A player's only
-- income is selling ore out of their own cave, that cave holds a fixed countable amount of it,
-- and mined cells do not grow back — across a relog either, since this version saves them. So the
-- only unit the price can honestly be written in is "how much of this cave do I have to mine",
-- and that is exactly what Config.Prestige.PriceFraction is.
--
-- Two hand-tuned curves failed at this before. The shipped one asked $30 000 of a rebirth-0 shaft
-- containing $5 876 of ore and then grew 3.2x per rebirth against a world growing 1.21x: every
-- one of the 25 rebirths cost more than its whole cave, so the wall never moved and the second
-- half of the game was dead. Its replacement fixed rebirth 0 (3.5x) and broke the middle: the
-- world's value curve triples between the first two rebirths and then flattens as the ore weights
-- saturate, so no geometric can follow it, and rebirths 4-17 ended up costing 4-7% of their own
-- cave — a ladder you climb without ever looking at the mine.
--
-- Prestige.requirement therefore integrates THE ORE TABLE ITSELF over every layer the current
-- wall exposes. The price cannot drift away from the world because it is computed from it.
-- Prestige.spec censuses all 25 real seeded caves and fails if any of them falls outside a
-- two-sided band — too expensive AND too cheap are both failures now.
Config.Prestige = {
	-- How much of your own cave the next rebirth costs. The price is no longer a hand-tuned
	-- curve at all: Prestige.requirement integrates the ore table over every layer the current
	-- wall exposes and charges this fraction of it, so the price tracks the world by construction
	-- at all 25 levels instead of being fitted to it. Measured against the real seeded caves,
	-- every rebirth costs between 27% and 35% of the shaft it is charged against.
	PriceFraction = 0.24,
	MultiplierPerRebirth = 0.8, -- cash multiplier = 1 + rebirths * 0.8
	MaxRebirths = 25,
}

-- ── Save ─────────────────────────────────────────────────────────────────────
Config.Save = {
	Enabled = true,
	Store = "DeepVein_v1",
	Leaderboard = "DeepVein_LB_v1", -- OrderedDataStore by deepest depth ever reached, in studs
	AutosaveSeconds = 20, -- also renews the session lock; MUST be < SessionLockSeconds
	SessionLockSeconds = 45,
}

return Config
