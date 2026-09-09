--!strict
-- Config.luau — ETT bord med alle tallene. Ingen magiske tall noe annet sted i spillet.
--
-- This module requires NOTHING. A bare `require("./X")` resolves in the luau CLI and is
-- INVALID in Roblox, so every shared module here takes its dependencies as ARGUMENTS and only
-- the server/client scripts require, from ReplicatedStorage.

local Config = {}

-- Same WorldSeed => the exact same Bronze floor 7 for every player, forever. That is the only
-- reason a run time or a gem count means anything next to somebody else's. Change this number
-- and every floor in the game is a different floor.
Config.WorldSeed = 20260909

-- Seed = WorldSeed * SEED_WORLD + tierIndex * SEED_TIER + floor * SEED_FLOOR.
-- Every intermediate stays far below 2^53 (WorldSeed * 1000003 ~ 2.0e13, floor * 2654435761 at
-- floor = 100000 ~ 2.7e14): overflow there silently zeroes the low bits and every floor in a
-- tier starts generating the same maze.
Config.Seed = {
	World = 1000003,
	Tier = 7919,
	Floor = 2654435761,
}

--============================================================================ save

Config.Save = {
	Enabled = true,
	Store = "VaultRunners_v1",
	AutosaveSeconds = 45,
	LockSeconds = 120,          -- soft session lock TTL, renewed by autosave
}

--============================================================================ vault geometry

-- One storey is one maze floor of the vault; you climb the stack while the collapse rises.
-- WallHeight is DERIVED: wall top must meet the underside of the floor above, or a player can
-- see (and on a bad day land) between the storeys.
Config.Vault = {
	CellSize = 12,          -- studs per fine-grid cell (corridor width AND wall thickness)
	StoreyHeight = 18,      -- floor top to floor top
	FloorThickness = 2,
	StepRise = 3,           -- one step of the climb shaft; 6 steps span a storey
	StepSize = 5,           -- step tread is StepSize x 1 x StepSize
	GemHeight = 3,          -- gem centre above the storey floor
	ExitHeight = 3,
	KillPlaneStart = -10,   -- the collapse starts this far under storey 0
	-- ...and finishes this far above the TOP storey's floor. ZERO on purpose: the plane must
	-- consume every storey's floor, and then STOP. If it climbed past the top floor it would
	-- kill a runner standing at the exit a second or two before the countdown expired, and the
	-- seal — the thing the whole game is named after — would never once fire in a real run.
	-- Below the top storey the collapse is lethal; on the top storey the SEAL ends the run.
	KillPlaneTop = 0,
	KillPlaneThickness = 2,
}

--============================================================================ tiers

-- Three vaults, unlocked by TOTAL gems banked (not by gems held — spending on a pet must never
-- take a vault away). v1 ships exactly these three; there is no fourth hidden behind a grind.
Config.Tiers = {
	{
		id = "bronze", name = "Bronze Vault", emoji = "🥉",
		unlockGems = 0,
		cells = 4, storeys = 3, gemsPerStorey = 4, gemValue = 4, collapseSeconds = 70,
		wallColor = { r = 104, g = 78, b = 48 },
		floorColor = { r = 72, g = 58, b = 42 },
		gemColor = { r = 255, g = 176, b = 92 },
	},
	{
		id = "silver", name = "Silver Vault", emoji = "🥈",
		unlockGems = 1200,
		cells = 5, storeys = 4, gemsPerStorey = 5, gemValue = 10, collapseSeconds = 80,
		wallColor = { r = 118, g = 126, b = 140 },
		floorColor = { r = 78, g = 84, b = 96 },
		gemColor = { r = 168, g = 226, b = 255 },
	},
	{
		id = "gold", name = "Gold Vault", emoji = "🥇",
		unlockGems = 6000,
		cells = 6, storeys = 5, gemsPerStorey = 6, gemValue = 22, collapseSeconds = 90,
		wallColor = { r = 150, g = 122, b = 46 },
		floorColor = { r = 96, g = 78, b = 34 },
		gemColor = { r = 255, g = 226, b = 120 },
	},
}

-- How a tier gets meaner the deeper you go INSIDE it. Floors are 1-based.
Config.Curve = {
	CellsEveryNFloors = 6,
	MaxCells = 8,
	StoreysEveryNFloors = 10,
	MaxStoreys = 7,
	GemsEveryNFloors = 5,
	MaxGemsPerStorey = 9,
	CollapseTightenPerFloor = 1.5,  -- seconds shaved per floor
	MinCollapseFraction = 0.55,     -- never below this fraction of the tier's base timer
}

--============================================================================ the run

Config.Run = {
	TickSeconds = 0.2,       -- server run loop; also the collapse's own resolution
	CollectRadius = 7,       -- studs, to a gem's centre
	ExitRadius = 9,          -- studs, to the exit pad's centre
	KillMargin = 2,          -- the plane kills once it is this far above your feet
	SealWarnSeconds = 10,    -- HUD goes red under this
}

--============================================================================ pets

-- ONE rarity tier ("Vault-Keeper"), bought straight from the hub stall with banked gems.
-- No breeding, no trading, no eggs — that is a deliberate v1 scope line, not an oversight.
-- `mult` multiplies the gems you BANK, so a pet is only ever worth what you actually escape with.
Config.Pets = {
	Rarity = "Vault-Keeper",
	List = {
		{ id = "coppertail", name = "Coppertail", emoji = "🐿️", cost = 150, mult = 1.05 },
		{ id = "gearmoth", name = "Gearmoth", emoji = "🦋", cost = 400, mult = 1.10 },
		{ id = "lockjaw", name = "Lockjaw", emoji = "🐊", cost = 900, mult = 1.16 },
		{ id = "emberwing", name = "Emberwing", emoji = "🦇", cost = 1800, mult = 1.24 },
		{ id = "glimmerbat", name = "Glimmerbat", emoji = "🦉", cost = 3200, mult = 1.33 },
		{ id = "boltcat", name = "Boltcat", emoji = "🐈", cost = 5200, mult = 1.42 },
		{ id = "sablefox", name = "Sablefox", emoji = "🦊", cost = 8000, mult = 1.52 },
		{ id = "crownwyrm", name = "Crownwyrm", emoji = "🐉", cost = 12000, mult = 1.65 },
	},
	-- The companion orb trails this far behind and above the player's root.
	FollowDistance = 6,
	FollowHeight = 4,
	FollowLerp = 0.25,
	FollowTick = 0.1,
}

--============================================================================ hub

Config.Hub = {
	PadSize = { x = 80, y = 2, z = 60 },
	SpawnPosition = { x = 0, y = 4, z = 0 },
	PortalSpacing = 22,      -- between the three tier portals
	PortalSize = { x = 10, y = 14, z = 2 },
	PortalZ = -22,
	StallPosition = { x = 26, y = 3, z = 6 },
	StallSize = { x = 14, y = 6, z = 8 },
	-- Each player's vault instance is built this far out along +X, and the index is RECYCLED
	-- when they leave. Never let an offset march outward forever.
	VaultSpacing = 400,
	VaultOriginY = 200,      -- vaults sit high above the hub, out of its skyline
}

--============================================================================ hud

Config.Hud = {
	AccentColor = { r = 255, g = 196, b = 92 },
	DangerColor = { r = 255, g = 96, b = 96 },
	PanelColor = { r = 18, g = 18, b = 26 },
}

return Config
