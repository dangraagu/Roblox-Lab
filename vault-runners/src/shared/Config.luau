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
	-- SEVEN, not five, and not six. Five was UNDER the cadence this comment cites: measured
	-- against the real server, forty real profile changes spaced one flush tick apart cost forty
	-- UpdateAsyncs over 220 seconds — one write per 5.5s, sustainable indefinitely by a client
	-- alternating Equip between two owned pets. Six sits exactly ON the documented boundary, and
	-- this file already has one boundary it refuses to sit on (RunState's `now >= sealAt`).
	FlushTickSeconds = 7,
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
	StepRise = 3,           -- one pad of the climb shaft; 6 pads span a storey
	-- THE PAD IS SMALL AND THE GAP IS REAL. v1 had StepSize 5 at a 6-stud reach, which left ONE
	-- stud of open air between consecutive treads in a 12-stud cell: a 2-stud-wide runner cannot
	-- fall through a 1-stud slot, so there was no jump in the game that could be missed. Three
	-- studs of pad at an eight-stud reach leaves FIVE studs of air, and asks for 76% of what the
	-- jump can actually carry at a 3-stud rise (VaultPath.jumpReach = 10.6 studs).
	-- tests/VaultFloor.spec.luau's `climbIsFailable` holds both ends of that.
	StepSize = 3,           -- pad is StepSize x 1 x StepSize
	-- Centre-to-centre between consecutive pads. StepReach/2 + StepSize/2 must stay inside
	-- CellSize/2 — the shaft lives in ONE maze cell, because the hole in the floor above it is
	-- one maze cell — and VaultFloor asserts exactly that rather than trusting this comment.
	StepReach = 8,
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
	-- One 3-stud pad of the climb shaft, jumped. A default jump is ~1.0s in the air; landing
	-- on the next pad and setting up the following jump is costed a little under that, and
	-- the spec's slack requirement is what absorbs the difference. NOT affected by WalkSpeed.
	ClimbSecondsPerStep = 0.9,
	-- ROBLOX'S OWN NUMBERS, and the game does NOT set either of them — Workspace.Gravity and
	-- Humanoid.JumpPower are left at their defaults, so these are recorded here as FACTS the
	-- climb's geometry is derived from, not as tunables. VaultPath.jumpReach solves the
	-- projectile for how far a runner moving at WalkSpeed carries while gaining `rise` studs,
	-- and tests/VaultFloor.spec.luau's `climbIsFailable` holds every hop in the shaft inside it.
	-- Change either number and the shaft has to be re-measured, not re-typed.
	Gravity = 196.2,            -- studs/s^2, Workspace.Gravity's default
	JumpPower = 50,             -- studs/s of upward launch, Humanoid.JumpPower's default
	-- How wide the thing doing the jumping is. R15's HumanoidRootPart is 2 x 2 x 1, and this is
	-- the number that decides whether a GAP IS A GAP: a hole narrower than the runner is a seam
	-- they walk over, not a hop they can miss.
	RunnerWidth = 2,
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
	-- HOW MUCH OF THE MAZE'S DEAD-END MASS THE BUDGET PAYS FOR. The demand is
	--     shortest route  +  WasteWeight * (cells sitting in branches off that route)
	-- in cell-steps, per storey (VaultPath.wastedCells). 0 prices the vault as if the runner
	-- could see the maze from above; 1 prices the whole expected walk of one who cannot.
	--
	-- MEASURED, not chosen by feel. A blind-explorer simulation over 300 mazes x 20 runs at the
	-- 6x5 cap, swept over beta in {0, 0.25, 0.5, 0.75, 1}: 0.25 is the only value that beats the
	-- shipped 0 on BOTH axes at once — the curve gets WIDER (65 completion points from floor 1 to
	-- the asymptote, against 59) and the run-to-run spread inside a single floor gets SMALLER
	-- (per-maze difficulty CV 8.8% against 12.1%). Everything past 0.25 buys less jitter by
	-- spending curve: at 1.0 the deepest floor the safety bounds allow still completes 71% of
	-- modelled runs, so the endgame stops being an endgame.
	WasteWeight = 0.25,

	-- SLACK IS THE DIFFICULTY CURVE. The size caps are a pacing budget and Gold starts at both
	-- of them, so from floor 26 the maze cannot grow — what has to change with depth is how much
	-- room over the demand the runner is owed.
	--
	--     slack(f) = MinSlack + (Slack - MinSlack) * (1 + (f-1)/TightenFloors) ^ -TightenExponent
	--
	-- v1 shed a flat 0.02 per floor to a hard floor of 1.5, which hit its floor at floor 26 and
	-- was FLAT FOR EVER AFTER — the 6000-gem Gold unlock bought 25 floors of curve and then the
	-- same run repeated. A power-law decay never reaches its asymptote, so there is no floor at
	-- which the game stops getting harder; it is still shedding 0.037 of slack between floors 400
	-- and 1000, where the old schedule shed nothing between floor 26 and floor 20000.
	--
	-- Both ends come off a measured run-completion model, not taste. See REVIEW-3.md.
	Slack = 1.85,          -- floor 1: 98% of modelled runs escape. A first vault you cannot fail.
	MinSlack = 1.21,       -- the asymptote, and the LOWEST that clears every bound in
	                       -- tests/Collapse.spec.luau with 25% headroom over 2400 measured floors.
	TightenFloors = 25,    -- the scale of the decay, in floors
	TightenExponent = 0.75,
	-- A vault so small the derivation asks for twelve seconds is not a run, it is a corridor.
	MinSeconds = 30,
	-- ...and the other end. This is a PACING promise, not a safety clamp: nothing clamps the
	-- countdown to it, because clamping would make a big vault unwinnable again — which is the
	-- exact bug this section exists to prevent. It is the bound Config.Curve's caps are chosen
	-- to satisfy, and tests/Collapse.spec.luau fails if a generated floor ever exceeds it.
	MaxSeconds = 300,
}

--============================================================================ the climb (the obby)

-- THE ONE PLACE IN THIS GAME A JUMP CAN BE MISSED.
--
-- v1's climb was six 5x5 treads packed into a 12-stud cell at 3-stud rises, one stud apart. It
-- was not an obby; it was a staircase you had to press Space on. The store copy, the thumbnail
-- and the genre line all lead with "ROBLOX RAGE OBBY", and REVIEW.md's finding 7 held publishing
-- because of the gap between those two sentences.
--
-- So the shaft is now six 3x3 pads at the four corners of the stairwell cell, Vault.StepReach
-- apart, with FIVE STUDS OF OPEN AIR between consecutive pads — wider than the runner
-- (Movement.RunnerWidth), so a missed hop is a fall and not a stumble — and every pad CRUMBLES
-- shortly after it is first stood on, so there is no lining the jump up at leisure.
--
-- WHAT A MISS COSTS IS SECONDS, and the collapse is what turns seconds into a lost run. There is
-- no new death rule, no lost gems, no reset to the hub: you fall to the floor you came from and
-- you climb again, while the plane keeps rising. That is the whole failure model, and it is why
-- the obby composes with the countdown instead of competing with it.
Config.Ascent = {
	-- From the first moment the runner is standing on a pad to the pad falling away. A hop is
	-- costed at Movement.ClimbSecondsPerStep (0.9s), so this is a little over one hop of grace:
	-- keep moving and you never see it, stop to think and the floor goes.
	CrumbleSeconds = 1.1,
	-- ...and back, so the shaft can never be permanently destroyed. A rage obby that eats its own
	-- route is an unwinnable vault, which is exactly what tests/Collapse.spec.luau exists to stop.
	-- Longer than a fall plus a re-approach, so a runner who drops off pad 2 genuinely waits.
	RespawnSeconds = 3,
	-- How the SERVER decides a runner is standing on a pad, in studs, against the TRUSTED
	-- position (src/shared/Trace.luau) — never against the client's claim. Horizontal is measured
	-- to the pad's centre and is generous by half a pad, because a runner standing on the lip of
	-- a 3-stud pad is standing on it.
	--
	-- StandHeight is how far the runner's FEET may be above the pad's top surface, NOT how far
	-- their root may be. Measured from the root it is impossible to tell standing on pad 1 from
	-- walking across the floor underneath it — the pad's top is exactly StepRise up and a standing
	-- root is Run.RunnerRootHeight up, and those are the same number of studs above the floor.
	-- That made pad 1 crumble while the runner was still walking towards it.
	StandRadius = 3,
	StandHeight = 2,

	--------------------------------------------------------------------- the MODEL, not the game
	-- Neither of the next two numbers is read by the running game. They exist so the COUNTDOWN
	-- can pay for the obby: VaultPath.climbSeconds prices a storey transition as the expected
	-- number of hops plus the expected number of falls, and these are what "expected" means.
	--
	-- ModelMissChance is an ASSUMPTION, in the same way measure_curve.luau's blind explorer is an
	-- assumption. Nobody has played this game, so there is no measured miss rate to put here;
	-- REVIEW-4 sweeps it from 0 to 0.12 and reports what the curve does at each, instead of
	-- defending one number. Six hops at 0.04 is a 22% chance of falling at least once per storey
	-- and 0.94 expected falls per storey transition — about 3.7 falls in a five-storey Gold run.
	ModelMissChance = 0.04,
	-- Seconds from landing on the storey floor after a miss to being back under pad 1, including
	-- the wait when the pad you fell off has not respawned yet. The fall itself is NOT in here —
	-- VaultPath.fallSeconds solves that from Gravity.
	ModelReapproachSeconds = 0.8,
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
