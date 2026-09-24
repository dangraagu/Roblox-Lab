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

	-- What the bedrock (Mine.shell's four walls and floor) is made of. Near-black Basalt: the edge of
	-- the claim reads at a glance. Only the floor slab is clickable (it explains the depth wall); the
	-- walls are not (REVIEW-4), so no stratum's stone may look like them: EnvConfig.spec holds every
	-- stone look at every layer MinBedrockContrast away and off this material (review 2026-09-24).
	BedrockColor = { 26, 24, 30 },
	BedrockMaterial = "Basalt",
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

-- ── The strata: the environment follows DEPTH ────────────────────────────────
-- Owner's brief 2026-09-17: richer, never monotonous, the world changes as you progress; rare,
-- telegraphed hazards; a way to rest that cannot be exploited. EYECANDY.md has the whole design,
-- the measurements and the shot list.
--
-- The progress value is the layer the miner is standing in, read by the client from its own
-- character (Strata.depthAt / layerAt) — never a clock. `from` is in LAYERS (one layer = one 6-stud
-- cell = the "m" on the HUD / 6). Every band blends in over `fade` layers ABOVE its `from`
-- (EnvBands), and on top of that every written value glides with a HalfLife, so the elevator's
-- teleports glide too.
--
-- The layers are placed on the game's own ladder: the depth wall is 24 + 12 x rebirths, and each
-- rebirth's run spends most of its time at the bottom of its shaft, so a new band opens near the
-- bottom of a rebirth: river before the first rebirth, glowshrooms after it, magma after the second,
-- the geode after the third, fossils after the fifth, ruins after the seventh, obsidian after the ninth,
-- and the core as the long-term goal (rebirth 11). A new stratum at least every two runs.
-- Pacing, measured: robloxemu/check_deepvein_pace.luau.
--
-- Colours are {r, g, b} (EnvBands blends numbers, never Color3). `rock` is applied by the SERVER to
-- every stone cell it builds (Strata.rockLook: the band palette, the old per-cell jitter, an accent
-- cell now and then); ore keeps its own Neon colour, and EnvConfig.spec proves every ore stays
-- readable against every stratum it can appear in. Everything else is the client's (Cave.client).
Config.Env = {
	HalfLife = 0.6, -- seconds for a written value to cover half the gap (teleports glide, never cut)
	LightingHz = 10, -- Lighting is written at most this often, and only when a value changed
	RootAboveFloor = 4, -- the server stands a miner with the root this far above the floor (standY)
	JitterRange = 11, -- the server's per-cell stone jitter, unchanged: floor(unit * 22) - 11
	MinOreContrast = 70, -- RGB distance every ore keeps from every rock around it (EnvConfig.spec)
	DecorMargin = 3, -- studs a wall decoration keeps from the shaft's corners
	DecorLayers = 10, -- wall decorations exist within this many layers of the miner (the lamp reaches 12)
	DecorBuildPerFrame = 2, -- decorations built per frame at most; the rest wait for the next frame
	DecorSeed = 20260923, -- lays the walls out; the same for every player and every visit
	WeatherMinRate = 0.3, -- particles/s below which a weather emitter is switched off
	CoreBandId = "core",

	-- Review 2026-09-24. A falling hazard is DRAWN (Strata.dropY) with its bottom no lower than this
	-- over the floor while it hangs: a standing R15 is about 5.2 studs, so it is never drawn through the
	-- miner's head. Under a one-layer tunnel's 6-stud roof it pokes out of the roof instead.
	HeadTopAboveFloor = 5.3,
	-- Stone never looks like the bedrock walls (Config.Mine.BedrockColor): more than the 38.1 RGB two
	-- cells of one stratum can differ by jitter alone. EnvConfig.spec walks every layer.
	MinBedrockContrast = 45,
	-- A glowing wall decoration never passes for an ore that can sit beside it (EnvConfig.spec).
	MinDecorOreContrast = 70,
	-- The glowing colours of the wall decorations, by kind (CaveArt builds its Neon parts from these).
	DecorGlow = {
		-- review 2026-09-24: ice-blue crystals were diamond (15.7 RGB), gold glyphs and keystones were gold
		-- (11.9, 13.6), the lit shard edge was obsidian ore (40.1), lava was copper (64-68). Crystals are violet
		-- or rose, the ruins' magic is turquoise, lava runs redder and the waterfall's pool a deeper blue.
		waterfall = { { 70, 164, 224 }, { 60, 140, 230 } }, -- the fall, its pool
		shrooms = { { 70, 232, 196 }, { 236, 96, 206 } }, -- teal or pink caps
		lavacrack = { { 255, 80, 20 }, { 255, 96, 24 } },
		lavafall = { { 255, 86, 22 }, { 255, 88, 20 } }, -- the fall, its pool
		crystals = { { 214, 140, 255 }, { 255, 120, 200 } }, -- violet or rose
		arch = { { 60, 230, 190 } }, -- the keystone
		glyphs = { { 60, 230, 190 } },
		shards = { { 230, 140, 255 } }, -- the lit edge
		runes = { { 255, 84, 30 } },
	},
	-- The server's mine preset (Fx.Presets.Horror, applied by Main.server), which the paid lamp track
	-- was built against: "the head lamp and the glowing ore are ALL the light". Below the surface band a
	-- stratum may tint the fill, not brighten it (EnvConfig.spec; check_deepvein_cave compares these
	-- references with the server's real Lighting).
	LampFill = {
		ReferenceAmbient = { 20, 22, 30 },
		ReferenceOutdoorAmbient = { 15, 18, 28 },
		ReferenceExposure = -0.15,
		MaxAmbientRatio = 1.25,
		MaxExposureLift = 0.1,
	},

	Bands = {
		{
			id = "topsoil", name = "Topsoil & Roots", emoji = "🌱", from = 0, fade = 0,
			lighting = { Ambient = { 72, 62, 56 }, OutdoorAmbient = { 150, 118, 96 }, Brightness = 2.2,
				ExposureCompensation = 0.1, ClockTime = 17.6, FogStart = 60, FogEnd = 520, FogColor = { 214, 168, 130 } },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = { 228, 180, 140 }, Decay = { 150, 100, 80 }, Glare = 0.5, Haze = 1.8 },
			bloom = { Intensity = 0.9, Size = 26, Threshold = 0.95 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.15, TintColor = { 255, 236, 214 } },
			sunRays = { Intensity = 0.14, Spread = 0.8 },
			rock = { color = { 112, 80, 54 }, material = "Ground", accent = { 78, 58, 42 }, accentChance = 0.14 },
			weather = { kind = "motes", rate = 4 },
			ambient = { { kind = "fireflies", count = 6 } },
			decor = { kinds = { "roots" }, perLayer = 0.8 },
			pieces = { "headframe" },
			hazards = {},
		},
		{
			id = "stone", name = "Grey Stone", emoji = "🪨", from = 4, fade = 2,
			lighting = { Ambient = { 25, 26, 32 }, OutdoorAmbient = { 19, 21, 28 }, Brightness = 1,
				ExposureCompensation = -0.2, ClockTime = 23.6, FogStart = 12, FogEnd = 140, FogColor = { 26, 28, 36 } },
			atmosphere = { Density = 0.4, Offset = 0.1, Color = { 92, 98, 114 }, Decay = { 32, 34, 44 }, Glare = 0.05, Haze = 1.4 },
			bloom = { Intensity = 0.6, Size = 24, Threshold = 1.05 },
			colorCorrection = { Brightness = 0, Contrast = 0.16, Saturation = -0.25, TintColor = { 215, 222, 240 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 104, 106, 114 }, material = "Slate", accent = { 78, 80, 88 }, accentChance = 0.12 },
			weather = { kind = "dust", rate = 6 },
			ambient = { { kind = "moths", count = 2 } },
			decor = { kinds = { "seam", "pebbles" }, perLayer = 0.7 },
			hazards = { "rock" },
		},
		{
			id = "iron", name = "Iron Veins", emoji = "⛓️", from = 10, fade = 3,
			lighting = { Ambient = { 33, 25, 21 }, OutdoorAmbient = { 26, 20, 18 }, Brightness = 1,
				ExposureCompensation = -0.2, ClockTime = 23.6, FogStart = 12, FogEnd = 135, FogColor = { 38, 27, 22 } },
			atmosphere = { Density = 0.42, Offset = 0.1, Color = { 122, 92, 76 }, Decay = { 44, 30, 24 }, Glare = 0.08, Haze = 1.5 },
			bloom = { Intensity = 0.65, Size = 24, Threshold = 1.0 },
			colorCorrection = { Brightness = 0, Contrast = 0.17, Saturation = -0.15, TintColor = { 240, 220, 202 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 104, 94, 90 }, material = "Slate", accent = { 112, 66, 52 }, accentChance = 0.22 },
			weather = { kind = "rust", rate = 6 },
			ambient = { { kind = "bats", count = 2 } },
			decor = { kinds = { "timber", "rust" }, perLayer = 0.7 },
			hazards = { "rock" },
		},
		{
			id = "river", name = "Underground River", emoji = "🌊", from = 18, fade = 3,
			lighting = { Ambient = { 15, 28, 36 }, OutdoorAmbient = { 10, 23, 34 }, Brightness = 1,
				ExposureCompensation = -0.15, ClockTime = 23.6, FogStart = 14, FogEnd = 130, FogColor = { 14, 34, 48 } },
			atmosphere = { Density = 0.44, Offset = 0.12, Color = { 72, 122, 150 }, Decay = { 18, 40, 56 }, Glare = 0.1, Haze = 1.8 },
			bloom = { Intensity = 0.85, Size = 28, Threshold = 0.95 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.15, Saturation = -0.05, TintColor = { 204, 230, 255 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 72, 86, 100 }, material = "Slate", accent = { 56, 94, 118 }, accentChance = 0.18 },
			weather = { kind = "drips", rate = 14 },
			ambient = { { kind = "bats", count = 3 } },
			decor = { kinds = { "waterfall", "wet" }, perLayer = 0.6 },
			hazards = { "stalactite", "steam" },
		},
		{
			id = "grotto", name = "Glowshroom Grotto", emoji = "🍄", from = 28, fade = 4,
			lighting = { Ambient = { 17, 29, 25 }, OutdoorAmbient = { 11, 24, 21 }, Brightness = 1,
				ExposureCompensation = -0.13, ClockTime = 23.6, FogStart = 14, FogEnd = 130, FogColor = { 16, 38, 34 } },
			atmosphere = { Density = 0.44, Offset = 0.12, Color = { 82, 150, 130 }, Decay = { 20, 50, 46 }, Glare = 0.12, Haze = 1.8 },
			bloom = { Intensity = 1.1, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.15, Saturation = 0.1, TintColor = { 215, 255, 236 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 68, 80, 72 }, material = "Rock", accent = { 58, 100, 66 }, accentChance = 0.25 },
			weather = { kind = "spores", rate = 10 },
			ambient = { { kind = "glowmoths", count = 5 } },
			decor = { kinds = { "shrooms", "shrooms", "wet" }, perLayer = 0.9 },
			hazards = { "stalactite", "steam" },
		},
		{
			id = "magma", name = "Magma Glow", emoji = "🔥", from = 40, fade = 5, celebrate = true, reached = "THE MAGMA",
			lighting = { Ambient = { 49, 21, 13 }, OutdoorAmbient = { 40, 14, 8 }, Brightness = 1.1,
				ExposureCompensation = -0.1, ClockTime = 23.6, FogStart = 12, FogEnd = 115, FogColor = { 60, 20, 10 } },
			atmosphere = { Density = 0.46, Offset = 0.12, Color = { 200, 92, 52 }, Decay = { 70, 24, 12 }, Glare = 0.3, Haze = 2.2 },
			bloom = { Intensity = 1.3, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.2, Saturation = 0.15, TintColor = { 255, 216, 192 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 82, 52, 46 }, material = "Rock", accent = { 108, 40, 26 }, accentChance = 0.2 },
			weather = { kind = "embers", rate = 18 },
			ambient = { { kind = "cinders", count = 4 } },
			decor = { kinds = { "lavacrack", "lavacrack", "lavafall" }, perLayer = 0.8 },
			hazards = { "lava", "steam" },
		},
		{
			id = "geode", name = "Crystal Geode", emoji = "💎", from = 54, fade = 6,
			lighting = { Ambient = { 31, 23, 46 }, OutdoorAmbient = { 26, 18, 44 }, Brightness = 1.05,
				ExposureCompensation = -0.1, ClockTime = 23.6, FogStart = 14, FogEnd = 130, FogColor = { 30, 20, 50 } },
			atmosphere = { Density = 0.44, Offset = 0.12, Color = { 140, 112, 200 }, Decay = { 40, 30, 70 }, Glare = 0.2, Haze = 1.8 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.16, Saturation = 0.2, TintColor = { 232, 216, 255 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 84, 76, 104 }, material = "Marble", accent = { 108, 92, 138 }, accentChance = 0.2 },
			weather = { kind = "glints", rate = 8 },
			ambient = { { kind = "wisps", count = 3 } },
			decor = { kinds = { "crystals", "crystals", "seam" }, perLayer = 0.9 },
			hazards = { "crystal", "steam" },
		},
		{
			id = "fossils", name = "Fossil Beds", emoji = "🦴", from = 78, fade = 8,
			lighting = { Ambient = { 30, 26, 19 }, OutdoorAmbient = { 25, 21, 15 }, Brightness = 1.05,
				ExposureCompensation = -0.13, ClockTime = 23.6, FogStart = 14, FogEnd = 135, FogColor = { 40, 34, 22 } },
			atmosphere = { Density = 0.42, Offset = 0.12, Color = { 170, 150, 110 }, Decay = { 54, 44, 30 }, Glare = 0.12, Haze = 1.6 },
			bloom = { Intensity = 0.95, Size = 28, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.14, Saturation = -0.05, TintColor = { 255, 240, 212 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 108, 94, 78 }, material = "Sandstone", accent = { 138, 124, 100 }, accentChance = 0.16 },
			weather = { kind = "sand", rate = 6 },
			ambient = { { kind = "bats", count = 3 } },
			decor = { kinds = { "ammonite", "ribs", "ammonite" }, perLayer = 0.8 },
			hazards = { "rock", "stalactite" },
		},
		{
			id = "ruins", name = "Lost Ruins", emoji = "🏛️", from = 100, fade = 8,
			lighting = { Ambient = { 29, 26, 15 }, OutdoorAmbient = { 24, 21, 12 }, Brightness = 1.05,
				ExposureCompensation = -0.11, ClockTime = 23.6, FogStart = 14, FogEnd = 135, FogColor = { 44, 36, 18 } },
			atmosphere = { Density = 0.42, Offset = 0.12, Color = { 196, 168, 100 }, Decay = { 60, 48, 24 }, Glare = 0.18, Haze = 1.7 },
			bloom = { Intensity = 1.05, Size = 30, Threshold = 0.86 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.15, Saturation = 0.05, TintColor = { 255, 236, 196 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 118, 106, 90 }, material = "Limestone", accent = { 146, 132, 104 }, accentChance = 0.16 },
			weather = { kind = "motes", rate = 7 },
			ambient = { { kind = "wisps", count = 3 } },
			decor = { kinds = { "arch", "glyphs", "arch" }, perLayer = 0.8 },
			hazards = { "relic", "rock" },
		},
		{
			id = "obsidian", name = "Obsidian Depths", emoji = "🌑", from = 124, fade = 8,
			lighting = { Ambient = { 31, 22, 46 }, OutdoorAmbient = { 20, 14, 34 }, Brightness = 1.05,
				ExposureCompensation = -0.11, ClockTime = 23.6, FogStart = 12, FogEnd = 120, FogColor = { 22, 14, 36 } },
			atmosphere = { Density = 0.46, Offset = 0.12, Color = { 120, 86, 190 }, Decay = { 36, 22, 64 }, Glare = 0.22, Haze = 2.0 },
			bloom = { Intensity = 1.25, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.2, Saturation = 0.12, TintColor = { 226, 210, 255 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 64, 50, 92 }, material = "Slate", accent = { 92, 70, 134 }, accentChance = 0.22 },
			weather = { kind = "void", rate = 9 },
			ambient = { { kind = "wisps", count = 4 } },
			decor = { kinds = { "shards", "shards", "crystals" }, perLayer = 0.9 },
			hazards = { "shard", "magma" },
		},
		{
			id = "core", name = "The Core", emoji = "🌋", from = 150, fade = 12, celebrate = true, reached = "THE CORE",
			lighting = { Ambient = { 50, 21, 9 }, OutdoorAmbient = { 46, 15, 4 }, Brightness = 1.2,
				ExposureCompensation = -0.05, ClockTime = 23.6, FogStart = 10, FogEnd = 100, FogColor = { 90, 30, 8 } },
			atmosphere = { Density = 0.5, Offset = 0.14, Color = { 255, 122, 52 }, Decay = { 100, 30, 6 }, Glare = 0.4, Haze = 2.5 },
			bloom = { Intensity = 1.6, Size = 36, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.24, Saturation = 0.25, TintColor = { 255, 206, 172 } },
			sunRays = { Intensity = 0, Spread = 0.8 },
			rock = { color = { 110, 24, 20 }, material = "Rock", accent = { 150, 56, 24 }, accentChance = 0.28 },
			weather = { kind = "sparks", rate = 28 },
			ambient = { { kind = "cinders", count = 6 } },
			decor = { kinds = { "runes", "lavacrack" }, perLayer = 1.0 },
			pieces = { "coreglow" },
			hazards = { "lava", "magma" },
		},
	},
}

-- ── Hazards: rare, telegraphed, vertical ─────────────────────────────────────
-- A mine shaft is a box of rock, so nothing flies in sideways: a rock works loose overhead or a
-- vent opens underfoot (Hazards.luau, `drop`). It hangs over the miner, tracking them, with a
-- shadow ring at their feet for the whole warning; locks `commit` seconds before it lands; then
-- falls in `fall` seconds. The ring is the danger zone (hitRadius + PlayerRadius, 6 studs across =
-- one cell): step out of it into any open cell beside you and it misses. A hit knocks you down for
-- a moment and nothing else — no health, no ore, no depth. Client only (Cave.client).
Config.Hazards = {
	IntervalMin = 120, -- seconds of MINING (the clock stops while resting) between two hazards
	IntervalMax = 180,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5, -- the hang point stops following a miner who moves faster (the elevator)
	PlayerRadius = 1.4,
	WalkSpeed = 16, -- the Humanoid default; the dodge is sized for it (EnvConfig.spec)
	KnockLift = 8, -- studs/s up, capped by Hazards.MAX_KNOCK_LIFT
	KnockSeconds = 0.9, -- PlatformStand after a hit, so the push carries: you are knocked down
	AimJitter = 0.8,
	SpreadDegrees = 0, -- (template field: vertical kinds do not use the view cone)
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	Kinds = {
		rock = { drop = "above", height = 22, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 32 },
		stalactite = { drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.5, hitRadius = 1.6, knock = 30 },
		lava = { drop = "above", height = 18, fall = 0.7, telegraph = 3.4, commit = 1.7, pass = 0.8, hitRadius = 1.6, knock = 30 },
		crystal = { drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 32 },
		relic = { drop = "above", height = 22, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 34 },
		shard = { drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.5, hitRadius = 1.6, knock = 32 },
		steam = { drop = "below", height = 7, fall = 0.35, telegraph = 3.4, commit = 1.8, pass = 1.2, hitRadius = 1.6, knock = 28 },
		magma = { drop = "below", height = 7, fall = 0.35, telegraph = 3.6, commit = 1.8, pass = 1.2, hitRadius = 1.6, knock = 36 },
	},
}

-- ── Rest: what "pause" means in a mine ───────────────────────────────────────
-- A Roblox server cannot pause the world for one player, so rest is a state: the miner sits down,
-- the view softens, and the cave leaves them alone (no hazard launches, and the hazard clock
-- FREEZES — it is never reset). Nothing is lost and nothing is earned. Any step, jump or swing wakes
-- them. Two Deep Vein rules on top of the template (Rest.luau): a rest starts only after
-- SettleSeconds of stillness, and not until MinAwakeSeconds after the last one ended — so a miner
-- cannot swing, rest, swing, rest to keep the hazard clock frozen between swings.
Config.Rest = {
	IdleSeconds = 20, -- standing still (no step, no swing) this long rests you too: AFK-safe
	RequireGrounded = true,
	BlockWhileThreat = true, -- mandatory (Rest.validate): rest is never a panic button
	WakeOnMove = true, -- mandatory (Rest.validate)
	WakeGraceSeconds = 0.3,
	PendingSeconds = 10, -- a queued request outlives the longest hazard (4.8 s) by more than 2 s
	SettleSeconds = 1.5,
	MinAwakeSeconds = 6,
}

-- ── Client budgets (mobile is the target) ────────────────────────────────────
-- Measured, not assumed: robloxemu/check_deepvein_cave.luau counts every local Part, emitter,
-- particle rate and light at the middle of every band and at every seam, and asserts these.
Config.Budget = {
	MaxLocalParts = 200, -- the server's shaft holds up to 1 124 (REVIEW-4); this is on top, client-only
	MaxEmitters = 4,
	MaxEmitterRate = 60, -- particles per second, all emitters together
	MaxWeatherEmitters = 2,
	MaxLights = 3,
	MaxBeams = 4,
	MaxTrails = 6,
	MaxHazards = 1,
}

-- ── Pacing model (robloxemu/check_deepvein_pace.luau) ────────────────────────
-- No telemetry exists, so time-to-depth is a MODEL: the walk bot plays the real server through the
-- rebirths (swings, blocks, surface trips are measured), and these are the human costs per action.
Config.Pacing = {
	Profiles = {
		normal = { swing = 0.45, block = 1.5, trip = 12 }, -- seconds per swing, per new block, per surface trip
		fast = { swing = 0.32, block = 0.8, trip = 7 },
		slow = { swing = 0.7, block = 2.5, trip = 20 },
	},
}

return Config
