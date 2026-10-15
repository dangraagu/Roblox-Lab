--!strict
-- Config.luau: every tunable in Gnome Garden Defense, in one place (DESIGN.md §3).
--
-- Pure data, no Roblox globals: the server, the clients, the pure modules (Garden, PathGen, Waves) and the
-- tests/ model all read this same table. Colours are {r, g, b} (0-255), never Color3, so the luau CLI can
-- read them. The balance numbers below (Tile .. WaveCount, Hazards' clock, Pacing) were measured with
-- tests/GardenModel.luau + tests/Pacing.spec.luau; change one and re-run tests/Pacing.spec.luau.

local Config = {}

--============================================================================ the garden (DESIGN.md §2, §3.1)
Config.Tile = 8          -- studs per bed cell; a pad is 7x7 on an 8-stud pitch (tap target)
Config.GridW = 12        -- cells, hedge gap (x = 0) to carrot patch (x = 11)
Config.GridH = 9
Config.PathCells = 30    -- EXACT path length, 240 studs: no bed is easier by luck (Pacing.spec)
Config.Dt = 0.1          -- the server's fixed simulation step, seconds (the model runs the same step)
Config.Carrots = 20      -- lives per attempt
Config.BuildSeconds = 20 -- build phase between waves; READY skips it. The FIRST wave of an attempt waits for READY
Config.AfkHoldSeconds = 180 -- the build timer starts the next wave only if the gardener acted in the last 180 s
Config.MaxGnomes = 14    -- per bed: with HpGrowth, the wall that bounds the endless board
Config.SellRefund = 0.7  -- of everything paid into a gnome, once the bed's first wave has come
Config.RevealRefund = 1  -- before it (the reveal) a sale gives everything back: trying pads costs nothing. At 0.7
                         -- five plant/sell tries left a spring bed with 45 seeds and no gnome: READY refused,
                         -- nothing affordable, no way on (REVIEW-1)
Config.SpawnGap = 0.9    -- seconds between two bugs of a wave
Config.HpGrowth = 1.075  -- bug hit points x this per wave
Config.BountyExp = 0.4   -- bounty grows with hpMult^BountyExp: income rises inside a chapter, slower than HP
Config.ClearBonus = 15   -- seeds for surviving a wave ...
Config.ClearBonusPerWave = 3 -- ... + this x the wave's number inside its chapter (1..10)
Config.WavesPerChapter = 10
-- Progress inside a running wave stops at (wave - 1) + this: the boundary (a band, the brag) is reached only when
-- the wave is survived. The server publishes 3 decimals, so this must stay under 0.9995.
Config.ProgressInWaveMax = 0.999

-- Start budget per chapter (every attempt starts here on a FRESH bed, nothing carries over).
-- Chapter 5 is endless, on the day's shared bed. `name` is the season the HUD shows.
Config.Chapters = {
	{ id = "spring", name = "Spring", seeds = 120, unlock = { "pebble", "sprinkler" }, boss = "stag" },
	{ id = "summer", name = "Summer", seeds = 420, unlock = { "mushroom" }, boss = "baron" },
	{ id = "autumn", name = "Autumn", seeds = 800, unlock = { "lantern" }, boss = "queen" },
	{ id = "frost", name = "Frost", seeds = 1500, unlock = {}, boss = "mantis" },
	{ id = "moonlit", name = "Moonlit Bed", seeds = 2600, unlock = {}, endless = true },
}

-- Gnomes. levels[1] is the planting price; levels[2..3] are upgrade prices. No upgrade drops a gnome
-- below 95% of planting's damage per seed paid (lowest: pebble L2, 97.2%; Economy.spec).
--   pebble: single target, first in range.   sprinkler: pulses, slows + light damage to all in range.
--   mushroom: splash around its target.       lantern: pierces armour, aims at the toughest in range.
Config.Gnomes = {
	pebble = { order = 1, name = "Pebble", blurb = "slingshot", target = "first", levels = {
		{ cost = 50, dmg = 6, cd = 0.8, range = 14 },
		{ cost = 70, dmg = 14, cd = 0.8, range = 15 },
		{ cost = 130, dmg = 28, cd = 0.7, range = 16 },
	} },
	sprinkler = { order = 2, name = "Sprinkler", blurb = "slows bugs", target = "pulse", levels = {
		{ cost = 60, dmg = 2, cd = 1.0, range = 12, slow = 0.55, slowFor = 1.5 },
		{ cost = 60, dmg = 5, cd = 1.0, range = 13, slow = 0.45, slowFor = 1.5 },
		{ cost = 110, dmg = 10, cd = 1.0, range = 14, slow = 0.40, slowFor = 1.5 },
	} },
	mushroom = { order = 3, name = "Mushroom", blurb = "spore splash", target = "first", splash = 7, levels = {
		{ cost = 110, dmg = 10, cd = 1.5, range = 13 },
		{ cost = 120, dmg = 22, cd = 1.5, range = 13 },
		{ cost = 220, dmg = 48, cd = 1.3, range = 14 },
	} },
	lantern = { order = 4, name = "Lantern", blurb = "pierces armour", target = "toughest", pierce = true, levels = {
		{ cost = 150, dmg = 45, cd = 2.0, range = 18 },
		{ cost = 160, dmg = 95, cd = 2.0, range = 20 },
		{ cost = 300, dmg = 170, cd = 1.8, range = 22 },
	} },
}
-- The pads that glow: the Count free pads that see the most path for a level-1 Kind gnome (PathGen.bestPads), all
-- game long while there is room for a gnome. The pacing model's NORMAL player plants on one of them (DESIGN.md
-- §4); REVIEW-2: the game showed them only until the first gnome stood, so the brag's minutes assumed knowledge
-- the screen did not give.
Config.Glow = { Count = 3, Kind = "pebble" }
-- The gnome the game suggests (Garden.suggestKind: the sheet stars it, the pads glow for it): the unlocked kind
-- furthest below its share of these weights. They are the normal profile's mix (DESIGN.md §4), now shown to the
-- player instead of assumed of them (REVIEW-2).
Config.Suggest = { pebble = 4, sprinkler = 1.5, mushroom = 2, lantern = 1.5 }
Config.ArmorFloor = 0.25 -- an armoured bug still takes at least this share of a hit

-- Bugs at hpMult 1. bite = carrots eaten if it reaches the patch. firstWave = when it joins the mix.
-- A boss bites 20 = the whole patch: a chapter is won only by STOPPING its boss.
Config.Bugs = {
	aphid = { name = "Aphid", hp = 24, speed = 6, bounty = 3, bite = 1, firstWave = 1, weight = 1.0 },
	ant = { name = "Ant", hp = 14, speed = 10, bounty = 2, bite = 1, firstWave = 3, weight = 0.6 },
	beetle = { name = "Beetle", hp = 60, speed = 4.5, armor = 2, bounty = 6, bite = 2, firstWave = 6, weight = 0.35 },
	wasp = { name = "Wasp", hp = 34, speed = 9, bounty = 5, bite = 2, firstWave = 12, weight = 0.4 },
	snail = { name = "Snail", hp = 120, speed = 3, bounty = 10, bite = 3, firstWave = 15, weight = 0.25, slowImmune = true },
	stag = { name = "Stag Beetle", hp = 420, speed = 3, armor = 2, bounty = 120, bite = 20, boss = true },
	baron = { name = "Snail Baron", hp = 600, speed = 2.5, bounty = 160, bite = 20, boss = true, slowHalf = true },
	queen = { name = "Slug Queen", hp = 1000, speed = 2.2, armor = 2, bounty = 220, bite = 20, boss = true, slowHalf = true },
	mantis = { name = "Frost Mantis", hp = 680, speed = 2.6, armor = 3, bounty = 260, bite = 20, boss = true, slowHalf = true },
}
Config.BossCycle = { "stag", "baron", "queen", "mantis" } -- waves 10, 20, 30, 40, then repeating
Config.WaveCount = { base = 8, perWave = 0.5 }              -- count(n) = base + floor((n - 1) * perWave)

--============================================================================ the model's player profiles
-- tests/GardenModel.luau plays these; the game never reads them. Written down so a reader can disagree.
Config.Pacing = {
	BragWave = 30,          -- the Slug Queen falls: HARVEST MOON
	BragMinutes = { 30, 45 },
	LongTermWave = 50,      -- the Aurora band, in the endless chapter
	-- think = seconds between two decisions; buildSeconds = how long they let a build phase run (READY
	-- earlier); introSeconds = at least this long on a new bed before READY (they also keep planting until
	-- their next plan is unaffordable); outroSeconds = the chapter fanfare; retrySeconds = the lost screen.
	-- padTop = they plant on one of the N best pads for that gnome; glow = they plant on one of the pads the
	-- game lights (Config.Glow, PathGen.bestPads: what a player sees; REVIEW-2). grow = gnomes they want per
	-- chapter before they start upgrading. policy "value" = plant/upgrade by damage per seed over covered path.
	Profiles = {
		weak = { think = 4.0, buildSeconds = 20, introSeconds = 30, outroSeconds = 20, retrySeconds = 15,
			padTop = 8, grow = { 6, 8, 10, 12, 12 }, mix = { pebble = 4, sprinkler = 2, mushroom = 2, lantern = 1 } },
		normal = { think = 2.5, buildSeconds = 14, introSeconds = 25, outroSeconds = 15, retrySeconds = 10,
			glow = true, grow = { 5, 7, 9, 11, 12 } }, -- glow: the starred gnome (Config.Suggest) on a glowing pad
		strong = { policy = "value", think = 1.0, buildSeconds = 6, introSeconds = 15, outroSeconds = 8, retrySeconds = 5 },
	},
}

--============================================================================ server, network, world
Config.Net = {
	TickHz = 10,             -- GardenTick to the garden's owner while bugs are out
	MaxStepsPerFrame = 5,    -- a lagging server slows both sides of a garden equally, never skips ahead
	RateBurst = 20,          -- every client action shares one token bucket per player ...
	RatePerSecond = 10,      -- ... refilling 10 per second (a human taps a few per second)
	PauseCooldown = 0.5,     -- SetPaused(true) at most every 0.5 s. A RESUME is never refused by it: the client's
	                         -- Rest wakes 0.4 s after a pause when the gardener moves, and that wake must land
	                         -- (REVIEW-2: it was refused with "Slow down a little")
	-- "Here": the gardener's OWN input (thumbstick, keys, a tap or click), reported by their client at most every
	-- HereSeconds while it lasts. It is what "the gardener is here" means for the AFK hold. REVIEW-2: the server
	-- used to poll the character and took any 4-stud move as the gardener's, so a neighbour's shove (or a fling)
	-- resumed a paused garden and ended an absent gardener's AFK hold. A move is not an input.
	HereSeconds = 5,
	HereMinGap = 1,          -- the server notes at most one Here a second per gardener (never answered: no echo)
	RepeatToastSeconds = 1,  -- "Slow down" / "still being dug" are said at most once a second: a flood of
	                         -- refused calls was echoed one toast per call (REVIEW-1: 2000 calls, 1999 toasts)
}

Config.World = {
	Slots = 8,               -- one garden per player, 8 players per server
	SlotColumns = 4,
	SlotPitchX = 160,        -- studs between two slots' origins (the 140 x 130 footprint plus a gap)
	SlotPitchZ = 170,
	BedY = 0,                -- top of the lawn
	PadSize = 7,
	DeckDepth = 16,          -- the deck along the bed's south edge: 96 x 16 studs
	DeckGap = 4,             -- lawn between the bed's last row and the deck
	DeckY = 1,               -- deck top
	HedgeMargin = 16,        -- hedge this far outside the bed and the deck
	HedgeHeight = 7,
	PatchLength = 16,        -- the carrot patch east of the bed's last column
	BoardX = 8,              -- the highscore board's centre: 8 studs in from the deck's west end ...
	BoardBack = 3,           -- ... 3 studs in from its south edge, facing south (the garden view's camera)
	MeadowMargin = 120,      -- the meadow under every slot reaches this far past the outer hedges: a step through
	                         -- the hedge gap (or a jump over a hedge) lands on grass, not in the void (REVIEW-1)
	MeadowDrop = 0.2,        -- its top sits this far below the lawns (no two faces in one plane)
}

Config.Save = {
	Enabled = true,
	Store = "GnomeGarden_v1",           -- { data, session, jobId, lockUntil } per u_<userId>
	Leaderboard = "GnomeGarden_LB_v1",  -- OrderedDataStore, u_<userId> -> Board.encode(bestWave, bestAt)
	Daily = "GnomeGarden_Daily_v1",     -- d_<utcDay> -> the endless bed's seed, drawn by the first server that day
	AutosaveSeconds = 20,               -- also renews the session lock; must be < SessionLockSeconds
	SessionLockSeconds = 45,
	-- A session that could not take the record (another server's lock, or a failed read) keeps trying, 2 s after
	-- join and then every 4, 8, 10, 10 ... s, so a crashed server's lock (45 s) costs at most ~10 s of saving
	-- once it runs out. It never writes before it has read the real record (REVIEW-1).
	RetryFirstSeconds = 2,
	RetryMaxSeconds = 10,
	DailyTries = 3,                     -- the day's endless bed: asked up to 3 times (1 s, then 2 s apart) ...
	DailyFallbackSeconds = 60,          -- ... and if the store is down, a bed of this server's own for 60 s, then
	                                    -- asked again (it was cached for the whole UTC day: REVIEW-1). The
	                                    -- server's own bed is ONE per day: a new one on each ask let a gardener
	                                    -- reroll the endless bed during an outage (REVIEW-2)
	Version = 1,
}

-- The highscore board (docs/complete-game-standard.md §3): +1 Jump's values and reasons.
Config.Board = {
	PublicRows = 10,
	PublicCacheSeconds = 60,
	FriendsRows = 10,
	FriendsCap = 200,
	FriendsCacheSeconds = 300,
	ScoreCacheSeconds = 120,
	ReadsBurst = 40,
	ReadsPerSecond = 1,
	BudgetReserve = 10,
	MaxMetric = 4000000,        -- 4e6 * 2e9 < 2^53: exact in a double
	PromptDistance = 9,
	-- one Public/Friends toggle per this many seconds per player: the prompt answered every trigger with a payload
	-- (REVIEW-2: 2000 triggers in one instant, 2001 payloads; 500 a second for a minute, 30061)
	ToggleSeconds = 0.5,
	Text = {
		Title = "BEST GARDENERS",
		EmptyPublic = "No garden on the board yet. Survive a wave and be the first!",
		FriendsFailed = "Couldn't load your Roblox friends right now. Try again in a minute.",
		NoFriends = "No Roblox friends yet. Friends you add show up here, ranked against you.",
		FriendsNoScores = "None of your %d friends has defended a garden yet. Invite one and race them to the Harvest Moon!",
		FriendsChecking = "Checking your friends: %d of %d so far...",
		Loading = "Loading...",
		Prompt = "Public / Friends",
	},
}

-- Every refusal says why (docs/new-game-checklist.md: no silent no-ops). Garden.luau formats these.
Config.Text = {
	NotEnoughSeeds = "Not enough seeds (need %d, have %d)",
	GardenFull = "Garden full: %d gnomes",
	PadTaken = "That pad is taken",
	NoPad = "That is not one of your pads",
	Locked = "%s unlocks in %s",
	UnknownGnome = "Unknown gnome",
	MaxLevel = "Max level",
	NoGnome = "No gnome there",
	PlantFirst = "Plant a gnome first",
	SeasonOver = "Not now: this season is over",
	PatchLost = "Not now: the bugs ate your carrots. Try again!",
	AlreadyComing = "The bugs are already coming!",
	CantPause = "Can't pause now",
	StandStill = "Stand still, then press PAUSE",
	TooFast = "Slow down a little",
	Dazed = "Seeing stars... %d",
	NoSave = "Progress is not being saved on this server.",
	SavingAgain = "Your progress is being saved again.",
	Restored = "Your saved garden is back: %s.",
	NotReady = "Your garden is still being dug. One moment!",
}

-- The phone-first HUD's geometry, shared by Hud.client (top bar, READY, gnome sheet, result panel) and
-- Garden.client (the band chip + PAUSE row under the top bar, the hazard warning), so the two lay out against
-- the same numbers (robloxemu/check_gnomegardendefense_hud.luau measures them together, overlap rule on).
-- Design px at UIScale 1; every tappable thing grows to >= MinTap SCREEN px on a touch screen.
Config.Hud = {
	TopH = 56, TopHCompact = 48,  -- the top bar: seeds, carrots, wave, next wave / boss
	RowW = 520, RowH = 40,        -- Garden.client's row under it: band chip + PAUSE
	PauseW = 112,
	WarnH = 34,                   -- the hazard warning under that row
	Gap = 8,
	MinTap = 44,
	ReadyW = 150, ReadyH = 60,    -- READY: right edge, vertically centred (never bottom-right: the jump button)
	SheetBtnW = 150, SheetBtnH = 64, SheetTitleH = 26, CloseW = 64,
	ResultW = 560, ResultH = 200,
	-- Roblox's touch controls own the bottom band (Responsive's controlPad): its left ThumbShare (the thumbstick)
	-- and its right JumpShare (the jump button), as robloxemu/emu/hudcheck.luau draws them. Nothing tappable there:
	-- the HUD's buttons, and the garden view's pads (REVIEW-2: the whole-garden view put pads under the thumbstick)
	ThumbShare = 0.35, JumpShare = 0.25,
	-- The garden view keeps every pad out of a WIDER thumbstick frame: the left StickW of the lower StickH of the
	-- screen, where Roblox's DynamicThumbstick takes a touch (as REVIEW-2 recalled PlayerModule: 40% x 2/3; Studio
	-- must confirm it, EYECANDY.md §7). It holds the HUD's own thumbstick corner on every phone (the band is at
	-- most 35% of the height) and costs the overview at most 7% of a cell (GardenCam.spec, 40 beds x 5 phones).
	StickW = 0.4, StickH = 2 / 3,
}

--============================================================================ the garden view (REVIEW-1)
-- Roblox's default camera, 12.5 studs behind the gardener on the deck, drew every pad under 44 px on an 844x390
-- phone (the glowing ones ~4 px tall). View.client takes the camera (Scriptable) and frames the WHOLE garden
-- under the HUD (tests/GardenCam.spec.luau: cells ~19 px on that phone, 44+ on a 1280x720 desktop). A tap picks
-- the pad under the finger, or the nearest within one cell (GardenCam.pickRay); when that cell is smaller than
-- MinTapPx on screen, the view zooms in on it (MinTapPx or more, above the gnome sheet) with the sheet open, so
-- a wrong neighbour is one big tap away. It eases back to the whole garden ZoomIdleSeconds after the sheet
-- closes. A live hazard zooms on the gardener (the red ring is big enough to step out of); a celebrated season
-- band looks up at the sky for SkySeconds; next to the board the camera reads the board; a gardener who walks
-- out of the garden gets Roblox's own camera back until they return.
Config.Camera = {
	Pitch = 58,              -- degrees below the horizon, every garden view
	Fov = 45,                -- vertical field of view of the garden views (a flatter view: far rows shrink less)
	SkyFov = 70,
	MinTapPx = 52,           -- a zoom makes the picked cell at least this tall and wide: at 52 its neighbours are
	                         -- 45.4 px or more too (48 left the row behind at 42.4, under the 44 that picks: REVIEW-2)
	ZoomIdleSeconds = 2.5,
	ZoomPeekSeconds = 6,     -- a zoom from a tap on a small cell (it picks nothing: REVIEW-2) eases back after this
	HalfLife = 0.12,         -- seconds for the camera to cover half of the way to a new view
	SkySeconds = 4.5,
	GnomeHeight = 7,         -- a gnome's body is tappable: a column this tall (an L3 hat tops out at 6.9 studs) ...
	GnomeHalfWidth = 1.5,    -- ... and this far either side of its pad's centre (an L3 body is 2.3 studs wide)
	BoardViewDistance = 12,  -- this close to your own board, the camera turns to read it
	BoardViewBack = 15,
	FreeMargin = 4,          -- this far outside your garden's lawn, the ordinary camera follows you
	Margin = 8,              -- screen px kept clear around the garden in the overview
	ZoneMargin = 4,          -- and between a pad and the touch controls' zones (REVIEW-2: one ended 0.004 px inside)
}

--============================================================================ hazards (EYECANDY.md, DESIGN.md §8)
-- Client-only and harmless to the garden: a hit knocks the gardener down and dazes them for DazeSeconds
-- (the gnome menu greys out). No seeds are lost: measured, a hit that costs seeds decides boss fights.
-- The clock runs on GARDEN time in a band with hazards: waves and build phases, frozen while paused, held,
-- on the reveal and the result screens, never reset. Vertical kinds (Deep Vein's): a top-down camera would
-- start +1 Jump's sideways lanes underground.
Config.Hazards = {
	IntervalMin = 100,
	IntervalMax = 150,
	QuietBeforeWave = 4,        -- the model's rule; the same as band 1 (waves 1-3) having no hazards
	DazeSeconds = 3,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.4,
	WalkSpeed = 16,
	KnockLift = 8,
	KnockSeconds = 0.9,
	AimJitter = 0.8,
	SpreadDegrees = 0,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	-- name = what the warning banner says
	Kinds = {
		acorn = { name = "ACORN", drop = "above", height = 22, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 32 },
		apple = { name = "APPLE", drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 32 },
		pinecone = { name = "PINECONE", drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.5, hitRadius = 1.6, knock = 30 },
		icicle = { name = "ICICLE", drop = "above", height = 20, fall = 0.5, telegraph = 3.2, commit = 1.6, pass = 0.5, hitRadius = 1.6, knock = 32 },
		snowClump = { name = "SNOW CLUMP", drop = "above", height = 18, fall = 0.7, telegraph = 3.4, commit = 1.7, pass = 0.8, hitRadius = 1.6, knock = 30 },
		starShard = { name = "STAR SHARD", drop = "above", height = 22, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 0.6, hitRadius = 1.6, knock = 34 },
		sprinklerJet = { name = "SPRINKLER JET", drop = "below", height = 7, fall = 0.35, telegraph = 3.4, commit = 1.8, pass = 1.2, hitRadius = 1.6, knock = 28 },
		molehill = { name = "MOLEHILL", drop = "below", height = 7, fall = 0.35, telegraph = 3.6, commit = 1.8, pass = 1.2, hitRadius = 1.6, knock = 36 },
	},
}

-- Rest = PAUSE (DESIGN.md §9): +1 Jump's Rest.luau, with idle rest OFF (watching a wave without touching
-- anything is normal play in a tower defence); the AFK hold on the build timer is the AFK safety instead.
-- The server freezes the WHOLE garden (bugs, gnomes, the build timer) and the client freezes the hazard clock.
Config.Rest = {
	IdleSeconds = 0,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 10,    -- outlives the longest hazard (molehill: 3.6 + 1.2 = 4.8 s) by more than 2 s
}

--============================================================================ the seasons (EYECANDY.md)
local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

-- progress p = waves survived + the share of the current wave's bugs already gone (the server's Progress
-- attribute). A band blends in over `fade` waves BEFORE its `from`. Season bands start at their boss wave,
-- so the season turns during the boss fight and is full the instant the boss falls.
Config.Env = {
	HalfLife = 0.6,
	LightingHz = 10,
	BragBandId = "moon",
	Bands = {
		{
			id = "sprouts", from = 0, fade = 0, name = "Spring Sprouts", emoji = "🌱",
			lighting = { ClockTime = 6.6, Brightness = 2.2, ExposureCompensation = 0.2,
				Ambient = rgb(110, 100, 115), OutdoorAmbient = rgb(165, 140, 160),
				FogStart = 120, FogEnd = 700, FogColor = rgb(245, 205, 215) },
			atmosphere = { Density = 0.34, Offset = 0.25, Color = rgb(245, 210, 220), Decay = rgb(200, 150, 170), Glare = 0.3, Haze = 2 },
			sky = { StarCount = 0, SunAngularSize = 20, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.06, Saturation = 0.12, TintColor = rgb(255, 240, 245) },
			sunRays = { Intensity = 0.16, Spread = 0.8 },
			pieces = { "seedlings", "dewTufts" },
			ambient = { { kind = "butterfly", count = 4 } },
			-- a light drift of dandelion fluff: the dawn has its own weather too, and it stays calm (no hazards yet)
			weather = { { kind = "fluff", rate = 4 } },
			hazards = {},
		},
		{
			id = "blossom", from = 3, fade = 1, name = "Blossom Morning", emoji = "🌸",
			lighting = { ClockTime = 9.5, Brightness = 2.8, ExposureCompensation = 0.15,
				Ambient = rgb(120, 120, 130), OutdoorAmbient = rgb(160, 165, 180),
				FogStart = 150, FogEnd = 900, FogColor = rgb(215, 230, 245) },
			atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(210, 225, 245), Decay = rgb(150, 170, 200), Glare = 0.35, Haze = 1.6 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.18, TintColor = rgb(255, 245, 250) },
			sunRays = { Intensity = 0.15, Spread = 0.8 },
			pieces = { "blossomTrees" },
			ambient = { { kind = "butterfly", count = 3 }, { kind = "bee", count = 3 } },
			weather = { { kind = "petals", rate = 8 } },
			hazards = { "acorn" },
		},
		{
			id = "summer", from = 10, fade = 2, name = "High Summer", emoji = "🌻",
			lighting = { ClockTime = 13, Brightness = 3.2, ExposureCompensation = 0.2,
				Ambient = rgb(125, 130, 120), OutdoorAmbient = rgb(165, 175, 150),
				FogStart = 200, FogEnd = 1200, FogColor = rgb(200, 230, 250) },
			atmosphere = { Density = 0.25, Offset = 0.15, Color = rgb(200, 230, 250), Decay = rgb(160, 190, 150), Glare = 0.5, Haze = 1.3 },
			sky = { StarCount = 0, SunAngularSize = 22, MoonAngularSize = 11 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.1, Saturation = 0.28, TintColor = rgb(255, 250, 235) },
			sunRays = { Intensity = 0.2, Spread = 0.75 },
			pieces = { "sunflowers", "bunting" },
			ambient = { { kind = "bee", count = 4 }, { kind = "dragonfly", count = 2 } },
			weather = { { kind = "pollen", rate = 6 } },
			hazards = { "acorn", "sprinklerJet" },
		},
		{
			id = "shower", from = 15, fade = 1, name = "Summer Shower", emoji = "🌦️",
			lighting = { ClockTime = 15, Brightness = 1.8, ExposureCompensation = 0.05,
				Ambient = rgb(105, 100, 120), OutdoorAmbient = rgb(130, 125, 150),
				FogStart = 80, FogEnd = 600, FogColor = rgb(150, 145, 170) },
			atmosphere = { Density = 0.42, Offset = 0.1, Color = rgb(160, 155, 180), Decay = rgb(120, 110, 150), Glare = 0.2, Haze = 2.6 },
			sky = { StarCount = 0, SunAngularSize = 22, MoonAngularSize = 11 },
			bloom = { Intensity = 0.9, Size = 24, Threshold = 0.92 },
			colorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.05, TintColor = rgb(235, 235, 255) },
			sunRays = { Intensity = 0.05, Spread = 0.6 },
			pieces = { "puddles", "rainbow" },
			ambient = { { kind = "dragonfly", count = 3 } },
			weather = { { kind = "rain", rate = 40 } },
			hazards = { "sprinklerJet", "acorn" },
		},
		{
			id = "harvest", from = 20, fade = 2, name = "Harvest Gold", emoji = "🍂",
			lighting = { ClockTime = 16.8, Brightness = 2.8, ExposureCompensation = 0.25,
				Ambient = rgb(140, 120, 100), OutdoorAmbient = rgb(190, 160, 120),
				FogStart = 150, FogEnd = 1000, FogColor = rgb(250, 215, 160) },
			atmosphere = { Density = 0.3, Offset = 0.12, Color = rgb(250, 215, 165), Decay = rgb(220, 150, 90), Glare = 0.9, Haze = 1.4 },
			sky = { StarCount = 0, SunAngularSize = 24, MoonAngularSize = 11 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.1, Saturation = 0.22, TintColor = rgb(255, 235, 205) },
			sunRays = { Intensity = 0.25, Spread = 0.7 },
			pieces = { "pumpkins", "hayBales" },
			ambient = { { kind = "robin", count = 3 } },
			weather = { { kind = "leaves", rate = 10 } },
			hazards = { "apple", "molehill" },
		},
		{
			id = "moon", from = 30, fade = 3, name = "HARVEST MOON", emoji = "🌕", celebrate = true,
			lighting = { ClockTime = 21.5, Brightness = 1.4, ExposureCompensation = 0.45,
				Ambient = rgb(95, 90, 120), OutdoorAmbient = rgb(120, 115, 160),
				FogStart = 150, FogEnd = 1100, FogColor = rgb(60, 55, 95) },
			atmosphere = { Density = 0.22, Offset = 0.05, Color = rgb(90, 85, 130), Decay = rgb(220, 150, 90), Glare = 0.6, Haze = 1.0 },
			sky = { StarCount = 2500, SunAngularSize = 12, MoonAngularSize = 30 },
			bloom = { Intensity = 1.5, Size = 38, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.15, TintColor = rgb(255, 230, 200) },
			sunRays = { Intensity = 0.05, Spread = 0.4 },
			pieces = { "lanterns", "moon" },
			ambient = { { kind = "firefly", count = 6 }, { kind = "owl", count = 1 } },
			weather = { { kind = "fireflies", rate = 8 } },
			hazards = { "apple", "pinecone" },
		},
		{
			id = "frost", from = 31, fade = 1, name = "First Frost", emoji = "❄️",
			lighting = { ClockTime = 8, Brightness = 2.4, ExposureCompensation = 0.2,
				Ambient = rgb(120, 130, 150), OutdoorAmbient = rgb(160, 180, 210),
				FogStart = 120, FogEnd = 800, FogColor = rgb(215, 230, 245) },
			atmosphere = { Density = 0.36, Offset = 0.2, Color = rgb(220, 232, 248), Decay = rgb(150, 175, 210), Glare = 0.3, Haze = 2.0 },
			sky = { StarCount = 0, SunAngularSize = 20, MoonAngularSize = 11 },
			bloom = { Intensity = 1.1, Size = 26, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.08, Saturation = -0.05, TintColor = rgb(235, 245, 255) },
			sunRays = { Intensity = 0.14, Spread = 0.8 },
			pieces = { "frostHedge", "birdbath" },
			ambient = { { kind = "robin", count = 2 } },
			weather = { { kind = "frost", rate = 6 } },
			hazards = { "icicle", "molehill" },
		},
		{
			id = "snowfall", from = 35, fade = 1, name = "Snowfall", emoji = "🌨️",
			lighting = { ClockTime = 17.5, Brightness = 1.8, ExposureCompensation = 0.2,
				Ambient = rgb(115, 115, 140), OutdoorAmbient = rgb(150, 150, 185),
				FogStart = 90, FogEnd = 650, FogColor = rgb(190, 190, 215) },
			atmosphere = { Density = 0.45, Offset = 0.1, Color = rgb(200, 200, 225), Decay = rgb(210, 150, 140), Glare = 0.5, Haze = 2.4 },
			sky = { StarCount = 0, SunAngularSize = 24, MoonAngularSize = 11 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.86 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.08, TintColor = rgb(240, 240, 255) },
			sunRays = { Intensity = 0.1, Spread = 0.6 },
			pieces = { "snowHedge", "sledge" },
			ambient = { { kind = "crow", count = 3 } },
			weather = { { kind = "snow", rate = 30 } },
			hazards = { "icicle", "snowClump" },
		},
		{
			id = "moonlit", from = 40, fade = 2, name = "Moonlit Snow", emoji = "🌙",
			lighting = { ClockTime = 0.5, Brightness = 1.2, ExposureCompensation = 0.5,
				Ambient = rgb(100, 110, 140), OutdoorAmbient = rgb(120, 135, 175),
				FogStart = 150, FogEnd = 1000, FogColor = rgb(40, 50, 85) },
			atmosphere = { Density = 0.25, Offset = 0.05, Color = rgb(70, 85, 130), Decay = rgb(100, 120, 170), Glare = 0.2, Haze = 1.0 },
			sky = { StarCount = 3000, SunAngularSize = 10, MoonAngularSize = 16 },
			bloom = { Intensity = 1.4, Size = 36, Threshold = 0.78 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = -0.05, TintColor = rgb(225, 235, 255) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "snowdrifts", "snowman" },
			ambient = { { kind = "owl", count = 1 } },
			-- the snow has stopped: frost glitters in the moonlight (Snowfall, the band before, is the snow)
			weather = { { kind = "frost", rate = 8 } },
			hazards = { "snowClump", "icicle" },
		},
		{
			id = "starfall", from = 45, fade = 2, name = "Starfall", emoji = "🌠",
			lighting = { ClockTime = 23, Brightness = 1.1, ExposureCompensation = 0.55,
				Ambient = rgb(100, 105, 140), OutdoorAmbient = rgb(115, 125, 170),
				FogStart = 200, FogEnd = 1400, FogColor = rgb(30, 35, 70) },
			atmosphere = { Density = 0.18, Offset = 0, Color = rgb(60, 70, 120), Decay = rgb(120, 100, 170), Glare = 0.2, Haze = 0.8 },
			sky = { StarCount = 4000, SunAngularSize = 10, MoonAngularSize = 14 },
			bloom = { Intensity = 1.5, Size = 40, Threshold = 0.72 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.05, TintColor = rgb(230, 230, 255) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "lampPosts", "snowdrifts" },
			ambient = { { kind = "shootingStar", count = 2 } },
			weather = { { kind = "stardust", rate = 10 } },
			hazards = { "starShard", "snowClump" },
		},
		{
			id = "aurora", from = 50, fade = 3, name = "AURORA", emoji = "🌌", celebrate = true,
			lighting = { ClockTime = 1.5, Brightness = 1.1, ExposureCompensation = 0.6,
				Ambient = rgb(95, 120, 130), OutdoorAmbient = rgb(110, 145, 160),
				FogStart = 200, FogEnd = 1500, FogColor = rgb(25, 45, 60) },
			atmosphere = { Density = 0.16, Offset = 0, Color = rgb(50, 90, 110), Decay = rgb(80, 200, 170), Glare = 0.3, Haze = 0.8 },
			sky = { StarCount = 5000, SunAngularSize = 10, MoonAngularSize = 14 },
			bloom = { Intensity = 1.7, Size = 44, Threshold = 0.68 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.16, Saturation = 0.2, TintColor = rgb(220, 255, 240) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "aurora", "snowdrifts" },
			ambient = { { kind = "hare", count = 3 } },
			weather = { { kind = "snow", rate = 10 }, { kind = "stardust", rate = 8 } },
			hazards = { "starShard", "snowClump" },
		},
	},
	-- Ambient life around the garden (never collidable, never in the way). Distances from the bed's centre.
	Critters = {
		butterfly = { rMin = 20, rMax = 60, yMin = 3, yMax = 10, speedMin = 3, speedMax = 6 },
		bee = { rMin = 15, rMax = 55, yMin = 2, yMax = 8, speedMin = 5, speedMax = 9 },
		dragonfly = { rMin = 20, rMax = 60, yMin = 3, yMax = 9, speedMin = 8, speedMax = 14 },
		robin = { rMin = 40, rMax = 80, yMin = 8, yMax = 20, speedMin = 10, speedMax = 16 },
		firefly = { rMin = 10, rMax = 55, yMin = 1, yMax = 6, speedMin = 1, speedMax = 3 },
		owl = { rMin = 60, rMax = 90, yMin = 20, yMax = 30, speedMin = 8, speedMax = 12 },
		crow = { rMin = 50, rMax = 90, yMin = 15, yMax = 30, speedMin = 12, speedMax = 18 },
		shootingStar = { rMin = 120, rMax = 220, yMin = 80, yMax = 140, speedMin = 90, speedMax = 140 },
		hare = { rMin = 60, rMax = 85, yMin = 0, yMax = 0, speedMin = 6, speedMax = 10 },
	},
}

-- Mobile budget for what the CLIENT builds (robloxemu/check_gnomegardendefense_env.luau measures it at every
-- band and seam). Emitter, weather, light, beam and hazard caps are +1 Jump's; 200 local parts (+1 Jump: 220)
-- because the bugs, drawn here too, take up to MaxBugParts.
Config.Budget = {
	MaxLocalParts = 200,      -- scenery + critters + hazard (the bugs are counted separately)
	MaxRenderedBugs = 40,     -- the measured peak is 35 (strong profile, endless)
	MaxBugParts = 120,        -- at most 3 Parts per bug
	MaxEmitters = 4,
	MaxWeatherEmitters = 2,
	MaxEmitterRate = 60,
	MaxBeams = 8,
	MaxLights = 3,
	MaxHazards = 1,
}

return Config
