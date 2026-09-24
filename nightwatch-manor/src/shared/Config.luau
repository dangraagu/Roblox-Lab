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

-- ================================================================== THE NIGHTS ESCALATE (client only)
-- Everything below is read by src/client/Haunt.client.luau + src/shared/HauntArt.luau, which run on
-- the CLIENT and build nothing the server sees. The server does not read any of it. See EYECANDY.md.
--
-- PROGRESS is the night number the server credits (State.night), nudged forward by dread while a night
-- runs (Nightfall.progress), never time. A band's `from` is a NIGHT; it fades in over `fade` of the
-- night before it, as that night's dread rises, so the manor visibly wakes up toward what comes next.
--
-- FAIRNESS (Nightfall.fairness, enforced at load: an unfair config switches the lighting blend OFF and
-- keeps the server's preset). The chase was tuned under Fx.Presets.Horror; every band's visibility
-- fields stay inside a hard envelope around it, no band tints the whole screen red, and no cosmetic
-- glow uses the Nightwatcher's own light colours. Colours are {r, g, b}.
Config.Env = {
	DreadLookahead = 0.9, -- how far toward the next night a full-dread night looks (capped below 1)
	HalfLife = 0.7, -- seconds: every blended value glides, so a night starting or ending never cuts
	LightingHz = 10,
	-- The Nightwatcher's own lights, exactly as Main.server builds them (head: 255,70,70; lamp: GHOST).
	-- robloxemu/check_nightwatchmanor_haunt.luau asserts the built model still uses these, so the rule
	-- below cannot drift away from the monster it protects.
	WatcherSignature = { { 255, 70, 70 }, { 150, 200, 210 } },
	-- The Servants' Exit's green light (the ExitLamp and the lights on it and on the ExitDoor), exactly as Main.server
	-- builds it and pinned the same way. Review 4: the ghosts glowed (120, 255, 140), 35 from it; a green light coming
	-- through a wall must never pass for the one beacon that means "the way out".
	ExitSignature = { { 120, 220, 140 } },
	Fairness = {}, -- empty = the hard envelope in Nightfall.HARD; values here may only tighten it
	FlickerAmp = 0.22, -- the deepest a room light ever flickers: 0.78 of what the server built, at worst
	FlickerDreadGain = 0.6, -- how much of that depth dread adds on top of the band's own
	FlashBoost = 0.12, -- colour-grade brightness a lightning flash adds, for 0.12 s
	BlinkHz = 2, -- the hazard's amber light and its locked marker; Nightfall.HARD.BlinkHzMax caps it
	-- colours of cosmetic glows that are not per band (rain: the drops on the glass; a paler blue than
	-- (190, 200, 225), which was 43 from the lamp's colour, measured by check_nightwatchmanor_budget.luau;
	-- ghost / ghostHalo: the will-o'-wisp and the wraith's eyes, a violet ghost-light, 78 / 74 from the lamp and
	-- 149 / 148 from the exit's green)
	Glow = { hazardBlink = { 255, 170, 40 }, ringTrack = { 255, 210, 60 }, ringLocked = { 255, 120, 20 }, fire = { 255, 150, 60 }, rain = { 210, 214, 236 },
		ghost = { 170, 140, 255 }, ghostHalo = { 205, 180, 255 } },

	-- windows are closed picture-boxes on the inside of OUTER walls (Nightfall.outerFaces)
	Window = { Width = 7, Height = 6, CentreY = 7.5, Along = 6, Inset = 0.55 },
	-- a room's own feature wall gets no window: the chapel's stained glass, the library's shelves
	WindowSkip = { chapel = { { 0, -1 } }, library = { { 1, 0 }, { -1, 0 } } },
	WindowRange = 70, -- studs from the camera: nearer windows are built, farther ones unparented
	PortraitRange = 60,
	EyeShift = 0.14, -- studs a pupil slides across its canvas toward the player

	-- ---------------------------------------------------------------- the bands (by NIGHT)
	-- Band 1 IS the server's Horror preset, so the client's takeover is seamless. `glow` colours are
	-- checked against WatcherSignature; `outside` is what the windows show (moon size, mist / stars / cloud /
	-- eclipse as 0..1, rain in drops per second); `inside` is the manor's mood (dust motes per second, flicker
	-- 0..1 of FlickerAmp, curtain sway in degrees, portrait-eye glow 0..1). Every band sets every key: a key
	-- only one side of a blend has would SNAP when the fade reaches half-way (EnvBands.lerp), not glide.
	Bands = {
		{
			id = "quiet", name = "Quiet Night", emoji = "🌙", from = 0, fade = 0,
			lighting = { Ambient = { 20, 22, 30 }, OutdoorAmbient = { 15, 18, 28 }, Brightness = 1, ExposureCompensation = -0.15 },
			atmosphere = { Density = 0.42, Offset = 0.1, Color = { 90, 100, 120 }, Decay = { 30, 34, 46 }, Glare = 0.1, Haze = 1.6 },
			bloom = { Intensity = 0.5, Size = 24, Threshold = 1.1 },
			colorCorrection = { Brightness = -0.02, Contrast = 0.18, Saturation = -0.35, TintColor = { 200, 210, 235 } },
			glow = { sky = { 26, 34, 62 }, moon = { 226, 230, 242 }, corona = { 214, 244, 196 }, eyes = { 230, 200, 90 }, flash = { 205, 215, 255 }, dust = { 220, 225, 235 } },
			outside = { moonSize = 1.0, mist = 0.12, rain = 0, stars = 1, cloud = 0.1, eclipse = 0 },
			inside = { dust = 3, flicker = 0.25, sway = 2, eyes = 0.15 },
			hazards = {},
		},
		{
			id = "mist", name = "The Mist Rises", emoji = "🌫️", from = 3, fade = 0.9,
			lighting = { Ambient = { 22, 24, 30 }, OutdoorAmbient = { 18, 20, 26 }, Brightness = 1, ExposureCompensation = -0.14 },
			atmosphere = { Density = 0.44, Offset = 0.12, Color = { 112, 118, 128 }, Decay = { 40, 44, 52 }, Glare = 0.05, Haze = 1.8 },
			bloom = { Intensity = 0.6, Size = 26, Threshold = 1.05 },
			colorCorrection = { Brightness = -0.02, Contrast = 0.17, Saturation = -0.4, TintColor = { 205, 212, 224 } },
			glow = { sky = { 52, 58, 70 }, moon = { 214, 214, 216 }, corona = { 214, 244, 196 }, eyes = { 230, 205, 100 }, flash = { 205, 215, 255 }, dust = { 214, 218, 222 } },
			outside = { moonSize = 0.9, mist = 0.75, rain = 0, stars = 0.3, cloud = 0.3, eclipse = 0 },
			inside = { dust = 5, flicker = 0.4, sway = 4, eyes = 0.3 },
			hazards = { "bats" },
		},
		{
			id = "rain", name = "Rain on the Glass", emoji = "🌧️", from = 6, fade = 0.9,
			lighting = { Ambient = { 20, 23, 32 }, OutdoorAmbient = { 16, 19, 30 }, Brightness = 1, ExposureCompensation = -0.15 },
			atmosphere = { Density = 0.43, Offset = 0.1, Color = { 84, 96, 118 }, Decay = { 28, 34, 50 }, Glare = 0.05, Haze = 1.7 },
			bloom = { Intensity = 0.6, Size = 26, Threshold = 1.05 },
			colorCorrection = { Brightness = -0.02, Contrast = 0.2, Saturation = -0.38, TintColor = { 194, 206, 234 } },
			glow = { sky = { 30, 38, 58 }, moon = { 214, 214, 204 }, corona = { 214, 244, 196 }, eyes = { 232, 206, 96 }, flash = { 205, 215, 255 }, dust = { 210, 218, 232 } },
			outside = { moonSize = 0.8, mist = 0.45, rain = 28, stars = 0, cloud = 0.7, eclipse = 0 },
			lightning = { everyMin = 18, everyMax = 34, bolt = false },
			inside = { dust = 4, flicker = 0.5, sway = 6, eyes = 0.4 },
			hazards = { "bats", "wisp" },
		},
		{
			id = "storm", name = "Thunderstorm", emoji = "⛈️", from = 10, fade = 0.9,
			lighting = { Ambient = { 22, 22, 34 }, OutdoorAmbient = { 18, 18, 32 }, Brightness = 1, ExposureCompensation = -0.14 },
			atmosphere = { Density = 0.43, Offset = 0.1, Color = { 92, 88, 122 }, Decay = { 34, 30, 52 }, Glare = 0.08, Haze = 1.7 },
			bloom = { Intensity = 0.7, Size = 28, Threshold = 1.0 },
			colorCorrection = { Brightness = -0.01, Contrast = 0.22, Saturation = -0.3, TintColor = { 196, 198, 240 } },
			glow = { sky = { 34, 28, 64 }, moon = { 216, 212, 228 }, corona = { 214, 244, 196 }, eyes = { 236, 210, 100 }, flash = { 214, 222, 255 }, dust = { 212, 214, 236 } },
			outside = { moonSize = 0.7, mist = 0.35, rain = 44, stars = 0, cloud = 1, eclipse = 0 },
			lightning = { everyMin = 6, everyMax = 14, bolt = true },
			inside = { dust = 5, flicker = 0.7, sway = 10, eyes = 0.55 },
			hazards = { "crockery", "bats" },
		},
		{
			id = "blood", name = "Blood Moon", emoji = "🩸", from = 20, fade = 0.9, celebrate = true,
			lighting = { Ambient = { 26, 20, 26 }, OutdoorAmbient = { 24, 14, 20 }, Brightness = 1, ExposureCompensation = -0.13 },
			atmosphere = { Density = 0.44, Offset = 0.12, Color = { 118, 84, 96 }, Decay = { 56, 24, 34 }, Glare = 0.12, Haze = 1.8 },
			bloom = { Intensity = 0.8, Size = 30, Threshold = 0.98 },
			colorCorrection = { Brightness = -0.01, Contrast = 0.22, Saturation = -0.2, TintColor = { 214, 196, 210 } },
			glow = { sky = { 46, 12, 22 }, moon = { 150, 20, 25 }, corona = { 214, 244, 196 }, eyes = { 242, 176, 60 }, flash = { 222, 214, 255 }, dust = { 226, 176, 150 } },
			outside = { moonSize = 1.6, mist = 0.5, rain = 0, stars = 0.5, cloud = 0.25, eclipse = 0 },
			lightning = { everyMin = 14, everyMax = 26, bolt = true },
			inside = { dust = 6, flicker = 0.8, sway = 8, eyes = 0.85 },
			hazards = { "wraith", "crockery" },
		},
		{
			id = "witching", name = "The Witching Hour", emoji = "🕯️", from = 40, fade = 0.9,
			lighting = { Ambient = { 20, 26, 24 }, OutdoorAmbient = { 14, 22, 18 }, Brightness = 1, ExposureCompensation = -0.12 },
			atmosphere = { Density = 0.45, Offset = 0.14, Color = { 84, 110, 96 }, Decay = { 24, 44, 34 }, Glare = 0.1, Haze = 1.9 },
			bloom = { Intensity = 0.9, Size = 32, Threshold = 0.95 },
			colorCorrection = { Brightness = -0.01, Contrast = 0.24, Saturation = -0.25, TintColor = { 198, 218, 206 } },
			glow = { sky = { 16, 34, 26 }, moon = { 20, 22, 24 }, corona = { 214, 244, 196 }, eyes = { 196, 240, 90 }, flash = { 190, 255, 206 }, dust = { 200, 232, 150 } },
			outside = { moonSize = 1.4, mist = 0.8, rain = 34, stars = 0.2, cloud = 0.8, eclipse = 1 },
			lightning = { everyMin = 5, everyMax = 11, bolt = true },
			inside = { dust = 7, flicker = 1.0, sway = 12, eyes = 1.0 },
			hazards = { "wraith", "crockery", "wisp", "bats" },
		},
	},
	FlagshipBandId = "blood", -- the one the pacing spec holds to 30-45 minutes of play

	-- ---------------------------------------------------------------- the safehouse grows cosier
	-- By HUB LEVEL (the sum of upgrade levels, max 30), shown in the State payload. Props are local,
	-- non-collidable and stand along the north wall and the corners, clear of the pads and the door.
	Cosy = {
		{ id = "bare", name = "Bare Shelter", minLevel = 0 },
		{ id = "kindled", name = "Hearth Kindled", minLevel = 2 },
		{ id = "homely", name = "Homely", minLevel = 6 },
		{ id = "cosy", name = "Cosy", minLevel = 12 },
		{ id = "haven", name = "Haven", minLevel = 20 },
	},
}

-- ================================================================== hazards (client only, NIGHT only)
-- Rare, telegraphed apparitions that come at you through the walls: ghosts, so walls do not stop them.
-- A hit knocks you down for KnockSeconds; it takes nothing (relics, dread and the night are the
-- server's and it never hears of a hazard). They exist to be SEEN and dodged, not to decide a night:
--   * one every IntervalMin..IntervalMax seconds of NIGHT: the clock is frozen in the day, and while the
--     Nightwatcher sees you (and for QuietAfterSpottedSeconds after, longer than its HuntSeconds, validated)
--     it keeps running but HOLDS the launch (Nightfall.hazardClock). Review 4: with the clock frozen for chases
--     too, the old 25-40 s came to one hazard per 1.2 minutes in the manor, more for a player who hid well; now
--     it is one per 2.5 manor-minutes for every player profile (tests/Pacing.spec.luau);
--   * a hazard in flight is called off the moment it sees you, and a knock ends at that moment too;
--   * a knock is slower than walking (KnockSpeedFractionMax x WalkSpeed, validated) and never lifts;
--   * the ring on the floor is where it will land, placed where you are walking (LeadSeconds ahead):
--     stop, turn or step out of it and it misses. Stepping out works in every direction;
--   * the warning covers the EARLIEST hit, not the arrival: telegraph - (hitRadius + PlayerRadius) / speed
--     is at least 3 s for every kind (Nightfall.validateHazards; the headless check measured a 3.0 s
--     crockery telegraph landing its hit 2.87 s after the warning, which is why these are 3.2-3.6).
-- Validated by Hazards.validate (template) and Nightfall.validateHazards (the chase rules); an invalid
-- config switches hazards OFF with a warning. Rarity is measured in tests/Pacing.spec.luau.
Config.Hazards = {
	IntervalMin = 120, -- seconds of NIGHT time (frozen in the day; held, not frozen, while hunted)
	IntervalMax = 180,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.3,
	MaxRetargetSpeed = 1.6,
	SpreadDegrees = 35,
	ViewPitchDegrees = 20,
	KindFitDegrees = 15,
	ElevationMin = -2, -- the room's height band, as seen from the player: never out of the floor
	ElevationMax = 12,
	AimJitter = 0.6,
	PlayerRadius = 2,
	KnockLift = 0,
	KnockSeconds = 0.8,
	KnockSpeedFractionMax = 0.8,
	LeadSeconds = 1.0,
	QuietAfterSpottedSeconds = 10,
	Kinds = {
		bats = { speed = 18, telegraph = 3.3, commit = 1.5, pass = 1.5, hitRadius = 1.8, knock = 14, pitch = 6, pitchSpread = 4 },
		wisp = { speed = 12, telegraph = 3.6, commit = 1.7, pass = 1.5, hitRadius = 1.6, knock = 10, pitch = 2, pitchSpread = 2 },
		crockery = { speed = 22, telegraph = 3.2, commit = 1.4, pass = 1.2, hitRadius = 1.7, knock = 15, pitch = 4, pitchSpread = 3 },
		wraith = { speed = 26, telegraph = 3.2, commit = 1.4, pass = 1.5, hitRadius = 2.0, knock = 16, pitch = 8, pitchSpread = 3 },
	},
}

-- ================================================================== rest: between rounds, never inside one
-- The night is a timed round: dread and the Nightwatcher are the server's and never pause, so there is
-- nothing to rest from inside the manor and nothing a rest could honestly promise there. The safehouse
-- IS the break room: sit by the fire as long as you like, nothing runs, nothing is lost. Phases.NIGHT is
-- rejected by Nightfall.validateRest; WakeOnMove / BlockWhileThreat are the template's own rules.
Config.Rest = {
	Phases = { DAY = true },
	WakeOnMove = true,
	BlockWhileThreat = true,
	RequireGrounded = true,
	IdleSeconds = 45, -- stand still in the safehouse this long and you doze by the fire (no sit)
	PendingSeconds = 6,
	WakeGraceSeconds = 0.4,
}

-- ================================================================== budgets (client, measured)
-- Checked every frame by robloxemu/check_nightwatchmanor_budget.luau; measured numbers in EYECANDY.md.
Config.Budget = {
	MaxParts = 160, -- client-built parts parented at once
	MaxEmitters = 3,
	MaxWeatherEmitters = 2,
	MaxEmitterRate = 60, -- particles per second, summed
	MaxLights = 3, -- PointLights the client creates (flicker reuses the server's; it creates none)
	MaxHazards = 1,
	MaxWindowsShown = 6,
	MaxPortraitsShown = 4,
}

-- ================================================================== pacing (tests only)
-- The human half of tests/NightModel.luau, written down instead of hidden in a number. The model plays
-- the real rules (Manor, Watcher, Night, Upgrades) forward; these are the parts of a person it cannot
-- know. When real session data exists, retune these first, then the bands' `from`.
Config.Pacing = {
	NearHitStuds = 8, -- a hazard that passes this close counts as a near-hit
	Profiles = {
		-- seconds to get your bearings at night start; seconds stood at each pedestal pressing E;
		-- seconds you keep running after it last saw you; the dread at which you head for the exit;
		-- relics you try for; after how many sightings you stop looting and get out; how long you will
		-- wait out of sight for its patrol to leave the next room; seconds in the safehouse per night
		-- (walk to the door, look around) and per purchase; after how many failures on one night you
		-- stop being careful and dash for the exit, and the dread at which you do the same inside a night
		normal = { startSeconds = 1.5, promptSeconds = 1.2, fleeSeconds = 8, leaveAtDread = 0.6, relicsPerNight = 99, leaveAfterSpotted = 2, patienceSeconds = 8, retriesBeforeDash = 3, dashAtDread = 0.8, daySeconds = 12, buySeconds = 5 },
		fast = { startSeconds = 0.8, promptSeconds = 0.8, fleeSeconds = 8, leaveAtDread = 0.75, relicsPerNight = 99, leaveAfterSpotted = 3, patienceSeconds = 5, retriesBeforeDash = 2, dashAtDread = 0.85, daySeconds = 7, buySeconds = 3 },
		slow = { startSeconds = 3, promptSeconds = 2, fleeSeconds = 10, leaveAtDread = 0.45, relicsPerNight = 3, leaveAfterSpotted = 1, patienceSeconds = 12, retriesBeforeDash = 4, dashAtDread = 0.7, daySeconds = 20, buySeconds = 8 },
	},
}

return Config
