--!strict
-- GROW A CRYSTAL 💎 (Cavern Idle) — all tunables in one place.
-- Pure modules (Rarity, Growth, Economy, Geode, Codex) take these values as ARGS so
-- they stay testable in luau-CLI without Roblox. Server/client read CONFIG directly.

local Config = {}

-- Deterministic cavern socket layout (same seed = same cavern shape for everyone).
Config.WorldSeed = 20260905

-- ── Cavern decoration budget ────────────────────────────────────────────────
-- Every decoration count lives here so a low-detail pass can halve them without touching the
-- structure or any invariant test. Structure (41), lamp nubs (10) and lock caps (24) are fixed
-- by the geometry itself and are NOT tunable: 41 + 10 + 24 + 16+14+10+10 + 2*12 = 149 parts.
Config.Cavern = {
	Stalactites = 16,
	Boulders = 14,
	Rubble = 10,
	Veins = 10,
	Mushrooms = 12, -- 12 stems + 12 caps = 24 parts
}

-- ── Rarity tiers (index 1..6, low → high) ───────────────────────────────────
Config.Tiers = { "Shard", "Quartz", "Amethyst", "Prism", "Legendary", "Mythic" }
Config.MaxTier = 6

-- Colors (client tint per tier). RGB.
Config.TierColor = {
	{ 150, 200, 210 }, -- Shard  (pale)
	{ 120, 220, 160 }, -- Quartz (green)
	{ 170, 110, 230 }, -- Amethyst (purple)
	{ 90, 200, 255 },  -- Prism (cyan)
	{ 255, 190, 60 },  -- Legendary (gold)
	{ 255, 90, 200 },  -- Mythic (magenta)
}

-- ── Refraction (the gacha core) ─────────────────────────────────────────────
-- A grown crystal starts at its seed's tier and may CLIMB one tier at a time while
-- the roll succeeds. Chance to climb FROM tier t (decreasing), multiplied by luck,
-- clamped so it can never be certain. Mythic (6) cannot climb further.
Config.Refraction = {
	UpgradeChance = { [1] = 0.50, [2] = 0.35, [3] = 0.22, [4] = 0.12, [5] = 0.05 },
	MaxChance = 0.95, -- luck can never push a single step above this
}

-- ── Growth ──────────────────────────────────────────────────────────────────
-- Every crystal grows through StageCount stages; seconds-per-stage depends on the
-- seed's tier (rarer = slower). Total grow time = StageCount * secondsPerStage.
-- Offline progress = elapsed real time since last save (timestamp diff).
Config.Growth = {
	StageCount = 4,
	SecondsPerStage = { [1] = 15, [2] = 30, [3] = 60, [4] = 120, [5] = 300, [6] = 600 },
}

-- ── Economy ─────────────────────────────────────────────────────────────────
Config.Economy = {
	-- Gem Dust you get for harvesting a crystal of the FINAL (post-refraction) tier.
	DustValue = { [1] = 1, [2] = 4, [3] = 16, [4] = 64, [5] = 300, [6] = 1500 },
	-- Cost (in Dust) to buy a seed of a given base tier from the shop.
	SeedCost = { [1] = 10, [2] = 50, [3] = 250, [4] = 1200, [5] = 6000, [6] = 30000 },
	-- Seed tiers the shop sells from the start (higher tiers gated behind chambers).
	SeedShopUnlockedByChamber = { [1] = 1, [2] = 1, [3] = 2, [4] = 3, [5] = 5, [6] = 7 },
	-- Chambers: cost of the NEXT chamber given how many you already own.
	ChamberBaseCost = 500,
	ChamberGrowth = 2.2,
	MaxChambers = 8,
	SocketsPerChamber = 6,
	StartChambers = 1,
	StartDust = 30, -- enough for a couple Shard seeds
}

-- ── Boosters (permanent, Dust-bought upgrades) ──────────────────────────────
-- Luck raises refraction odds; Growth speeds every crystal. Level 0 = neutral.
Config.Boosters = {
	Luck = { BasePerLevel = 0.15, MaxLevel = 10, BaseCost = 400, CostGrowth = 1.8 },   -- luckMult = 1 + level*0.15
	Growth = { BasePerLevel = 0.10, MaxLevel = 10, BaseCost = 400, CostGrowth = 1.8 }, -- growthMult = 1 + level*0.10 (faster)
}

-- ── Weekly Geode event ──────────────────────────────────────────────────────
-- Cracking the weekly Geode grants a rotating guaranteed exclusive gem tier.
-- Epoch = a Monday 00:00 UTC (2026-09-07). Week bucket = floor((now-epoch)/604800).
Config.Geode = {
	Epoch = 1788480000, -- 2026-09-07T00:00:00Z (Monday)
	WeekSeconds = 604800,
	Rotation = { 4, 5, 6, 5 }, -- Prism, Legendary, Mythic, Legendary — cycles weekly
	CostDust = 1000,           -- price to crack a Geode (once per week per player)
}

-- ── Codes (one-time per player; reward = dust or a seed of a tier) ──────────
Config.Codes = {
	["WELCOME"] = { dust = 100 },
	["CRYSTAL"] = { dust = 500 },
	["GEODE"]   = { seedTier = 3 },
	["MYTHIC"]  = { dust = 5000 },
}

-- ── Gamepasses (fill real IDs when created; OFF until then) ──────────────────
Config.Passes = {
	Enabled = false,
	AutoHarvest = 0, -- auto-collects mature crystals
	DoubleDust = 0,  -- 2x harvest Dust
	LuckyAura = 0,   -- flat luck bonus
}

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- THE CAVERN COMES ALIVE: environment bands, visitors, harvest bursts and rest (EYECANDY.md)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Everything below is COSMETIC and runs on the client (src/client/Grotto.client.luau). Nothing here
-- grants, removes or records progress, and the server never reads it. Colours are {r, g, b}
-- (0-255), never Color3, so the pure modules and the luau-CLI specs can read them.
--
-- The PROGRESS value is the number of chambers the player owns, as the server pushes it in the
-- State event: the same number the HUD's chamber button and the rubble caps show. A band blends in
-- over `fade` chambers BEFORE its `from`, so every chamber purchase moves the look (2 = half-way to
-- the glow-worms, 3 = all of them, ...); the glide between two looks is timed (Env.HalfLife), the
-- trigger never is. tests/EnvConfig.spec.luau pins the rules, tests/Pacing.spec.luau measures when a
-- player gets there.

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

Config.Env = {
	HalfLife = 1.2,   -- s: lighting and scenery glide toward a new look (never a hard cut)
	LightingHz = 10,  -- Lighting is written at most 10 times a second, and only when a value moved

	Bands = {
		{
			id = "grotto", from = 0, fade = 0, name = "Sunken Grotto", emoji = "💧",
			-- = Fx.Presets.Cozy, number for number, so the client takes over from the server's lighting
			-- without a jump (EnvConfig.spec + check_growacrystal_env compare them)
			lighting = { ClockTime = 0, Brightness = 2, ExposureCompensation = 0.1,
				Ambient = rgb(40, 44, 58), OutdoorAmbient = rgb(35, 40, 55),
				FogStart = 20, FogEnd = 240, FogColor = rgb(22, 26, 40) },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(120, 150, 170), Decay = rgb(60, 80, 110), Glare = 0.2, Haze = 1.2 },
			bloom = { Intensity = 0.9, Size = 30, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.18, TintColor = rgb(220, 235, 245) },
			depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
			pulse = { depth = 0.08, period = 9 },
			pieces = { "poolShimmer" },
			ambient = { { kind = "moth", count = 2 } },
			weather = { { kind = "drips", rate = 6 } },
			visitors = {},
		},
		{
			id = "glowworm", from = 3, fade = 2, name = "Glow-worm Hollow", emoji = "✨", teaser = "Glow-worms are waking up…",
			lighting = { ClockTime = 0, Brightness = 1.9, ExposureCompensation = 0.12,
				Ambient = rgb(34, 46, 62), OutdoorAmbient = rgb(30, 44, 60),
				FogStart = 25, FogEnd = 260, FogColor = rgb(14, 30, 44) },
			atmosphere = { Density = 0.32, Offset = 0.2, Color = rgb(90, 170, 190), Decay = rgb(40, 90, 120), Glare = 0.25, Haze = 1.4 },
			bloom = { Intensity = 1.05, Size = 32, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.22, TintColor = rgb(205, 240, 250) },
			depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
			pulse = { depth = 0.15, period = 9 },
			pieces = { "poolShimmer", "glowworms" },
			ambient = { { kind = "moth", count = 5 } },
			weather = { { kind = "drips", rate = 5 } },
			visitors = { "mothSwirl" },
		},
		{
			id = "mushroom", from = 5, fade = 2, name = "Mushroom Terraces", emoji = "🍄", teaser = "Mushrooms are sprouting…",
			lighting = { ClockTime = 0, Brightness = 2.1, ExposureCompensation = 0.14,
				Ambient = rgb(52, 40, 62), OutdoorAmbient = rgb(46, 36, 58),
				FogStart = 25, FogEnd = 280, FogColor = rgb(36, 22, 44) },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(190, 130, 200), Decay = rgb(110, 60, 120), Glare = 0.3, Haze = 1.3 },
			bloom = { Intensity = 1.1, Size = 34, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.28, TintColor = rgb(245, 225, 250) },
			depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
			pulse = { depth = 0.2, period = 8 },
			pieces = { "poolShimmer", "glowworms", "shrooms" },
			ambient = { { kind = "moth", count = 6 } },
			weather = { { kind = "spores", rate = 8 }, { kind = "drips", rate = 3 } },
			visitors = { "mothSwirl" },
		},
		{
			id = "waterfall", from = 7, fade = 2, name = "Waterfall Chamber", emoji = "🌊", teaser = "You can hear water somewhere…",
			lighting = { ClockTime = 0, Brightness = 2.2, ExposureCompensation = 0.16,
				Ambient = rgb(38, 56, 64), OutdoorAmbient = rgb(34, 54, 62),
				FogStart = 20, FogEnd = 220, FogColor = rgb(20, 44, 54) },
			atmosphere = { Density = 0.36, Offset = 0.2, Color = rgb(140, 200, 215), Decay = rgb(60, 120, 140), Glare = 0.35, Haze = 1.8 },
			bloom = { Intensity = 1.15, Size = 34, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.25, TintColor = rgb(215, 245, 250) },
			depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
			pulse = { depth = 0.22, period = 8 },
			pieces = { "poolShimmer", "glowworms", "shrooms", "waterfall" },
			ambient = { { kind = "moth", count = 4 }, { kind = "bat", count = 4 } },
			weather = { { kind = "mist", rate = 12 }, { kind = "spores", rate = 4 } },
			visitors = { "batSwoop", "mothSwirl" },
		},
		{
			id = "geode", from = 8, fade = 1, name = "Heart of the Geode", emoji = "💎",
			lighting = { ClockTime = 0, Brightness = 2.3, ExposureCompensation = 0.2,
				Ambient = rgb(56, 40, 70), OutdoorAmbient = rgb(50, 34, 66),
				FogStart = 30, FogEnd = 300, FogColor = rgb(40, 18, 52) },
			atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(200, 140, 230), Decay = rgb(130, 60, 170), Glare = 0.45, Haze = 1.2 },
			bloom = { Intensity = 1.3, Size = 40, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.15, Saturation = 0.35, TintColor = rgb(250, 225, 255) },
			depthOfField = { FarIntensity = 0.1, FocusDistance = 30, InFocusRadius = 25, NearIntensity = 0.2 },
			pulse = { depth = 0.35, period = 7 },
			pieces = { "poolShimmer", "glowworms", "shrooms", "waterfall", "geodeHeart", "seams" },
			ambient = { { kind = "moth", count = 4 }, { kind = "bat", count = 3 }, { kind = "wisp", count = 5 } },
			weather = { { kind = "sparkle", rate = 10 }, { kind = "mist", rate = 8 } },
			visitors = { "batSwoop", "mothSwirl" },
		},
	},

	-- How many elements each scenery piece has (Grotto.layout). A half-weight piece shows the first half.
	Layout = { Glowworms = 16, Shrooms = 6, GeodePrisms = 10, Seams = 8 },

	-- Parts per critter model (moths and wisps are one glowing bead, a bat is a body and two wings).
	CritterParts = { moth = 1, bat = 3, wisp = 1 },
	-- Ambient life: never collidable, never in anybody's way (Grotto.layout gives each its zone).
	Critters = {
		moth = { speedMin = 2, speedMax = 4 },
		bat = { speedMin = 12, speedMax = 18 },
		wisp = { speedMin = 2, speedMax = 3.5 },
	},

	-- What a harvest looks like, by the refraction tier it rolled. A beam of light only for Legendary
	-- and Mythic (the owner's brief); Grotto.burst clamps the tier and returns a copy.
	Harvest = {
		{ shards = 4, ring = false, beam = false, flash = false, shake = 0 },
		{ shards = 6, ring = false, beam = false, flash = false, shake = 0 },
		{ shards = 8, ring = true, beam = false, flash = false, shake = 0 },
		{ shards = 10, ring = true, beam = false, flash = false, shake = 0 },
		{ shards = 12, ring = true, beam = true, flash = true, shake = 0, card = "🌟 LEGENDARY!" },
		{ shards = 12, ring = true, beam = true, flash = true, shake = 0.5, card = "💎 MYTHIC!" },
	},
	-- The full-screen flash of a Legendary/Mythic harvest (and the Mythic shake): a tint of `alpha` that fades
	-- over `fade` s, at most once per `cooldown` s (Grotto.flashDue). A Legendary seed always refracts to
	-- Legendary or Mythic, so without the cooldown a row of them stacked three flashes, 73 % opaque. The
	-- cooldown outlasts the fade, so two are never on screen together (EnvConfig.spec).
	HarvestFlash = { alpha = 0.35, fade = 0.8, cooldown = 2 },
}

-- Visitors: RARE and HARMLESS (a moth swirl down the light shaft, a bat swoop under the ceiling).
-- There are no knock-down hazards in this game: it is an idle game with no failure state, and a
-- hazard could only interrupt somebody who is waiting for their crystals (EYECANDY.md §3).
-- One visitor every 120-180 s of play (launch to launch), never two at once, none in the first band.
Config.Visitors = {
	IntervalMin = 120,
	IntervalMax = 180,
	Kinds = {
		mothSwirl = { seconds = 7, parts = 10 },
		batSwoop = { seconds = 6, parts = 18 },
	},
}

-- Rest ("🛋 Relax"): sit down, soften the view, visitors leave you alone; the crystals keep growing
-- (growth is server time, so resting can neither speed it up nor pause it). Idle rest is OFF: in an
-- idle game standing still IS playing, and nothing here can hurt an AFK player.
Config.Rest = {
	IdleSeconds = 0,
	RequireGrounded = true,
	BlockWhileThreat = true, -- there are no threats here: visitors are harmless, so Relax is never queued by one
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 3,      -- pressed mid-jump: sits you down on landing, or forgets it after 3 s
}

-- The pacing model in tests/IdleModel.luau. NOT used by the game: these are the assumptions behind
-- the band numbers above, written down instead of hidden (tests/Pacing.spec.luau).
Config.Pacing = {
	Profiles = {
		-- a normal player: checks their sockets every 75 s, plants the Shard seed the HUD starts on,
		-- buys the cheapest upgrade the shop offers while keeping enough dust to replant
		normal = { checkEvery = 75, codes = { WELCOME = true, CRYSTAL = true, GEODE = true, MYTHIC = true }, selectTier = 1, buy = "cheapest" },
		-- the same player, but slower to come back to the sockets
		slow = { checkEvery = 150, codes = { WELCOME = true, CRYSTAL = true, GEODE = true, MYTHIC = true }, selectTier = 1, buy = "cheapest" },
		-- a player who never types the advertised codes
		nocodes = { checkEvery = 75, codes = {}, selectTier = 1, buy = "cheapest" },
	},
	SessionHours = 8,
}

-- Mobile budget for what the CLIENT builds (measured in robloxemu/check_growacrystal_env.luau at every
-- chamber count and every seam). The server builds none of this. On top of the server's own cavern
-- (154 parts, 10 lights, 2 emitters per plot).
Config.Budget = {
	MaxLocalParts = 150,
	MaxScenery = 80,         -- Grotto.layout elements, all pieces together
	MaxEmitters = 4,
	MaxWeatherEmitters = 2,  -- enforced with EnvBands.capRates
	MaxEmitterRate = 30,     -- particles/s summed over the enabled weather emitters (also enforced)
	MaxLights = 1,           -- the Legendary/Mythic beam, for 2.5 s
	MaxShards = 12,          -- pooled harvest shards
	MaxVisitors = 1,
}

-- ── Save ─────────────────────────────────────────────────────────────────────
Config.Save = {
	Enabled = true,
	Store = "GrowCrystal_v1",
	Leaderboard = "GrowCrystal_LB_v1", -- OrderedDataStore by total Dust earned
	AutosaveSeconds = 20,   -- also renews the session lock; MUST be < SessionLockSeconds
	SessionLockSeconds = 45, -- soft lock; expires fast so a crash rejoin isn't locked out
}

return Config
