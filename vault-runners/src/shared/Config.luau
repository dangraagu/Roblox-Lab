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
	-- false in src, always: a Studio playtest must not write to the LIVE stores (2026-10-09 review). Set it true
	-- only in an open Studio place's Config when a save test needs the real stores (Board.spec checks).
	AllowStudio = false,
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
	-- The highscore board's OrderedDataStore (Config.Board). Its own store: an ordered store holds
	-- one integer per key, never a profile.
	Board = "VaultRunners_Deepest_v1",
}

--============================================================================ the highscore board

-- docs/complete-game-standard.md §3 (owner, 2026-09-16). One board, PUBLIC or FRIENDS, on a physical
-- sign by the hub spawn with a ProximityPrompt that toggles the view per player.
--
-- THE METRIC IS THE DEEPEST VAULT ESCAPED, as a depth: the tier's buried depth (Env.TierDepth) plus
-- the escapes made in it. It is the number the strata are drawn from, so the brag (the Frozen Vault,
-- depth 18+) is a row on the board. A script cannot inflate it: it moves only in finishRun, when
-- RunState.tryEscape banks a run the server judged on its own trusted position (Trace), and no remote
-- carries a depth, a floor or a time.
-- AND ONLY ESCAPES THE SERVER COULD TRACE COUNT (owner decision 2026-10-11, Config.Gate below,
-- src/shared/FlierGate.luau). Trace bounds speed, not geometry: a noclip client flies to the exit
-- through the walls and escapes every vault. Such an escape still banks and still advances `floors`,
-- but the board reads the profile's `traced` (VaultEnv.deepestCleared(traced)), which it does not move.
-- For an honest runner the two are the same number.
-- Stored as `depth * 2e9 + (2e9 - reachedAtUnix)` (src/shared/Board.luau) so a tie goes to whoever
-- escaped that deep FIRST, and written only when the depth improves.
Config.Board = {
	PublicRows = 10,            -- GetSortedAsync(false, 10)
	PublicCacheSeconds = 60,    -- the server asks for the top 10 at most once a minute
	FriendsRows = 10,
	FriendsCap = 200,           -- Players:GetFriendsAsync is never read past this many friends
	FriendsCacheSeconds = 300,  -- one player's friends list
	ScoreCacheSeconds = 120,    -- one friend's stored value (including "never escaped"), per server
	ReadsBurst = 40,            -- GetAsync on the board for friends: 40 at once...
	ReadsPerSecond = 1,         -- ...then 1 a second (Roblox allows 60 + 10 per player a minute)
	BudgetReserve = 10,         -- always leave this many GetAsync in Roblox's own budget
	MaxMetric = 4000000,        -- every stored value is exact in a double up to here (4e6 * 2e9 < 2^53)
	PromptDistance = 10,        -- studs; the spawn pad's edge is farther, so standing on it shows no prompt
	-- where the sign stands: west of the spawn, across from the pet stall, its face turned to the spawn,
	-- its foot on the hub floor (y = Size.y / 2). x = -18, not -16: at -16 the prompt low on its face was
	-- 9.6 studs from the spawn pad's edge, inside PromptDistance, so it would pop up on every spawn
	-- (check_vaultrunners_board measured it). At -18 it is 11.6 and the sign is 18.4 from the spawn.
	Position = { x = -18, y = 5.5, z = 4 },
	Size = { x = 16, y = 11, z = 1 },
	Text = {
		Title = "DEEPEST ESCAPES",
		EmptyPublic = "Nobody has escaped a vault yet. Escape one and your name goes here first!",
		FriendsFailed = "Couldn't load your Roblox friends right now. Try again in a minute.",
		NoFriends = "No Roblox friends yet. Friends you add show up here, ranked against you.",
		FriendsNoScores = "None of your %d friends has escaped a vault yet. Invite one and race them to the Frozen Vault!",
		FriendsChecking = "Checking your friends: %d of %d so far...",
		Loading = "Loading...",
		Prompt = "Public / Friends",
		Offline = "The board is offline this session (saving is off), so nothing is ranked.",
		-- The toast for an escape the flier gate could not follow (Config.Gate): what was banked, and
		-- that it is not ranked, in one line. %d = gems banked. Short: the HUD's toast is one 520 px line.
		Untraced = "💎 Banked %d gems. 🧭 Not on the board: the server lost your path.",
	},
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

--============================================================================ the flier gate

-- WHICH ESCAPES COUNT FOR THE BOARD (owner decision 2026-10-11: fliers must not top it).
-- src/shared/FlierGate.luau keeps a VALIDATED position per run and accepts a sample of the client's
-- claim only if it is reachable from there through the vault's corridors and stairwells inside what
-- a runner could have covered. An escape whose validated position cannot be at the exit is banked
-- exactly as before (gems, floor, everything `Trace` judged) and is NOT counted for the board.
-- Nothing here touches the economy, and nothing here slows anybody down.
--
-- Every number is a MARGIN for the honest runner, measured in tests/FlierGate.spec.luau:
Config.Gate = {
	-- On the flat, over Movement.WalkSpeed. The same 1.35 Trace allows, so the two cannot disagree
	-- about how fast a runner is: 32.4 studs/s against the 24 the server writes onto the Humanoid.
	SpeedFactor = 1.35,
	-- Upward, over the fastest any chain of jumps climbs (JumpPower / 2 = 25 studs/s, each jump landed
	-- at its apex). The pads themselves allow about 15 studs/s; this is 37.5.
	ClimbFactor = 1.5,
	-- How much unused allowance BANKS. This is the lag a runner at full speed can have and still be
	-- ranked: BurstSeconds x SpeedFactor = 5.4 s of freeze (129.6 studs of corridor in one move).
	-- It is also the longest hop a route-following cheat can make, so it is a few seconds, not thirty.
	BurstSeconds = 4,
	-- A root this far inside a wall is read as leaning out of the corridor next to it. A root part is
	-- half a stud deep and physics is not exact; a wall is 12 studs thick.
	WallTolerance = 1.5,
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
	-- from the runner's root to the pad's centre, and it is the pad's half-width plus the RUNNER's
	-- half-width: up to there, part of a 2-stud body is over the pad; past it, all of it is over the
	-- gap. DERIVED, not typed. It was 3 — a full pad-width of tolerance — and a runner who landed short,
	-- 1.5 studs out into the air and about to fall, was counted as standing on the pad (REVIEW-5 §3).
	--
	-- StandHeight is how far the runner's FEET may be above the pad's top surface, NOT how far
	-- their root may be. Measured from the root it is impossible to tell standing on pad 1 from
	-- walking across the floor underneath it — the pad's top is exactly StepRise up and a standing
	-- root is Run.RunnerRootHeight up, and those are the same number of studs above the floor.
	-- That made pad 1 crumble while the runner was still walking towards it.
	StandRadius = Config.Vault.StepSize / 2 + Config.Movement.RunnerWidth / 2,
	StandHeight = 2,
	-- HOW OFTEN THE SERVER LOOKS AT THE SHAFT, in seconds. Faster than the run's rules tick
	-- (Run.TickSeconds, 0.2) on purpose: a runner who chains the hops has a pad under their feet for
	-- about 0.13 s, and a 0.2 s look missed a third of those landings, so the pads they chained over
	-- never crumbled (robloxemu/check_vaultrunners_shaft.luau §6: 18 of 48 before, 0 after). The
	-- trusted position (Trace) is stepped at this rate too; the gems, the exit and the collapse are
	-- still judged at Run.TickSeconds.
	SampleSeconds = 0.05,

	--------------------------------------------------------------------- the MODEL, not the game
	-- Neither of the next two numbers is read by the running game. They exist so the COUNTDOWN
	-- can pay for the obby: VaultPath.climbSeconds prices a storey transition as the expected
	-- number of hops plus the expected number of falls, and these are what "expected" means.
	--
	-- ModelMissChance is an ASSUMPTION, in the same way measure_curve.luau's blind explorer is an
	-- assumption. Nobody has played this game, so there is no measured miss rate to put here;
	-- REVIEW-4 sweeps it from 0 to 0.12 and reports what the curve does at each, instead of
	-- defending one number. Five missable hops at 0.04 (hop 1 leaves from the floor and cannot be
	-- missed, VaultPath.failableHops) is an 18% chance of falling at least once per storey and 0.23
	-- expected falls per storey transition — about 0.91 falls in a five-storey Gold run.
	-- robloxemu/check_vaultrunners_static.luau recomputes every number in those two sentences; an
	-- earlier version said 0.94 and 3.7, which is `attempts - n`, the closed form's own first bug.
	ModelMissChance = 0.04,
	-- Seconds from landing on the storey floor after a miss to being back under pad 1. The fall
	-- itself is NOT in here — VaultPath.fallSeconds solves that from Gravity — and neither is the
	-- wait for a crumbled pad to come back: a miss on hop 2 can find pad 1 still gone for about two
	-- seconds. That wait is NOT modelled. Measured on the real server (walk_vaultrunners.luau) it
	-- is 0.46 s per fall — 22.2 s over 48 falls — so about 0.4 s at the 0.91 falls a Gold run is
	-- priced for, against a 269 s countdown (REVIEW-5 §5).
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

--============================================================================ the environment (EYECANDY.md)

-- EVERYTHING BELOW IS CLIENT-SIDE LOOK AND FEEL. src/client/Vault.client.luau reads it; the server
-- never does, and nothing below can change a countdown, a gem, a pad or a save. The time budget
-- (Config.Collapse, VaultPath) is untouched by all of it — tests/EnvConfig.spec.luau and
-- tests/Pacing.spec.luau say so in numbers.
--
-- THE PROGRESS VALUE IS DEPTH: the floor of the run the server started, plus how deep that tier's
-- vault is buried. A harder vault is a deeper vault, so unlocking Silver or Gold carries on down the
-- strata instead of starting again at the bank. Colours are {r, g, b} arrays (EnvBands blends
-- plain numbers; Color3 does not exist in the luau CLI).
Config.Env = {
	-- Bronze floor f is depth f; Silver floor 1 is depth 26; Gold floor 1 is depth 56. Chosen so a
	-- new tier opens in the band the player is already in (tests/Pacing.spec.luau measures that a
	-- normal, fast and slow player never unlock their way back to an earlier band).
	TierDepth = { 0, 25, 55 },
	HalfLife = 0.6,        -- every written value glides: half the gap closes in this many seconds
	LightingHz = 10,       -- Lighting is written at most this often, and only when a value changed
	-- The collapse as the runner feels it (VaultEnv.danger): 0 while the kill plane is this many
	-- studs or more below the height at which it would catch them, 1 at that height.
	DangerStuds = 18,
	MaxDangerBlend = 0.55, -- how far toward Env.Danger the grade goes at danger 1 (readability first)
	-- Weather and ceiling dust are thinned to this share while the runner is in the climb shaft, so
	-- the crumbling pads stay readable.
	ShaftWeatherScale = 0.3,
	-- One storey above the one you stand on is dressed too, so props never pop in as you climb.
	PropStoreysAbove = 1,
	PropBottomAboveFloor = 12.8, -- a hanging prop never reaches below this (a jumping head tops out near 12)
	-- CRITTERS (docs/complete-game-standard.md §2: every band has its own). Each stratum's kind is in its
	-- band (`critters`). A critter lives in ONE maze cell and walks a loop inside it (VaultEnv.critterOffset),
	-- placed from (storey, cell, floor seed) only, like a prop: it never reads the walls, the route or the
	-- gems. The runner meets the ones within CritterReach cells of the cell they stand in, nearest first,
	-- at most Budget.MaxCritters; never in the shaft cell or over the hole. Client-only and inert.
	CritterReach = 2,      -- maze cells (Chebyshev) around the runner's cell
	CritterRoam = 3.5,     -- studs: the loop's largest radius from the cell centre
	CritterHalfLength = 1, -- studs: the most any critter VaultArt draws reaches from its centre
	CritterBob = 0.4,      -- studs: how far a flyer bobs above and below its height

	-- The hub is not a band: it is where every run starts and ends. These are Fx.Presets.Cozy's
	-- numbers exactly (the server applies Cozy at load), so the client's first write changes nothing.
	Hub = {
		lighting = {
			Ambient = { 40, 44, 58 }, OutdoorAmbient = { 35, 40, 55 }, Brightness = 2, ExposureCompensation = 0.1,
			ClockTime = 0, FogStart = 20, FogEnd = 240, FogColor = { 22, 26, 40 },
		},
		atmosphere = { Density = 0.3, Offset = 0.2, Color = { 120, 150, 170 }, Decay = { 60, 80, 110 }, Glare = 0.2, Haze = 1.2 },
		bloom = { Intensity = 0.9, Size = 30, Threshold = 0.9 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.18, TintColor = { 220, 235, 245 } },
		sky = { StarCount = 3000 },
	},

	-- The collapse closing in pulls the grade toward this, by danger * MaxDangerBlend.
	Danger = {
		atmosphere = { Color = { 235, 120, 95 } },
		colorCorrection = { Contrast = 0.24, Saturation = 0.28, TintColor = { 255, 200, 185 } },
	},

	-- A crumbling pad is pulled toward its band's `crack` colour by CrackBlend as it goes, and a pad
	-- must stand out MinPadContrast:1 against the floor under it (WCAG ratio; VaultEnv.readablePad).
	CrackBlend = 0.7,
	MinPadContrast = 3,
	-- THE CRACK FOLLOWS THE SERVER'S PAD (VaultEnv.padLook). The server drops a pad CrumbleSeconds
	-- after its TRUSTED position reached it, on its own 0.2 s tick, and the drop has to replicate
	-- back — so it goes a beat (plus ping) after this client's own clock says it should. The crack is
	-- held at full until the server's drop arrives: indefinitely while the runner still stands on it,
	-- and for this long past the crumble once they have stepped off (a pad only brushed on the way past
	-- may never have been counted by the server, and then it never drops).
	CrackHoldSeconds = 1.5,
	PadFlashSeconds = 0.45, -- a pad that comes back flashes this long, unless a runner lands on it
	-- GEMS STAY FINDABLE. A gem (and the exit pad, which wears the gem colour) keeps its tier's colour
	-- where it stands out MinGemContrast:1 against the floor and MinGemWallContrast:1 against the walls,
	-- and wears the stratum's own `palette.gem` where it would vanish (VaultEnv.gem): Silver's pale
	-- blue on the Frozen Vault's ice read 1.10:1. The wall bar is what a bright gem can reach on the
	-- tomb's sandstone.
	MinGemContrast = 3,
	MinGemWallContrast = 1.8,
	-- ...AND IS NOT THE PADS' COLOUR. The pads are read by colour too, so a gem (and the exit pad) must
	-- sit this far from the pad painted on the same floor, as a Euclidean distance in sRGB 0-255
	-- (VaultEnv.rgbDistance). The first gem fix put pearl gems 42 from the tomb's cream pads and
	-- sapphire 42 from the Frozen Vault's navy; Bronze's orange sat 40 from the bank's gold pads from
	-- the start. 80 is twice those, and the drop ring's follow/lock pair already has to be 60 apart.
	MinGemPadDistance = 80,
	-- THE DROP'S RING STAYS VISIBLE. The ring is the danger zone itself, a Neon disc on the floor: the
	-- first candidate that stands out MinRingContrast:1 against the floor under it (seen through its own
	-- transparency, VaultEnv.readableRing) is drawn. Yellow read 1.16:1 on the Frozen Vault's snow, and
	-- a pure red lock cannot reach 3:1 on the bank's or the tomb's floor at any opacity.
	MinRingContrast = 3,
	RingFollow = {
		{ color = { 255, 210, 60 }, transparency = 0.35 }, -- yellow, on the dark floors
		{ color = { 140, 100, 0 }, transparency = 0.15 },  -- dark gold, on snow
	},
	RingLock = {
		{ color = { 255, 150, 140 }, transparency = 0.1 }, -- hot coral red, on the dark floors
		{ color = { 170, 0, 20 }, transparency = 0.25 },   -- crimson, on snow
	},

	-- Five strata. `from` is the DEPTH a band starts at; it blends in over `fade` depths before it.
	-- palette: colours the client paints onto the server's walls / floors / pads (COLOUR ONLY —
	--          never Material, Size, CFrame, CanCollide or Transparency, so physics and the obby are
	--          byte-identical to what the server built). `pad` must stand out against `floor` and
	--          `wall` (tests/EnvConfig.spec.luau measures the contrast): the obby is read by colour.
	--          `gem` is the stratum's own gem colour, worn by the gems and the exit pad wherever the
	--          tier's colour would vanish into this stratum (VaultEnv.gem).
	-- weather: one ambient particle kind around the camera. props: what hangs from the ceilings.
	-- piece: the set piece in the sky above the top storey. hazards: which ceiling drops fall here.
	Bands = {
		{
			id = "bank", name = "Bank Vault", emoji = "🏦", from = 0, fade = 0,
			blurb = "Marble, brass and other people's money",
			lighting = {
				Ambient = { 72, 64, 50 }, OutdoorAmbient = { 62, 56, 46 }, Brightness = 2, ExposureCompensation = 0.15,
				ClockTime = 0, FogStart = 20, FogEnd = 260, FogColor = { 30, 26, 20 },
			},
			atmosphere = { Density = 0.28, Offset = 0.2, Color = { 175, 150, 110 }, Decay = { 90, 70, 40 }, Glare = 0.1, Haze = 1.0 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.1, TintColor = { 255, 240, 215 } },
			sky = { StarCount = 800 },
			palette = {
				wall = { 104, 108, 116 }, floor = { 58, 82, 68 }, pad = { 215, 210, 200 }, -- marble pads: gold is the treasure's colour here
				accent = { 214, 172, 82 }, glow = { 255, 226, 160 }, crack = { 255, 90, 50 }, wallReflect = 0.06,
				gem = { 255, 214, 90 }, -- gold coin
			},
			weather = { kind = "glitter", rate = 6 },
			props = { kind = "lamp", density = 0.3 },
			critters = { kind = "rat", density = 0.35, speed = 4, height = 0.35, color = { 140, 124, 110 } },   -- rats along the marble
			piece = "dome",
			hazards = { "marble" },
		},
		{
			id = "tomb", name = "Pyramid Tomb", emoji = "🏺", from = 5, fade = 2,
			blurb = "Older stone under the bank. Sand in the corridors",
			lighting = {
				Ambient = { 100, 66, 38 }, OutdoorAmbient = { 92, 64, 40 }, Brightness = 2.2, ExposureCompensation = 0.1,
				ClockTime = 0, FogStart = 18, FogEnd = 220, FogColor = { 60, 38, 20 },
			},
			atmosphere = { Density = 0.36, Offset = 0.1, Color = { 222, 172, 112 }, Decay = { 140, 90, 40 }, Glare = 0.25, Haze = 2.0 },
			bloom = { Intensity = 1.0, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.2, TintColor = { 255, 226, 186 } },
			sky = { StarCount = 2600 },
			palette = {
				wall = { 214, 172, 110 }, floor = { 110, 78, 44 }, pad = { 255, 226, 60 }, -- gilded pads, clear of the pearl gems
				accent = { 46, 150, 160 }, glow = { 255, 166, 84 }, crack = { 255, 90, 50 }, wallReflect = 0,
				gem = { 255, 250, 235 }, -- pearl
			},
			weather = { kind = "sand", rate = 10 },
			props = { kind = "brazier", density = 0.3 },
			critters = { kind = "scarab", density = 0.35, speed = 1.2, height = 0.25, color = { 24, 60, 56 } },   -- scarabs in the sand
			piece = "sunDisc",
			hazards = { "sandstone" },
		},
		{
			id = "reactor", name = "Reactor Core", emoji = "⚛️", from = 14, fade = 3,
			blurb = "Somebody built a reactor under the tomb",
			lighting = {
				Ambient = { 42, 72, 88 }, OutdoorAmbient = { 32, 62, 80 }, Brightness = 2, ExposureCompensation = 0.05,
				ClockTime = 0, FogStart = 20, FogEnd = 240, FogColor = { 10, 30, 40 },
			},
			atmosphere = { Density = 0.3, Offset = 0.15, Color = { 92, 190, 222 }, Decay = { 20, 70, 100 }, Glare = 0.3, Haze = 1.2 },
			bloom = { Intensity = 1.3, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0, Contrast = 0.16, Saturation = 0.15, TintColor = { 212, 245, 255 } },
			sky = { StarCount = 400 },
			palette = {
				wall = { 76, 84, 98 }, floor = { 38, 42, 52 }, pad = { 124, 236, 255 },
				accent = { 0, 255, 210 }, glow = { 120, 230, 255 }, crack = { 255, 90, 50 }, wallReflect = 0.08,
				gem = { 140, 255, 110 }, -- isotope green
			},
			weather = { kind = "sparks", rate = 8 },
			props = { kind = "panel", density = 0.35 },
			critters = { kind = "drone", density = 0.35, speed = 2.5, height = 8.5, color = { 150, 150, 160 } },  -- maintenance drones
			piece = "reactorRing",
			hazards = { "pipe" },
		},
		{
			-- the brag: a normal player first runs it inside 30-45 min (owner decision 2026-09-30,
			-- tests/Pacing.spec.luau). It was from = 24, fade = 4 and arrived at 61 min.
			id = "frozen", name = "Frozen Vault", emoji = "❄️", from = 18, fade = 2,
			blurb = "The reactor's cold side. Everything here is ice",
			lighting = {
				Ambient = { 98, 122, 152 }, OutdoorAmbient = { 110, 140, 170 }, Brightness = 2.3, ExposureCompensation = 0.1,
				ClockTime = 0, FogStart = 18, FogEnd = 200, FogColor = { 60, 80, 110 },
			},
			atmosphere = { Density = 0.4, Offset = 0.1, Color = { 192, 222, 246 }, Decay = { 110, 150, 200 }, Glare = 0.15, Haze = 1.8 },
			bloom = { Intensity = 1.1, Size = 26, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.1, Saturation = -0.05, TintColor = { 226, 240, 255 } },
			sky = { StarCount = 3000 },
			palette = {
				wall = { 176, 214, 236 }, floor = { 226, 238, 246 }, pad = { 40, 92, 160 },
				accent = { 190, 240, 255 }, glow = { 170, 225, 255 }, crack = { 255, 90, 50 }, wallReflect = 0.15,
				gem = { 120, 40, 190 }, -- amethyst (sapphire sat 42 from the navy pads, REVIEW-5 §B2)
			},
			weather = { kind = "snow", rate = 14 },
			props = { kind = "icicles", density = 0.35 },
			critters = { kind = "bat", density = 0.35, speed = 5, height = 10, color = { 70, 60, 72 } },          -- frost bats under the ice
			piece = "aurora",
			hazards = { "icicle" },
		},
		{
			id = "volcano", name = "Volcano Temple", emoji = "🌋", from = 40, fade = 6,
			blurb = "The bottom of every vault. It is warm down here",
			lighting = {
				Ambient = { 104, 46, 30 }, OutdoorAmbient = { 92, 40, 28 }, Brightness = 2, ExposureCompensation = 0.05,
				ClockTime = 0, FogStart = 16, FogEnd = 200, FogColor = { 40, 12, 8 },
			},
			atmosphere = { Density = 0.38, Offset = 0.1, Color = { 204, 92, 52 }, Decay = { 90, 30, 10 }, Glare = 0.4, Haze = 1.6 },
			bloom = { Intensity = 1.4, Size = 34, Threshold = 0.8 },
			colorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = 0.25, TintColor = { 255, 216, 196 } },
			sky = { StarCount = 200 },
			palette = {
				wall = { 58, 44, 42 }, floor = { 34, 26, 26 }, pad = { 80, 220, 190 }, -- jade: bone sat 71 from the Gold tier's gems
				accent = { 255, 110, 30 }, glow = { 255, 124, 56 }, crack = { 255, 90, 50 }, wallReflect = 0,
				gem = { 255, 226, 120 }, -- molten gold
			},
			weather = { kind = "embers", rate = 12 },
			props = { kind = "embers", density = 0.3 },
			critters = { kind = "salamander", density = 0.35, speed = 2, height = 0.3, color = { 150, 44, 30 } }, -- fire salamanders
			piece = "eruption",
			hazards = { "lavaBomb" },
		},
	},

	-- THE ENDGAME IS NOT ONE ROOM (owner decision 2026-09-30). Every Gold floor is the Volcano Temple,
	-- and a player may live in Gold for hours, so past `from` the deepest stratum moves to its next
	-- HALL every `every` depths and wraps round: its own light (an overlay on the stratum's), its own
	-- weather and its own props. The palette — walls, floors, pads, gems, the drop's ring — is the
	-- stratum's own in every hall, so every readability bar in tests/EnvConfig.spec.luau holds in every
	-- hall by construction. The first hall IS the stratum as it was. VaultEnv.hall picks the hall;
	-- tests/Pacing.spec.luau measures how long one lasts a normal player.
	Halls = {
		from = 44,
		every = 4,
		list = {
			{ id = "magma", name = "Magma Hall" },
			{
				id = "obsidian", name = "Obsidian Hall",
				overlay = {
					lighting = { Ambient = { 74, 46, 96 }, OutdoorAmbient = { 62, 40, 86 }, FogColor = { 22, 10, 34 } },
					atmosphere = { Color = { 150, 96, 196 }, Decay = { 56, 22, 84 } },
					colorCorrection = { TintColor = { 228, 212, 255 } },
				},
				weather = { kind = "glitter", rate = 8 }, -- obsidian glints
				props = { kind = "brazier", density = 0.3 },
			},
			{
				id = "ash", name = "Ash Hall",
				overlay = {
					lighting = { Ambient = { 98, 88, 84 }, OutdoorAmbient = { 86, 78, 76 }, FogColor = { 42, 38, 36 } },
					atmosphere = { Color = { 172, 162, 152 }, Decay = { 82, 72, 66 } },
					colorCorrection = { Saturation = -0.08, TintColor = { 236, 230, 224 } },
				},
				weather = { kind = "ash", rate = 12 },
				props = { kind = "lamp", density = 0.3 },
			},
		},
	},
}

--============================================================================ ceiling drops (the hazards)

-- RARE, TELEGRAPHED, AVOIDABLE, and LOCAL: a chunk of ceiling cracks over the runner, the ring under
-- their feet follows them for a couple of seconds, locks, and the chunk drops. Keep running and it
-- lands behind you; stand in the ring and it knocks you down for a moment. src/shared/Hazards.luau
-- is the rule (adapted from +1 Jump's template); VaultEnv.hazardEligible is where it may land.
--
-- A hit costs about a second and nothing else — no gems, no death rule, no pad — and it can only
-- happen to a player who stood still in the ring through the warning. tests/Pacing.spec.luau
-- measures what that does to a run: nothing, for a player who moves.
Config.Hazards = {
	IntervalMin = 120,          -- seconds of RUN time between drops (the hub freezes the clock)
	IntervalMax = 180,
	MinTelegraphSeconds = 2.5,
	MinCommitSeconds = 1.0,
	MaxTrackSpeed = 60,         -- studs/s the ring may follow; faster (a fall, a teleport) locks it
	PlayerRadius = 1,           -- R15 root half-width; the ring is hitRadius + this, and so is the rule
	AimJitter = 0.8,
	KnockLift = 4,              -- a hop, never a launch (Hazards.MAX_KNOCK_LIFT)
	MaxKnock = 16,
	KnockSeconds = 0.9,         -- PlatformStand after a hit: knocked down, then up again
	-- Where and when a drop may START (VaultEnv.hazardEligible):
	GraceSeconds = 12,          -- not in the first seconds of a run
	QuietBeforeSealSeconds = 15, -- not in the last seconds before the seal (the HUD goes red at 10)
	MaxDanger = 0.5,            -- not with the collapse within half a storey of catching you
	ShaftMarginCells = 2,       -- fine cells (Chebyshev) kept clear around the shaft and the hole
	-- The furthest a knocked-down runner is assumed to slide. Asserted against the hole's distance
	-- in tests/VaultEnv.spec.luau; how far a Roblox humanoid really slides is on the Studio list.
	KnockClearStuds = 4,
	Kinds = {
		marble = { name = "MARBLE SLAB", telegraph = 3.0, commit = 1.2, fall = 0.35, pass = 1.6,
			hitRadius = 2.4, knock = 12, dropHeight = 13, reach = 8 },
		sandstone = { name = "SANDSTONE BLOCK", telegraph = 3.0, commit = 1.2, fall = 0.35, pass = 1.6,
			hitRadius = 2.5, knock = 12, dropHeight = 13, reach = 8 },
		pipe = { name = "COOLANT PIPE", telegraph = 3.2, commit = 1.3, fall = 0.35, pass = 1.6,
			hitRadius = 2.4, knock = 12, dropHeight = 13, reach = 8 },
		icicle = { name = "ICICLE", telegraph = 3.4, commit = 1.4, fall = 0.3, pass = 1.6,
			hitRadius = 2.0, knock = 10, dropHeight = 13, reach = 8 },
		lavaBomb = { name = "LAVA BOMB", telegraph = 3.0, commit = 1.2, fall = 0.4, pass = 1.8,
			hitRadius = 2.5, knock = 14, dropHeight = 13, reach = 8 },
	},
}

--============================================================================ rest

-- A Roblox server cannot pause, and a vault run is a timed round: the collapse must never freeze.
-- So REST IS THE HUB. Between runs nothing can hurt you, no clock runs and no run starts by itself;
-- the ☕ Rest button there sits you down and softens the view. It is not offered inside a vault.
-- src/shared/Rest.luau (the template) is the rule; Rest.validate refuses WakeOnMove = false and
-- BlockWhileThreat = false, and "threat" here is "a run is going".
Config.Rest = {
	WakeOnMove = true,
	BlockWhileThreat = true,
	RequireGrounded = true,
	IdleSeconds = 0,       -- no idle rest: the hub has nothing to rest FROM, and a run never pauses
	PendingSeconds = 10,
	WakeGraceSeconds = 0.4,
}

--============================================================================ budgets (client, measured)

-- What the client may build on top of the server's vault, per player. Mobile is the target. These
-- are CAPS IN CODE, not only numbers a check compares against (EYECANDY.md §6, §13): VaultArt hangs
-- props only inside MaxLocalParts less its headroom, and VaultArt.enforceBudget, every frame, trims
-- parts, grants emitters by priority within MaxEmitters / MaxEmitterRate and caps lights and beams;
-- the weather also goes through EnvBands.capRates. MaxHazards is the drop scheduler's single slot
-- (Hazards holds one drop at a time) and tests/EnvConfig.spec.luau pins the number to it. Measured
-- by robloxemu/check_vaultrunners_env.luau §9 (shipped) and check_vaultrunners_budget.luau (forced).
Config.Budget = {
	MaxLocalParts = 180,      -- every Part the client creates, pooled or not, parented at once
	MaxEmitters = 6,          -- enabled ParticleEmitters the client owns
	MaxEmitterRate = 90,      -- their summed Rate, particles/s
	MaxWeatherEmitters = 2,   -- of which ambient weather (two bands blending at most)
	MaxWeatherRate = 30,
	MaxLights = 3,
	MaxBeams = 6,
	MaxHazards = 1,
	MaxCritters = 4,          -- critters on show at once (VaultArt.updateCritters; they yield first)
}

--============================================================================ pacing (a MODEL, not the game)

-- NOTHING IN THE RUNNING GAME READS THIS. tests/VaultModel.luau plays the real vaults with these
-- numbers so tests/Pacing.spec.luau can say how long a normal player takes to reach each band and
-- how often a ceiling drop comes near them. There is no telemetry yet: when there is, retune
-- `normal` FIRST, then Config.Env.Bands[*].from — the spec prints where each band lands.
Config.Pacing = {
	Profiles = {
		-- a normal player: reads the maze at every new junction, misses twice the hops the
		-- countdown prices, and spends a few seconds in the hub between runs
		normal = { SpeedFactor = 0.85, JunctionPauseSeconds = 0.6, RetryPauseSeconds = 0.2, MissChance = 0.08,
			HubSecondsPerAttempt = 12, StunSeconds = 1.2, ReactSeconds = 0.5, NearStuds = 8 },
		fast = { SpeedFactor = 0.95, JunctionPauseSeconds = 0.25, RetryPauseSeconds = 0.1, MissChance = 0.04,
			HubSecondsPerAttempt = 8, StunSeconds = 1.0, ReactSeconds = 0.35, NearStuds = 8 },
		slow = { SpeedFactor = 0.75, JunctionPauseSeconds = 1.2, RetryPauseSeconds = 0.4, MissChance = 0.15,
			HubSecondsPerAttempt = 20, StunSeconds = 1.5, ReactSeconds = 0.8, NearStuds = 8 },
		-- a normal player who stops to READ the maze for 3 s at every new junction. The three above
		-- never stand still long enough for a drop to land on them even when they ignore every
		-- warning, so this is the profile the cost of a hit is measured on (tests/Pacing.spec.luau)
		reader = { SpeedFactor = 0.85, JunctionPauseSeconds = 3, RetryPauseSeconds = 0.6, MissChance = 0.08,
			HubSecondsPerAttempt = 12, StunSeconds = 1.2, ReactSeconds = 0.5, NearStuds = 8 },
	},
}

return Config
