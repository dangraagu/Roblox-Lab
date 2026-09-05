--!strict
-- GROW A CRYSTAL 💎 (Cavern Idle) — all tunables in one place.
-- Pure modules (Rarity, Growth, Economy, Geode, Codex) take these values as ARGS so
-- they stay testable in luau-CLI without Roblox. Server/client read CONFIG directly.

local Config = {}

-- Deterministic cavern socket layout (same seed = same cavern shape for everyone).
Config.WorldSeed = 20260905

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

-- ── Save ─────────────────────────────────────────────────────────────────────
Config.Save = {
	Enabled = true,
	Store = "GrowCrystal_v1",
	Leaderboard = "GrowCrystal_LB_v1", -- OrderedDataStore by total Dust earned
	AutosaveSeconds = 20,   -- also renews the session lock; MUST be < SessionLockSeconds
	SessionLockSeconds = 45, -- soft lock; expires fast so a crash rejoin isn't locked out
}

return Config
