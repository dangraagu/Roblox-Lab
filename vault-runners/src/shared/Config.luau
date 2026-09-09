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
	-- Remote-driven saves are COALESCED onto this tick instead of writing per tap. Roblox
	-- throttles writes to one key to roughly one every six seconds and queues about thirty
	-- before it errors, and flush() pcalls its failure — so an unthrottled save path does not
	-- crash, it silently stops saving. Every rejected Buy and Equip used to write: tapping down
	-- the eight-pet list to compare multipliers was eight UpdateAsyncs.
	FlushTickSeconds = 5,
	LockSeconds = 120,          -- soft session lock TTL, renewed by every write
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
	-- WHERE THE COLLAPSE STARTS, in STOREYS below the height at which it kills a runner standing
	-- on storey 0 — never as a bare stud offset. v1 wrote -10 here, which gave storey 0 only
	-- eleven studs of plane travel where every storey above it got eighteen: the ground floor of
	-- every vault in the game had 39% less time than the ones above it, on top of the countdown
	-- bug this whole file's collapse section now exists to prevent. Derived from the runner's own
	-- height (Run.RunnerRootHeight - Run.KillMargin) in VaultFloor, so EVERY storey — including
	-- the one you land on — gets exactly one storey-height of collapse to outrun.
	KillPlaneLeadStoreys = 1,
	-- ...and it finishes this far above the TOP storey's floor. ZERO on purpose: the plane must
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
		cells = 4, storeys = 3, gemsPerStorey = 4, gemValue = 4,
		wallColor = { r = 104, g = 78, b = 48 },
		floorColor = { r = 72, g = 58, b = 42 },
		gemColor = { r = 255, g = 176, b = 92 },
	},
	{
		id = "silver", name = "Silver Vault", emoji = "🥈",
		unlockGems = 1200,
		cells = 5, storeys = 4, gemsPerStorey = 5, gemValue = 10,
		wallColor = { r = 118, g = 126, b = 140 },
		floorColor = { r = 78, g = 84, b = 96 },
		gemColor = { r = 168, g = 226, b = 255 },
	},
	{
		id = "gold", name = "Gold Vault", emoji = "🥇",
		unlockGems = 6000,
		cells = 6, storeys = 5, gemsPerStorey = 6, gemValue = 22,
		wallColor = { r = 150, g = 122, b = 46 },
		floorColor = { r = 96, g = 78, b = 34 },
		gemColor = { r = 255, g = 226, b = 120 },
	},
}

-- How a tier gets meaner the deeper you go INSIDE it. Floors are 1-based.
--
-- THE CAPS ARE A PACING BUDGET, NOT A RENDER BUDGET. The countdown is derived from how long the
-- maze takes to walk, so every cell and every storey added here lengthens the run for real. At
-- the old caps (8 cells x 7 storeys) a Gold floor 21 measured 542 seconds of optimal route and
-- would have been handed a FOURTEEN MINUTE countdown, all of it lost on a single death.
-- tests/Collapse.spec.luau asserts the derived countdown stays under Config.Collapse.MaxSeconds
-- across every tier and a hundred floors, which is what holds these two numbers down.
Config.Curve = {
	CellsEveryNFloors = 6,
	MaxCells = 6,
	StoreysEveryNFloors = 10,
	MaxStoreys = 5,
	GemsEveryNFloors = 5,
	MaxGemsPerStorey = 9,
}

--============================================================================ the run

Config.Run = {
	TickSeconds = 0.2,       -- server run loop; also the collapse's own resolution
	CollectRadius = 7,       -- studs, to a gem's centre
	ExitRadius = 9,          -- studs, to the exit pad's centre
	KillMargin = 2,          -- the plane kills once it is this far above your feet
	SealWarnSeconds = 10,    -- HUD goes red under this
	-- Where a standing runner's HumanoidRootPart sits above the floor it is standing on. R15's
	-- root is one half-root + HipHeight over the ground. This is not decoration: it is the
	-- height the kill plane is compared against, so the plane's own start is derived FROM it.
	RunnerRootHeight = 3,
	-- THE CLIENT OWNS ITS OWN CHARACTER'S PHYSICS, so hrp.Position is a claim, not an
	-- observation. src/shared/Trace.luau keeps the server's own position for the runner and
	-- moves it toward that claim no faster than these allow; every rule in the run loop reads
	-- the trusted position instead. Read Trace.luau's header for what this does NOT stop.
	TrustedSpeedFactor = 1.35,   -- horizontal, over Movement.WalkSpeed — jitter, not speed
	TrustedClimbFactor = 2.5,    -- upward, over the modelled climb rate; players skip treads
	TrustedBurstSeconds = 3,     -- how much unused allowance can bank, for replication jitter
}

--============================================================================ movement

-- What a player can actually do, in the units the collapse is measured in.
--
-- THE SERVER WRITES WalkSpeed ONTO THE HUMANOID (Main.server, onCharacter). It has to: the
-- countdown is derived from distance / WalkSpeed, so a number here the engine does not honour
-- would be worse than no number at all — it would be a lie the whole difficulty curve is built
-- on. Roblox's default is 16, which is a walk; a vault runner outrunning a collapse runs.
Config.Movement = {
	WalkSpeed = 24,             -- studs/second, written onto every character that spawns
	-- One 3-stud step of the climb shaft, jumped. A default jump is ~1.0s in the air; landing
	-- on the next tread and setting up the following jump is costed a little under that, and
	-- the spec's slack requirement is what absorbs the difference. NOT affected by WalkSpeed.
	ClimbSecondsPerStep = 0.9,
}

--============================================================================ the collapse

-- THE COUNTDOWN IS DERIVED, NOT TYPED. See src/shared/VaultPath.luau for the derivation.
--
-- v1 shipped 70 / 80 / 90 seconds as three hand-picked numbers and computed the plane's speed as
-- (vault height) / (countdown). Adding a storey therefore made the plane RISE FASTER through the
-- lower ones: Silver and Gold killed a BFS-optimal runner on storey 0, and no test in the repo
-- measured a traversal time to notice. Now the vault is generated first, its optimal route is
-- measured, and the countdown follows from that. The only thing left to tune is how much slack
-- the runner is owed — which is what these numbers are.
Config.Collapse = {
	-- Multiplier on the optimal route. Everything a real player does that a BFS solver does not
	-- — detouring for gems, reading the maze, missing a jump, backtracking a dead end — comes
	-- out of this.
	Slack = 2.0,
	-- ...shaved as you go deeper into a tier. THIS is the difficulty curve now: the same maze,
	-- less room for error. It can never take the run below MinSlack, which is the point at which
	-- a perfect route with one gem per storey stops fitting.
	TightenPerFloor = 0.02,
	MinSlack = 1.5,
	-- A vault so small the derivation asks for twelve seconds is not a run, it is a corridor.
	MinSeconds = 30,
	-- ...and the other end. This is a PACING promise, not a safety clamp: nothing clamps the
	-- countdown to it, because clamping would make a big vault unwinnable again — which is the
	-- exact bug this section exists to prevent. It is the bound Config.Curve's caps are chosen
	-- to satisfy, and tests/Collapse.spec.luau fails if a generated floor ever exceeds it.
	MaxSeconds = 300,
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
