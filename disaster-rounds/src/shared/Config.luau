--!strict
-- DISASTER ROUNDS - every tunable in one place (docs/new-game-checklist.md §1).
--
-- The pure modules (MapGen, Round, Zones, Strikes, Flood, Tornado, Quake, Guard, Progress) never read this file
-- as a global: the server, the clients and the specs pass it in, so every rule runs in the luau CLI. Each number
-- carries its reason, or the DESIGN.md section that gives it. Colours are { r, g, b } (0-255), never Color3, so the
-- specs can read them. RED IS RESERVED FOR DANGER: no band, overlay or island palette is red (tests/EnvConfig.spec).

local Config = {}

Config.Version = 1 -- the profile format this code writes (Progress.normalise refuses to write a newer one)
Config.WalkSpeed = 16
Config.MaxPlayers = 8 -- set at publish (DESIGN.md §2.2); the part budget and the crowded-plateau proof are sized for 8

--================================================================== the round cycle (DESIGN.md §2.1)
Config.Round = {
	IntermissionSeconds = 20, -- on the Lookout: read the card, look at the board, decide to take a break
	DropSeconds = 4, -- on the island before the disaster is named
	DisasterSeconds = 60,
	OutroSeconds = 4, -- the SURVIVED card where it happened
	-- practice drop-in: from the start of the drop until this many seconds into the disaster (10 s before it ends)
	PracticeUntilSeconds = 50,
	TickSeconds = 0.1, -- the server's sample rate (10 Hz): hit tests, the guard, the disaster clocks
	ServerNowHz = 1, -- workspace attribute ServerNow, so clients can extrapolate the server clock
}

--================================================================== the island (DESIGN.md §2.2)
Config.Island = {
	Grid = 13, -- 13 x 13 cells
	CellStuds = 8,
	LevelStuds = 4, -- cell top at y = 4 * level; a 4-stud step is a jump
	MaxLevel = 4,
	ColumnBottomY = -10, -- every cell column reaches down to here (under the sea surface)
	SeaY = -2, -- the sea surface; the flood's first rise starts here
	FallOutY = -6, -- a root below this has fallen into the sea
	HighLevel = 3, -- levels 3-4 stay dry after the last flood rise
	MinHighCells = 18, -- ... and there are always at least this many of them (8 players fit)
	MaxEscapeStuds = 80, -- cell-centre path; 100 studs walked at the 1.25 path factor
	PathFactor = 1.25,
	Peaks = { 1, 2, 2, 3 }, -- how many cones, picked uniformly from this list
	PeakHeights = { 4, 5, 5, 6 },
	SlopeMin = 0.55,
	SlopeMax = 0.95,
	CoreMin = 5, -- peaks sit in the inner 5 x 5 (cells 5..9)
	CoreMax = 9,
	MaxTries = 50, -- re-rolls before MapGen gives up (measured: never more than 2)
	WallHalf = 53, -- invisible walls at |x|, |z| = 53
	WallHeight = 40, -- a jump from level 4 reaches about y = 23
	DropSpacingCells = 2, -- each roster player lands at least 2 cells (Chebyshev) from every other
	MaxProps = 80,
	-- three styles, one per round; a palette per level 0..4 and two prop kinds. No saturated red anywhere.
	Styles = {
		{
			id = "palm", name = "Palm Atoll",
			levels = { { 238, 214, 160 }, { 222, 200, 140 }, { 104, 170, 84 }, { 86, 150, 72 }, { 70, 128, 66 } },
			materials = { "Sand", "Sand", "Grass", "Grass", "Grass" },
			props = { "palm", "beachRock" },
		},
		{
			id = "pine", name = "Pine Isle",
			levels = { { 150, 146, 140 }, { 120, 132, 96 }, { 88, 120, 76 }, { 74, 104, 70 }, { 236, 240, 246 } },
			materials = { "Pebble", "Grass", "Grass", "Grass", "Snow" },
			props = { "pine", "log" },
		},
		{
			id = "mesa", name = "Ochre Mesa",
			levels = { { 226, 204, 158 }, { 214, 178, 120 }, { 200, 160, 104 }, { 186, 146, 96 }, { 170, 134, 92 } },
			materials = { "Sand", "Sandstone", "Sandstone", "Sandstone", "Sandstone" },
			props = { "cactus", "bleachedRock" },
		},
	},
}

--================================================================== the red rule and the hit test (DESIGN.md §2.3)
Config.Hits = {
	PlayerRadius = 1.5, -- the template's value (plus1-jump Config.Hazards)
	LagGrace = 0.2, -- a hit needs the root inside at EVERY server sample in [T, T + 0.2]: ties go to the dodger
	GroundGrace = 0.6, -- flood and holes: the cell under you must stay deadly this long in a row
}

--================================================================== aimed rings and Heat (DESIGN.md §2.4)
Config.Strikes = {
	HitRadius = 3.0, -- + PlayerRadius = a 4.5-stud ring, 9 across
	TelegraphSeconds = 3.0, -- the template's MinTelegraphSeconds
	PassSeconds = 0.6, -- the ring is gone 0.6 s after impact
	FirstAfterSeconds = 5, -- first ring at a player >= 5 s after the name (or a practice landing)
	Jitter = 0.2, -- +-20 % on every interval
	-- seconds between rings at one player, by Heat 0..5
	Intervals = {
		meteor = { 6.0, 5.0, 4.2, 3.5, 3.0, 2.5 },
		other = { 15, 12, 9.5, 7.5, 6.0, 5.0 },
	},
	ExitStuds = 7, -- a ring is placed only if everyone it covers can stand outside all red within 7 studs
	RetrySeconds = 0.25, -- ... otherwise it waits this long and tries again
	MaxCoverage = 0.25, -- live rings never cover more than a quarter of the walkable area
	ExitSearchStep = 0.5, -- studs between the circles the exit search tries
	ExitSearchDirections = 32,
}

Config.Heat = {
	StreakPerHeat = 2, -- heat = min(5, floor(streak / 2))
	Max = 5,
}

--================================================================== the four disasters (DESIGN.md §2.5)
Config.Disasters = {
	Kinds = { "meteor", "flood", "tornado", "quake" },
	LeadSeconds = 3, -- no threat starts earlier than 3 s after the name
	Info = {
		meteor = { name = "METEOR SHOWER", icon = "☄️", rule = "Step out of the red rings.", hit = "Hit by a meteor" },
		flood = { name = "FLOOD", icon = "🌊", rule = "Get above the red line.", hit = "Swept away by the flood" },
		tornado = { name = "TORNADO", icon = "🌪️", rule = "Stay off the red path.", hit = "Caught by the tornado" },
		quake = { name = "EARTHQUAKE", icon = "🏚️", rule = "Get off the red ground.", hit = "The ground gave way" },
	},
	-- what each disaster's aimed ring is, for the swept-out card
	RingHit = { meteor = "Hit by a meteor", flood = "Struck by lightning", tornado = "Hit by flying debris", quake = "Hit by a boulder" },
}

Config.Flood = {
	-- the water rises to each of these heights in turn: 2, 6 and 10 cover levels 0, 1 and 2 by 2 studs
	Levels = { 0, 1, 2 },
	OverTop = 2, -- the water ends 2 studs over the flooding level's top
	StartUnder = 2, -- ... and starts 2 studs under it
	WarnAt = { 3, 16, 29 }, -- seconds after the name the red line appears
	WarnSeconds = 9, -- warning before the rise begins
	RiseSeconds = 4, -- linear rise
}

Config.Tornado = {
	HitRadius = 5.0, -- + PlayerRadius = 6.5 studs: a 13-stud path
	Speed = 9, -- walk speed is 16
	HorizonSeconds = 4.0, -- the red path shows the next 4 s and nothing further
	StepSeconds = 0.25, -- the path is decided 0.25 s at a time at the horizon
	TurnDegPerSecond = 30,
	ChaseChance = 0.5, -- target: a random player on the island, or a random point
	RetargetSeconds = 5,
	ReachedStuds = 8, -- a target this close counts as reached
	TouchdownAt = 3, -- seconds after the name
	MinStartStuds = 20, -- touchdown at an edge point at least this far from every player on the island
	EdgeInset = 3, -- the funnel stays this far inside the island's outer cells (reflects off the edge)
}

Config.Quake = {
	FirstAt = 3,
	EverySeconds = 6, -- 9 batches, the last drop at 54 s
	CrackSeconds = 3.0,
	BatchMax = 10,
	OwnCellChance = 0.6, -- per player on the island: crack their own cell plus one neighbour
	CapShare = 0.45, -- never more than 45 % of the island (76 of 169 cells)
}

--================================================================== the movement guard (DESIGN.md §2.7)
Config.Guard = {
	WindowSeconds = 1.0,
	MaxStuds = 28, -- 16 x 1.5 + 4: walking is 16 studs/s, the margin absorbs network bunching
	BoxMargin = 4, -- outside the island box by more than this = swept out
	ResetSeconds = 1.0, -- the guard is quiet for this long after every server teleport
}

--================================================================== rate limits
Config.Rates = {
	JumpInSeconds = 1.0, -- one Jump-in request a second
	JumpInToastSeconds = 2, -- ... and at most one "One tap is enough." every 2 s (REVIEW-1 F6)
	SetRestPerSecond = 2,
	BoardSwitchSeconds = 1.0,
}

--================================================================== the Lookout (DESIGN.md §9)
Config.Lookout = {
	MinX = -82, MaxX = -62, MinZ = -18, MaxZ = 18, -- the deck, 20 x 36 studs
	FloorY = 28, -- top of the deck, 12 studs above the island's highest top
	SpawnPos = { -74, 28.5, 0 }, -- LookoutSpawn's centre (6 x 1 x 6); it faces +X, toward the island
	RailHeight = 4,
	WallHeight = 20, -- invisible: a default jump clears the rail
	ReturnSpots = 8, -- swept-out and outro returns land on one of these spots on the deck
}

--================================================================== persistence (DESIGN.md §8)
Config.Save = {
	Enabled = true,
	Store = "DisasterRounds_v1",
	Leaderboard = "DisasterRounds_Streak_v1",
	LockSeconds = 300, -- the session lock's TTL, renewed by every write
	RenewSeconds = 120, -- a lock-renewal write for players with no round result
	LoadAttempts = 3,
	LoadBackoff = { 1, 2, 4 },
	LoadRetrySeconds = 10, -- after a failed load: a fresh unsaved profile, and another try every 10 s
	LockWaitSeconds = 30, -- a lock held by another session: re-read every 5 s for 30 s ...
	LockPollSeconds = 5,
	ReadOnlyRecheckSeconds = 10, -- ... then read-only, re-checked every 10 s (an expired lock is taken over)
}

--================================================================== the board (docs/complete-game-standard.md §3)
-- Metric: best streak. OrderedDataStore Config.Save.Leaderboard, key u_<userId>, value best * 2e9 + (2e9 - reachedAt).
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
	MaxMetric = 4000000,
	-- REVIEW-1 F5: the board counts a best streak up to this. A script reading the replicated red never misses and the
	-- round clock alone does not bound it (40.9 an hour, for as long as it runs); 25 in a row is a run a fast human
	-- makes in 43 % of one-hour sittings and 82 % of two-hour ones (tests/RoundModel.luau, REVIEW-1.md F5), so a
	-- script reaches what a person can and no more.
	StreakCap = 25,
	PromptDistance = 10,
	Size = { 12, 8, 0.4 }, -- studs; the SurfaceGui draws at 40 px per stud
	Text = {
		Title = "LONGEST STREAKS",
		EmptyPublic = "No streaks on the board yet. Survive a round and be the first!",
		FriendsFailed = "Couldn't load your Roblox friends right now. Try again in a minute.",
		NoFriends = "No Roblox friends yet. Friends you add show up here, ranked against you.",
		FriendsNoScores = "None of your %d friends has survived a round yet. Invite one and see who lasts longer!",
		FriendsChecking = "Checking your friends: %d of %d so far...",
		Loading = "Loading...",
		Prompt = "Public / Friends",
	},
}

--================================================================== Heat glow and the brag (DESIGN.md §3.4, §6)
Config.Brag = {
	BandId = "fallingsky", -- crossing into this band during play is the brag
	MaxHeatStreak = 10, -- the skill brag: the first time a streak reaches 10
	DodgedPopups = 3, -- "Dodged!" pops for the first 3 dodges only
}

--================================================================== environment bands (DESIGN.md §3)
-- Progress = lifetime counted survivals (the server-written `Survived` attribute). It only goes up.
local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

Config.Env = {
	HalfLife = 0.6,
	LightingHz = 10,
	OverlayFadeSeconds = 3, -- the disaster overlay weighs in over 3 s at the name and out over 3 s after the end
	Bands = {
		{
			id = "calm", from = 0, fade = 0, name = "Calm Cove", emoji = "🏝️",
			-- = Fx.Presets.Coast, so the client takes over from the server's first frame without a jump
			lighting = { ClockTime = 9.5, Brightness = 2.8, ExposureCompensation = 0.1,
				Ambient = rgb(120, 130, 140), OutdoorAmbient = rgb(150, 165, 180),
				FogStart = 250, FogEnd = 1400, FogColor = rgb(196, 226, 236) },
			atmosphere = { Density = 0.26, Offset = 0.2, Color = rgb(198, 228, 238), Decay = rgb(120, 170, 190), Glare = 0.3, Haze = 1.4 },
			bloom = { Intensity = 0.9, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.06, Saturation = 0.14, TintColor = rgb(250, 252, 255) },
			sunRays = { Intensity = 0.12, Spread = 0.8 },
			sky = { StarCount = 0 },
			sea = rgb(64, 190, 200),
			pieces = { "palmIslets", "sailboat" },
			critters = { { kind = "gull", count = 4 } },
			weather = { kind = "spray", rate = 4 },
		},
		{
			id = "windy", from = 2, fade = 1, name = "Windy Point", emoji = "🌬️",
			lighting = { ClockTime = 13.5, Brightness = 3.1, ExposureCompensation = 0.15,
				Ambient = rgb(126, 136, 150), OutdoorAmbient = rgb(156, 170, 190),
				FogStart = 300, FogEnd = 1600, FogColor = rgb(200, 222, 240) },
			atmosphere = { Density = 0.24, Offset = 0.15, Color = rgb(204, 224, 242), Decay = rgb(130, 160, 196), Glare = 0.4, Haze = 1.2 },
			bloom = { Intensity = 0.9, Size = 24, Threshold = 0.92 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.1, TintColor = rgb(240, 248, 255) },
			sunRays = { Intensity = 0.1, Spread = 0.7 },
			sky = { StarCount = 0 },
			sea = rgb(56, 160, 190),
			pieces = { "lighthouse", "bentTrees" },
			critters = { { kind = "albatross", count = 4 } },
			weather = { kind = "wind", rate = 8 },
		},
		{
			id = "storm", from = 6, fade = 2, name = "Storm Coast", emoji = "⛈️",
			lighting = { ClockTime = 16.5, Brightness = 1.9, ExposureCompensation = 0.05,
				Ambient = rgb(110, 108, 128), OutdoorAmbient = rgb(128, 124, 146),
				FogStart = 120, FogEnd = 900, FogColor = rgb(132, 128, 150) },
			atmosphere = { Density = 0.4, Offset = 0.05, Color = rgb(146, 140, 166), Decay = rgb(96, 100, 130), Glare = 0.2, Haze = 2.4 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.0, Contrast = 0.16, Saturation = -0.08, TintColor = rgb(228, 228, 250) },
			sunRays = { Intensity = 0.05, Spread = 0.5 },
			sky = { StarCount = 0 },
			sea = rgb(60, 96, 120),
			pieces = { "stormBank", "shipwreck" },
			critters = { { kind = "petrel", count = 5 } },
			weather = { kind = "drizzle", rate = 30 },
			lightning = { everyMin = 7, everyMax = 15 },
		},
		{
			id = "ember", from = 12, fade = 3, name = "Ember Isles", emoji = "🌋",
			lighting = { ClockTime = 18.0, Brightness = 2.0, ExposureCompensation = 0.15,
				Ambient = rgb(140, 120, 104), OutdoorAmbient = rgb(170, 140, 116),
				FogStart = 160, FogEnd = 1100, FogColor = rgb(214, 170, 130) },
			atmosphere = { Density = 0.34, Offset = 0.1, Color = rgb(226, 182, 140), Decay = rgb(150, 110, 90), Glare = 0.8, Haze = 1.8 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.18, TintColor = rgb(255, 232, 205) },
			sunRays = { Intensity = 0.2, Spread = 0.6 },
			sky = { StarCount = 200 },
			sea = rgb(70, 92, 110),
			pieces = { "volcano" },
			critters = { { kind = "bat", count = 6 } },
			weather = { kind = "ash", rate = 14 },
		},
		{
			id = "fallingsky", from = 21, fade = 4, name = "Falling Sky", emoji = "☄️", celebrate = true,
			-- deep violet night, kept bright enough to read the rings (EYECANDY.md needs-Studio #2)
			lighting = { ClockTime = 20.0, Brightness = 1.6, ExposureCompensation = 0.45,
				Ambient = rgb(130, 120, 160), OutdoorAmbient = rgb(140, 128, 176),
				FogStart = 200, FogEnd = 1500, FogColor = rgb(64, 52, 104) },
			atmosphere = { Density = 0.22, Offset = 0.05, Color = rgb(96, 80, 150), Decay = rgb(150, 110, 180), Glare = 0.5, Haze = 1.2 },
			bloom = { Intensity = 1.6, Size = 36, Threshold = 0.72 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.16, Saturation = 0.2, TintColor = rgb(232, 226, 255) },
			sunRays = { Intensity = 0.05, Spread = 0.3 },
			sky = { StarCount = 2500 },
			sea = rgb(40, 40, 90),
			pieces = { "comet", "farMeteors" },
			critters = { { kind = "firebird", count = 5 } },
			weather = { kind = "sparks", rate = 10 },
		},
		{
			id = "dawn", from = 100, fade = 20, name = "New Dawn", emoji = "🌅",
			lighting = { ClockTime = 6.4, Brightness = 2.6, ExposureCompensation = 0.25,
				Ambient = rgb(150, 136, 140), OutdoorAmbient = rgb(186, 166, 160),
				FogStart = 260, FogEnd = 1500, FogColor = rgb(250, 214, 184) },
			atmosphere = { Density = 0.28, Offset = 0.15, Color = rgb(255, 222, 190), Decay = rgb(220, 170, 150), Glare = 1.0, Haze = 1.4 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.84 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.1, Saturation = 0.3, TintColor = rgb(255, 240, 225) },
			sunRays = { Intensity = 0.25, Spread = 0.8 },
			sky = { StarCount = 0 },
			sea = rgb(70, 170, 200),
			pieces = { "rainbow", "flowerIslets" },
			critters = { { kind = "butterfly", count = 6 }, { kind = "dolphin", count = 3 } },
			weather = { kind = "pollen", rate = 6 },
		},
	},
	-- the running disaster, on top of every player's band (EnvBands.overlay): amber, blue-grey, green-grey, brown
	Overlays = {
		meteor = { colorCorrection = { Saturation = 0.3, TintColor = rgb(255, 230, 200) },
			atmosphere = { Color = rgb(236, 190, 140), Haze = 2.2 } },
		flood = { lighting = { Brightness = 1.4 }, colorCorrection = { Saturation = -0.1, TintColor = rgb(214, 228, 246) },
			atmosphere = { Color = rgb(150, 164, 180), Density = 0.42, Haze = 2.6 } },
		tornado = { colorCorrection = { Saturation = -0.15, TintColor = rgb(222, 236, 214) },
			atmosphere = { Color = rgb(150, 164, 136), Density = 0.4, Haze = 2.8 } },
		quake = { colorCorrection = { Saturation = -0.05, TintColor = rgb(240, 228, 208) },
			atmosphere = { Color = rgb(176, 150, 118), Density = 0.38, Haze = 2.6 } },
	},
	-- ambient life, never dangerous, never collidable; studs from the Lookout centre
	Critters = {
		gull = { rMin = 60, rMax = 220, yMin = 10, yMax = 50, speedMin = 10, speedMax = 16 },
		albatross = { rMin = 80, rMax = 260, yMin = 20, yMax = 70, speedMin = 14, speedMax = 20 },
		petrel = { rMin = 60, rMax = 200, yMin = 4, yMax = 40, speedMin = 16, speedMax = 24 },
		bat = { rMin = 50, rMax = 180, yMin = 10, yMax = 50, speedMin = 12, speedMax = 20 },
		firebird = { rMin = 70, rMax = 240, yMin = 20, yMax = 90, speedMin = 14, speedMax = 22 },
		butterfly = { rMin = 8, rMax = 30, yMin = 0, yMax = 8, speedMin = 2, speedMax = 4 },
		dolphin = { rMin = 120, rMax = 300, yMin = -30, yMax = -20, speedMin = 10, speedMax = 16 },
	},
	SceneryMinStuds = 250, -- far scenery sits in a ring 250-450 studs out, always beyond the island
	SceneryMaxStuds = 450,
}

--================================================================== Lookout strays (DESIGN.md §4.2): plus1-jump's Hazards.luau
-- Client only, on the Lookout only, while not resting. Themed by the current (or last) disaster.
Config.Hazards = {
	IntervalMin = 60, -- seconds of Lookout time between strays
	IntervalMax = 90,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	AimJitter = 1.2,
	SpreadDegrees = 35,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	KnockLift = 8, -- lifts 0.16 studs: never over the 4-stud rail
	KnockSeconds = 0.9,
	Kinds = {
		ember = { speed = 30, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 1.8, visualRadius = 2.2, knock = 32, pitch = 14, pitchSpread = 6 },
		spray = { speed = 22, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 2.2, visualRadius = 2.6, knock = 28, pitch = 6, pitchSpread = 4 },
		plank = { speed = 34, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 2.0, visualRadius = 2.4, knock = 34, pitch = 8, pitchSpread = 6 },
		pebble = { speed = 26, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, visualRadius = 2.0, knock = 30, pitch = 18, pitchSpread = 6 },
	},
	-- which stray each disaster throws at the deck
	ByDisaster = { meteor = "ember", flood = "spray", tornado = "plank", quake = "pebble" },
}

--================================================================== rest (DESIGN.md §5): plus1-jump's Rest.luau
Config.Rest = {
	IdleSeconds = 150, -- > the 112 s longest still stretch of an engaged player
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 8, -- the longest stray flight (5.7 s) + 2, rounded up
	ServerMoveQuietSeconds = 1.0, -- after a server move (MoveSeq bump) the glue reports "not moving"
	MoveSpeed = 1, -- studs/s of the root's own horizontal speed that count as moving
}

--================================================================== budgets (DESIGN.md §3.5): every one capped in code (REVIEW-1 F11)
Config.Budget = {
	ServerParts = 400,
	SceneryParts = 500, -- client, two bands cross-faded at a seam
	SceneryPartsPerBand = 250,
	SceneryPartsPerPiece = 125, -- SkyArt trims a far piece to this; a band has at most 2 pieces (tests/EnvConfig.spec)
	Critters = 10,
	WeatherEmitters = 2,
	MaxEmitterRate = 60,
	DisasterEmitters = 6,
	Chunks = 60,
	ChunksPerCell = 6,
	ChunkSeconds = 3,
	Debris = 12,
	Projectiles = 16,
	Rings = 16, -- live ring Parts on the server at once (Strikes.maxLive); one projectile each on the client
	PathRibbon = 40, -- the tornado's red: one piece per path segment and one disc per path point (18 + 19) + the funnel's own disc
	Auras = 8,
	Billboards = 8,
	Lights = 6,
	Strays = 1,
	Confetti = 1,
}

--================================================================== shots (EYECANDY.md): nil in src/, set only in a shots place
Config.Shots = {
	ForceKind = nil :: string?,
	ForceHeat = nil :: number?,
	IslandSeed = nil :: number?,
}

--================================================================== the pacing model's player profiles (tests/RoundModel.luau)
-- Not used by the game: these are the assumptions behind the band thresholds, written down instead of hidden.
Config.Pacing = {
	BragMinutes = { 30, 45 }, -- the owner's target for a normal player
	LatencySeconds = 0.10,
	Profiles = {
		fast = { react = 0.55, lapseRing = 0.008, lapseBig = 0.005 },
		normal = { react = 0.80, lapseRing = 0.020, lapseBig = 0.010 },
		slow = { react = 1.20, lapseRing = 0.035, lapseBig = 0.020 },
		bot = { react = 0.60, lapseRing = 0, lapseBig = 0, fixed = true },
	},
}

return Config
