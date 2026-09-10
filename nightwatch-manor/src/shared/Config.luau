--!strict
-- Config.luau — every tunable for "Nightwatch Manor: Haunted Escape Tycoon".
-- One data block so a fresh session (or a reviewer) can retune the whole game from here.
--
-- Game loop, two phases:
--   NIGHT — the server builds a seeded, procedurally laid-out manor out of a modular room
--     kit. You walk it, take relics off their pedestals, and get back to the servants' exit
--     before DREAD fills. A single scripted Nightwatcher walks a patrol route through linked
--     rooms; it has NO pathfinding and NO chase AI — it sees you inside a view cone, in your
--     room or the room next door, and if it reaches you it takes what you are carrying.
--   DAY — back in your own safehouse you spend banked relic worth on upgrades. Every upgrade
--     changes a NUMBER the next night reads (dread speed, watcher speed, extract window,
--     relic value, how much you keep when caught) and puts a visible prop in the safehouse.
--
-- THREE CATALOGS, THREE DISPATCH TABLES. Room kinds, relic tiers and upgrades are all data
-- here, and each one is dispatched by ID through a builder table in Main.server.luau. The
-- server refuses to boot when an entry in any of the three has no handler — see the guard
-- next to ROOM_BUILDERS. Adding an entry to a list below does NOT make it happen.

local Config = {}

-- Base seed for every manor layout. Folded with the night number ONLY (never the userId), so
-- night 7 is the same manor for every player in the world — that is what makes "I got out of
-- night 14" a comparable claim. Deliberate trade: layouts are memorisable across sessions.
Config.WorldSeed = 20260909

-- Primes folded into the per-night seed. Kept here so nothing else in the codebase invents
-- its own. WorldSeed * SeedPrimeA stays far under 2^53 (2.0e7 * 7919 = 1.6e11), so no low
-- bits are lost to float rounding — the trap that pinned a sibling game to one layout.
Config.SeedPrimeA = 7919
Config.SeedPrimeB = 104729

-- ------------------------------------------------------------------ Manor generation
Config.Manor = {
	RoomSize = 40, -- studs; one grid cell is one square room
	WallHeight = 15,
	DoorWidth = 10,
	DoorHeight = 10,
	GridSpan = 5, -- rooms live in [-GridSpan, GridSpan] on both axes

	-- Room count grows with the NIGHT, and with nothing else. It deliberately does NOT read the
	-- player's hub level: night N has to be the same manor for everybody or the best-night number
	-- compares nothing, and with the exit always in the deepest room, sizing the manor off the
	-- safehouse made every upgrade quietly lengthen the walk out.
	-- MaxRooms is the cap on the TOTAL, repair rooms included, so `Manor.roomCount` stops the
	-- GROWTH TARGET MaxRepairRooms short of it and the repair pass spends the difference. It used
	-- to clamp the target AT this number and let repair append on top, which put 468 of nights
	-- 1-500 over the config's own limit (largest manor 23 against a MaxRooms of 18) with nothing
	-- asserting otherwise. Keep MaxRooms >= MaxRepairRooms + 2 — Manor.spec asserts it — or
	-- roomCount's floor at 2 out-votes the cap and the number here stops being a maximum again.
	BaseRooms = 6,
	RoomsPerNight = 0.5,
	MaxRooms = 18,

	-- Chance of a doorway through each wall a new room shares with an ALREADY-BUILT room other
	-- than the one it grew from. This is what puts circuits in the manor. At 0 the generator
	-- makes a pure tree, every branch of which ends in a dead end — and a dead end against a
	-- pursuer is a kill regardless of how fast the player is, which is exactly how a fleeing
	-- player was still being cornered on 8 of nights 1-12 after the chase speeds were fixed.
	ExtraDoorChance = 0.75,

	-- Rooms the generator may add ON TOP of the target while closing dead ends (see the repair
	-- pass in Manor.plan). A one-door room is somewhere a chased player cannot leave, so the
	-- manor is grown to `roomCount` and then closed; without a budget here it could not be.
	MaxRepairRooms = 5,

	-- Patrol route length (rooms). Consecutive entries are always LINKED rooms, so the
	-- Nightwatcher walks through doorways instead of through walls.
	PatrolBase = 3,
	PatrolPerNight = 0.25,
	PatrolMax = 8,

	-- Room kinds. `weight` 0 means "never drawn randomly" — foyer and vestibule are placed by
	-- the generator itself (entrance / exit). Every id needs a ROOM_BUILDERS entry.
	Kinds = {
		{ id = "foyer", name = "Foyer", weight = 0 },
		{ id = "vestibule", name = "Servants' Exit", weight = 0 },
		{ id = "hall", name = "Portrait Hall", weight = 3 },
		{ id = "library", name = "Library", weight = 2 },
		{ id = "dining", name = "Dining Room", weight = 2 },
		{ id = "nursery", name = "Nursery", weight = 1 },
		{ id = "cellar", name = "Cellar", weight = 1 },
		{ id = "chapel", name = "Chapel", weight = 1 },
	},
}

-- ------------------------------------------------------------------ Relics (the only currency)
-- What you carry out IS what you spend. `worth` is the banked value of one relic before the
-- Relic Vault multiplier. Deeper rooms bias the draw toward the later tiers via DepthBias.
-- Every id needs a RELIC_BUILDERS entry in the server.
Config.Relics = {
	Tiers = {
		{ id = "trinket", name = "Tarnished Trinket", worth = 10, weight = 5 },
		{ id = "portrait", name = "Cursed Portrait", worth = 25, weight = 3 },
		{ id = "reliquary", name = "Silver Reliquary", worth = 60, weight = 2 },
		{ id = "heart", name = "The Manor's Heart", worth = 150, weight = 1 },
	},
	DepthBias = 0.35, -- per room of depth, per tier step above the first
	Base = 4, -- relics on night 1
	PerNight = 0.5,
	Max = 12,
	MaxPerRoom = 2,
}

-- ------------------------------------------------------------------ The player
-- The player's speed is part of the MODEL, not an engine default nobody wrote down. The server
-- assigns WalkSpeed onto every Humanoid it sees, and Watcher.speed measures itself against this
-- number. It had to be added: with nothing setting it, the Nightwatcher was implicitly racing
-- Roblox's default 16, a value no config knew, no test asserted and no retune could see — and it
-- was losing that race from 0.8 seconds into night one.
Config.Player = {
	WalkSpeed = 20, -- studs/second on foot
}

-- ------------------------------------------------------------------ The Nightwatcher
-- No pathfinding, no chase AI. It walks the patrol route at a speed that rises with dread,
-- and it "sees" you when you are inside its view cone AND in its room or a linked one.
--
-- THE SPEEDS BELOW ARE BOUNDED BY THE PLAYER'S, NOT BY THEMSELVES. `MaxSpeedFraction` is a hard
-- ceiling applied inside Watcher.speed, and TWO boot audits sit on top of it (see
-- Watcher.speedAudit / Watcher.ceilingBinds, and the block that calls them in Main.server):
--   * Main.server REFUSES TO BOOT if MaxSpeedFraction reaches 1, or if WalkSpeed is not a
--     positive number. That state is a Nightwatcher nobody can outrun, which turns "it saw me"
--     into "I am dead" with no counterplay and makes the game's own advice ("break line of sight
--     and keep moving") a lie — you cannot break sight with something that closes on you.
--   * It WARNS if the raw curve below reaches the ceiling, because at that point the clamp has
--     stopped being a guard rail and become the operating point: the watcher sits at exactly
--     MaxSpeedFraction * WalkSpeed for most of the night and the three constants underneath stop
--     changing anything at all. The game is still playable, which is why it is not fatal — but
--     every headless gate asserts the server boots with ZERO warnings, so a build still fails.
-- Retune BaseSpeed / SpeedPerDread / HuntSpeedMul freely inside that: (8 + 2.4) * 1.2 = 12.48
-- against a ceiling of 13.00, so there is a little room and the F9 console will say when it runs
-- out.
Config.Watcher = {
	BaseSpeed = 8, -- studs/second at dread 0
	SpeedPerDread = 2.4, -- + this much at dread 1
	SightRange = 55,
	SightHalfAngleDeg = 50,
	CatchRadius = 7,
	HuntSpeedMul = 1.2, -- while it has seen you
	HuntSeconds = 7, -- how long it keeps coming after losing sight
	-- Hard ceiling, as a fraction of Config.Player.WalkSpeed. 0.65 * 20 = 13 studs/s, which the
	-- curve above never reaches (12.48 at dread 1 while hunting) — the ceiling is a guard rail,
	-- not the operating point. A fleeing player gains at least 7.5 studs/s, i.e. more than a
	-- room's width over one hunt window, which is what makes running an actual escape.
	MaxSpeedFraction = 0.65,
}

-- ------------------------------------------------------------------ The night itself
Config.Night = {
	StartNight = 1,
	MaxNight = 500,
	-- The manor "wakes up" over DreadSeconds; at dread 1 you are thrown out empty-handed.
	DreadSeconds = 210,
	DreadPerNight = -3, -- nights get shorter (negative = less time), floored by DreadMin
	DreadMin = 110,
	StartStash = 0,
}

-- ------------------------------------------------------------------ Safehouse upgrades
-- `per` is the effect granted PER LEVEL. Effect keys are fixed and read by name in
-- Upgrades.effects — a typo'd key would silently do nothing, so the spec asserts every key
-- used here is one the aggregator knows. Every id needs an UPGRADE_PROPS entry in the server.
Config.Upgrades = {
	Catalog = {
		{ id = "lanterns", name = "Safehouse Lanterns", blurb = "Light you can carry into the manor.", max = 5, baseCost = 40, costMul = 1.6, per = { lampRadius = 6 } },
		{ id = "wardstones", name = "Wardstones", blurb = "The manor wakes up slower.", max = 5, baseCost = 60, costMul = 1.7, per = { dreadSlow = 0.07 } },
		{ id = "beartraps", name = "Bear Traps", blurb = "The Nightwatcher walks slower.", max = 5, baseCost = 75, costMul = 1.75, per = { watcherSlow = 0.05 } },
		-- The bell HEARS. Watcher.hears has no facing argument and no sight argument, so it cannot
		-- know whether you have been noticed; what it does is ring when something walks close by,
		-- through walls and behind its back, which sight cannot do. The blurb used to promise the
		-- other thing ("Warns you sooner that it has seen you") — 120 relics for a product the code
		-- does not sell. 25 studs clears the 20-stud half-room, so level 1 reaches next door.
		{ id = "alarmbell", name = "Alarm Bell", blurb = "Rings when something is close, through walls and around corners.", max = 3, baseCost = 120, costMul = 1.9, per = { warnRange = 25 } },
		{ id = "relicvault", name = "Relic Vault", blurb = "Every relic banks for more.", max = 5, baseCost = 100, costMul = 1.8, per = { relicValue = 0.15 } },
		{ id = "lockbox", name = "Lockbox", blurb = "Keep some of your haul when caught.", max = 3, baseCost = 150, costMul = 2, per = { keepOnCaught = 0.2 } },
		{ id = "floodlights", name = "Floodlights", blurb = "Buys you more time in the manor.", max = 4, baseCost = 200, costMul = 1.9, per = { extractSeconds = 15 } },
	},
	-- Hard ceilings on the AGGREGATED effect. Without these a long enough grind turns
	-- dreadSlow or watcherSlow into "the night never ends" / "it never moves".
	MaxDreadSlow = 0.5,
	MaxWatcherSlow = 0.4,
	MaxKeepOnCaught = 0.6,
}

-- ------------------------------------------------------------------ Safehouse hub geometry
Config.Hub = {
	Size = 60, -- square studs of safehouse floor
	WallHeight = 14,
	PadSize = 7, -- one upgrade pad, square studs
	-- Where the manor is built relative to the player's zone origin. Far enough that the
	-- safehouse is never visible from inside the manor.
	ManorOffset = { 0, 0, -400 },
}

-- Per-player zones are spaced this far apart along +X. Indices are RECYCLED on leave so a
-- long-lived server never marches out to where float precision falls apart.
Config.ZoneSpacing = 3000

-- ------------------------------------------------------------------ Persistence
Config.Save = {
	Store = "NightwatchManor_v1",
	LeaderStore = "NightwatchManorBest_v1", -- OrderedDataStore, best night survived
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
}

-- ------------------------------------------------------------------ Server loop
-- The night is driven by a `task.wait` loop, NOT by RunService.Heartbeat, and dread is
-- accumulated from the value `task.wait` returns rather than read off a wall clock. That keeps
-- the whole loop testable: the headless emulator drives a virtual clock, so a real-time read
-- would sit at zero for an entire simulated night.
Config.TickSeconds = 0.1 -- watcher movement + sight checks
Config.PushEverySeconds = 0.5 -- how often the HUD gets a fresh dread/loot readout
Config.BeatSeconds = 2.5 -- the pause after a night ends, before you are back in the safehouse

return Config
