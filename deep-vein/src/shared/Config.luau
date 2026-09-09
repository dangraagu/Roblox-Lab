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
	Value = { [0] = 0, 6, 20, 80, 340, 1400 }, -- cash per unit, before the rebirth multiplier
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
	MinLayer = { 1, 4, 9, 14, 19 },
	BaseWeight = { 0.150, 0.070, 0.030, 0.020, 0.008 },
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
-- THE PRICE IS CHARGED AGAINST A FINITE SHAFT. A player's only income is selling ore out of
-- their own cave, and that cave holds a fixed, countable amount of it — once mined cells stop
-- growing back there is no second helping. The shipped numbers asked $30 000 of a rebirth-0
-- shaft that contains $5 876 of ore in total, and then multiplied the price by 3.2 per rebirth
-- against a world that only grows about 1.21x per rebirth: mining out EVERY cell of EVERY cave
-- paid at most 38% of the next rebirth, at every one of the 25 levels. The depth wall could
-- never move, so the deep ores could never be reached, so the second half of the game was dead.
--
-- Two things changed. The growth now tracks the world's own measured growth, and the price is
-- quoted in ORE rather than in cash: it is multiplied by the same rebirth multiplier that
-- inflates every sale, so a reward that makes your ore worth 20x does not also make the next
-- rebirth 20x cheaper. Prestige.spec now walks all 25 levels and fails if any of them costs more
-- than half of what its own cave contains.
Config.Prestige = {
	BaseRequirement = 3500,
	RequirementGrowth = 1.21, -- measured: the shaft's total ore value grows 1.2124x per rebirth
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
