--!strict
-- Meteor Drop Tycoon — EVERY tunable in one place. Read by the server, both client scripts, the pure
-- modules (passed in as `cfg`) and every spec. DESIGN.md gives the reason for each number; the tag after
-- a value says where it came from ([M n] design/model.luau part n, [T] a template game, [R] a rule or
-- worked arithmetic, [A] an assumption). tests/Pacing.spec.luau re-measures the pacing FROM THIS FILE.
--
-- Colours are {r, g, b} (0-255), never Color3, so the pure modules and specs can read them in the luau CLI.
-- Nothing in here is secret: this module replicates, and nothing in the game is seeded from it.

local Config = {}

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

--============================================================================ the world
Config.World = {
	Plots = 8, -- one per player, Players.MaxPlayers = 8 (a Studio setting, EYECANDY needs-Studio)
	RingRadius = 110, -- plot centres on a ring around the origin, 45 degrees apart [R]
	PlotRadius = 36, -- a plot is a disc of 72 studs [R]
	BaseplateSize = 600, -- one continuous ground plate, top at y = 0: nothing can fall off anything [R]
	GroundY = 0,
	DiscTopY = 0.2, -- the plot disc sits 0.2 above the plate
	ObservatoryRadius = 16,
	KickMessage = "This server's 8 plots are taken. Rejoin to get a server with room.",
}

-- Plot-local positions: origin at the plot centre (the Smelter), -Z points at the observatory.
Config.Plot = {
	LandInner = 8, -- nothing lands on the Smelter (radius 6) or its 2-stud apron [R]
	LandOuter = 32, -- nothing lands within 4 studs of the rim [R]
	SmelterRadius = 6,
	Arrival = { x = 0, z = -30 }, -- the SpawnLocation, 6 x 1 x 6, top at y = 1
	ArrivalSize = 6,
	Showcase = { x = 0, z = -26 }, -- the Falling Star, 4 studs in front of the arrival, outside the biggest dish
	Board = { x = -14, z = -31 }, -- the Star Chart, r = 34.0, outside the landing ring
	Beacon = { x = 0, z = 33 }, -- outside the landing ring, behind the Smelter in every arrival view
	Sign = { x = 0, z = -36 }, -- the owner sign, above the rim
	FirstMeteor = { x = 0, z = -20 }, -- a session's first meteor lands 10 studs in front of the arrival [R]
	SpawnCorrectStuds = 8, -- CharacterAdded belt and braces: re-place a root further than this from the pad
	RootAbovePad = 3, -- vault-runners' root height over a pad top [T]
	SpawnWaitFrames = 300, -- the bounded wait for char.Parent (SPAWN-ORDER.md) [T]
	-- The low surfaces a player stands on, as Main.server.luau builds them (PlotGeom.floors; the hazard zone is
	-- drawn up to the highest one it overlaps, REVIEW-1). robloxemu/check_meteordroptycoon_hazards.luau measures
	-- them on the built parts, so a change to the build that forgets these fails there.
	ArrivalTopY = 1, -- the pad is 1 stud tall on the plate (world y 0..1)
	SmelterBaseHeight = 1, -- the Smelter's round base, radius SmelterRadius, on the disc
	BeaconBaseRadius = 2.5,
	BeaconBaseHeight = 2,
}

--============================================================================ meteors
Config.Meteors = {
	FallSeconds = 1.5, -- announce -> land; the landing glow shows this long [R]
	StarFallSeconds = 4, -- the Falling Star descends slowly so it can be watched and filmed [R]
	FirstMeteorAt = 0.5, -- after the character is placed [R]
	MaxLying = 20, -- a full plot burns new meteors up in the sky [M3]
	PickupRadius = 5, -- studs, horizontal, from the TRUSTED position [R]
	PollSeconds = 0.1, -- the server's pickup / landing / melt tick (10 Hz) [R]
	SpawnJitter = 0.25, -- each gap is SpawnInterval x U(0.75, 1.25) [R]
	StreakHeight = 180, -- the client's falling streak starts this high... [R]
	StreakTiltDegrees = 25, -- ...entering 25 degrees from vertical, so it crosses a third-person view [R]
	MaxStreakTrails = 2, -- trails only on the player's own plot, at most 2 at a time [R]
	FullToastSeconds = 5, -- "Hopper full" refusals toast at most this often
	VisitorToastSeconds = 15, -- "Only <name> can collect here" at most this often
	StateSeconds = 0.25, -- the owner's State payload is pushed at most 4 times a second (and on change)
	RateHalfLife = 20, -- the HUD's "+X/min" is a measured moving average of Stardust minted [R]
}

--============================================================================ the three machines
Config.Beacon = {
	SpawnInterval0 = 3.0, -- seconds between meteors at L0 [M1, M8]
	SpawnIntervalDecay = 0.97,
	SpawnIntervalMin = 1.2, -- reached at L31 [M2]
	OreGrowth = 1.14, -- ore per meteor = OreGrowth ^ L x rarity multiplier
	Price0 = 12, -- about 28 s of the starting inflow [M2, R]
	PriceGrowth = 1.26, -- tuned with the Smelter's growth: the Falling Star at ~36 min [M11]
	SegmentEvery = 5, -- the tower grows a segment every 5 levels...
	MaxSegments = 10, -- ...up to 10 (the part budget)
	SegmentHeight = 3,
}

Config.Collector = {
	Max = 8,
	Price0 = 60,
	PriceGrowth = 2.2,
	Radius1 = 10, -- the dish radius at level 1...
	RadiusStep = 2, -- ...+2 per level: 10..24, covering 3.7%..53.3% of landings [M1]
	IdleSeconds = 600, -- it sleeps 10 min after its owner's last HAND pickup [M6]
	HudHandRate = 0.4, -- meteors/s the HUD's star assumes an active player walks to [M1, R]
}

Config.Smelter = {
	Rate0 = 0.6, -- ore/s at s0 against an inflow of 0.43 [M2]
	RateGrowth = 1.28,
	HopperSeconds = 20, -- the hopper holds 20 s of melting; it accepts while below the cap [M7, R]
	Price0 = 20,
	PriceGrowth = 1.38, -- [M11]
	-- REVIEW-1: the HUD's star treats the Smelter as full at this share of its rated melt. Rares and epics
	-- arrive in bursts, so a Smelter that only matches the AVERAGE inflow is full a fifth of the time: with
	-- 1.0 the normal player's hopper was full 18.5% of the way to the star and the dish lost 16.8% of its
	-- catches; with 0.85 it is 6.3% and 3.8% (medians, 20 seeds), and the star still falls at 35.5 min.
	-- 0.80 put the star at 38.6 min; 0.65 past 45 [measured, tests/Pacing.spec.luau].
	StarHeadroom = 0.85,
	-- ...and it MEASURES the hopper: the steady rule assumes a pace (Collector.HudHandRate), and a player who
	-- collects faster still fills it. The server keeps a moving share of the time the hopper was full (half-life
	-- FullHalfLife s, reset when a Smelter level is bought); at StarFullShare or more the star is on the Smelter,
	-- from the first purchase on (before it, the first ★ is the Beacon).
	StarFullShare = 0.1,
	FullHalfLife = 30,
}

-- No meteor colour is reddish: red is the hazard ring's alone (EnvConfig.spec, isReddish).
Config.Rarities = {
	Order = { "common", "uncommon", "rare", "epic", "legendary" },
	Defs = {
		common = { name = "Pebble", mult = 1, color = rgb(200, 200, 210), size = 2.2 },
		uncommon = { name = "Iron", mult = 3, color = rgb(90, 220, 120), size = 2.6 },
		rare = { name = "Crystal", mult = 8, color = rgb(80, 160, 255), size = 3.0 },
		epic = { name = "Plasma", mult = 25, color = rgb(180, 100, 255), size = 3.4 },
		legendary = { name = "Star Core", mult = 100, color = rgb(255, 210, 60), size = 4.0 },
	},
	GlowSize = 4.5, -- the landing glow disc's diameter
	StarColor = rgb(255, 225, 120), -- the Falling Star
}

--============================================================================ trust, save, board, remotes
-- The trusted position (vault-runners' Trace): the server's own copy of the player, moving toward the
-- claimed root at no more than WalkSpeed x TrustedSpeedFactor, with a banked burst for replication jitter.
Config.Trace = {
	WalkSpeed = 16, -- Humanoid default; the server writes it
	TrustedSpeedFactor = 1.35, -- 21.6 studs/s [T: vault-runners]
	BurstSeconds = 3, -- [T: vault-runners]
}

Config.Save = {
	Store = "MeteorDropTycoon_v1",
	Version = 1,
	FlushTickSeconds = 7, -- coalesced writes, at most one per player per tick [T]
	AutosaveSeconds = 60, -- renews the lock [T]
	LockSeconds = 120, -- twice the autosave [T]
	-- REVIEW-1 (steal-a-cryptid's REVIEW-1 fix [T]): a load is tried LoadAttempts times, LoadRetrySeconds x
	-- attempt apart (1 s, 2 s), before the session plays unsaved; one transient failure used to be final.
	LoadAttempts = 3,
	LoadRetrySeconds = 1,
	-- a record another server still holds is re-read every LockRetrySeconds for up to LockWaitSeconds at the
	-- join (an old server's leave-write usually lands within seconds); a session that still starts read-only
	-- re-checks every LockRecheckSeconds and takes over once the lock is gone and the data is as it read it [T]
	LockWaitSeconds = 15,
	LockRetrySeconds = 5,
	LockRecheckSeconds = 15,
	-- writes are serialised per session; one that must follow the write in flight waits at most this long [T]
	WriteQueueSeconds = 60,
}

Config.Board = {
	Store = "MeteorDropTycoon_Board_v1",
	Scale = 2e9, -- value = beacon * Scale + (Scale - beaconAt) [T: complete-game-standard.md]
	PublicSize = 10,
	PublicCacheSeconds = 60,
	FriendsCap = 200,
	FriendReadsPerSecond = 1, -- per server
	BudgetReserve = 10, -- keep this much GetAsync budget for everything else
	FriendCacheSeconds = 300,
	WriteMinInterval = 60, -- at most one board write per player per minute, plus one on leaving
	PromptDistance = 10, -- the board is 14 studs from the arrival centre, a few steps reach it
}

Config.Remotes = {
	MaxPerSecond = 8, -- per remote per player [T: steal-a-cryptid]
	SlowToastSeconds = 5,
}

-- The first-minutes hints (the persisted `tutorial` step 0..3, so a rejoin resumes and never repeats).
Config.Tutorial = {
	Walk = "☄️ A meteor is coming: walk over it when it lands",
	Keep = "Meteors melt into Stardust. Keep collecting!",
	Buy = "Tap ⬆ Upgrades and buy the ★ upgrade",
	Collector = "The Collector catches meteors for you. It sleeps if you stop collecting.",
	NotSaving = "⚠️ Progress is not being saved this session",
	-- REVIEW-1: a read-only session now re-checks the lock and starts saving by itself (no "rejoin in 2 minutes")
	NotSavingLocked = "⚠️ Save open on another server: not saving until it lets go",
	LockWaiting = "⏳ Your save is open on another server. Waiting for it…",
	LockTaken = "✅ Your save is back: progress is being saved",
	LockChanged = "⚠️ Your save changed elsewhere: rejoin to load it (not saving)",
}

--============================================================================ the sky: environment bands
-- Everything under Config.Env is COSMETIC and client-side (src/client/Sky.client.luau), except each
-- band's `beam`, the colour of the owner's Beacon beam, which the server shows everyone. The trigger is
-- the owner's Beacon level (how far into space the plot listens), never time. The integer level names
-- the band; the same level drives the blend (each band fades in over `fade` levels before its `from`),
-- and every written value glides with HalfLife.
Config.Env = {
	HalfLife = 1.5, -- s: a purchase is a deliberate step the player should see happen [R]
	LightingHz = 10, -- Lighting is written at most 10x/s and only on change [T]
	BragBandId = "starfall", -- entering it grants the Falling Star (the brag moment)
	StarBeacon = 22, -- = the brag band's `from`; EnvConfig.spec asserts they agree

	Bands = {
		{
			id = "dusk", from = 0, fade = 0, name = "Dusk Meadow", emoji = "🌅",
			-- = Fx.Presets.Dusk, so the client takes over from the server's light with no jump
			lighting = { ClockTime = 17.8, Brightness = 2.4, ExposureCompensation = 0.1,
				Ambient = rgb(120, 100, 90), OutdoorAmbient = rgb(170, 140, 120),
				FogStart = 200, FogEnd = 1400, FogColor = rgb(255, 190, 150) },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(255, 190, 150), Decay = rgb(190, 110, 90), Glare = 0.6, Haze = 1.8 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.15, TintColor = rgb(255, 236, 220) },
			sunRays = { Intensity = 0.2, Spread = 0.8 },
			pieces = { "hills", "birches", "lowSun" },
			ambient = { { kind = "swallow", count = 5 }, { kind = "butterfly", count = 3 } },
			weather = { kind = "fluff", rate = 5 },
			hazards = {},
			beam = rgb(255, 170, 90),
			mix = { common = 880, uncommon = 110, rare = 10, epic = 0, legendary = 0 },
		},
		{
			id = "twilight", from = 5, fade = 2, name = "Twilight", emoji = "🌆",
			lighting = { ClockTime = 19.0, Brightness = 1.6, ExposureCompensation = 0.15,
				Ambient = rgb(90, 90, 120), OutdoorAmbient = rgb(110, 110, 160),
				FogStart = 300, FogEnd = 1800, FogColor = rgb(140, 130, 200) },
			atmosphere = { Density = 0.25, Offset = 0.15, Color = rgb(140, 130, 200), Decay = rgb(120, 90, 160), Glare = 0.4, Haze = 1.4 },
			sky = { StarCount = 800, SunAngularSize = 18, MoonAngularSize = 12 },
			bloom = { Intensity = 1.1, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.1, TintColor = rgb(225, 225, 255) },
			sunRays = { Intensity = 0.1, Spread = 0.6 },
			pieces = { "hills", "moon", "lighthouse" },
			ambient = { { kind = "bat", count = 4 }, { kind = "firefly", count = 8 } },
			weather = { kind = "mist", rate = 4 },
			hazards = { "satellite" },
			beam = rgb(150, 140, 255),
			mix = { common = 800, uncommon = 160, rare = 36, epic = 4, legendary = 0 },
		},
		{
			id = "aurora", from = 12, fade = 3, name = "Aurora", emoji = "🌌",
			lighting = { ClockTime = 22.0, Brightness = 1.2, ExposureCompensation = 0.2,
				Ambient = rgb(80, 100, 110), OutdoorAmbient = rgb(100, 130, 150),
				FogStart = 400, FogEnd = 2400, FogColor = rgb(90, 140, 170) },
			atmosphere = { Density = 0.15, Offset = 0.1, Color = rgb(90, 140, 170), Decay = rgb(60, 120, 140), Glare = 0.2, Haze = 1.0 },
			sky = { StarCount = 2500, SunAngularSize = 14, MoonAngularSize = 14 },
			bloom = { Intensity = 1.3, Size = 34, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.12, TintColor = rgb(215, 245, 240) },
			sunRays = { Intensity = 0, Spread = 0.4 },
			pieces = { "aurora", "peaks", "moon" },
			ambient = { { kind = "owl", count = 2 }, { kind = "wisp", count = 6 } },
			weather = { kind = "snow", rate = 20 },
			hazards = { "satellite", "ice" },
			beam = rgb(80, 255, 190),
			mix = { common = 720, uncommon = 200, rare = 65, epic = 14, legendary = 1 },
		},
		{
			id = "starfall", from = 22, fade = 4, name = "Starfall", emoji = "🌠", celebrate = true,
			lighting = { ClockTime = 23.0, Brightness = 1.1, ExposureCompensation = 0.25,
				Ambient = rgb(100, 90, 110), OutdoorAmbient = rgb(120, 110, 150),
				FogStart = 600, FogEnd = 4000, FogColor = rgb(70, 60, 110) },
			atmosphere = { Density = 0.1, Offset = 0.05, Color = rgb(70, 60, 110), Decay = rgb(120, 80, 140), Glare = 0.1, Haze = 0.6 },
			sky = { StarCount = 3500, SunAngularSize = 12, MoonAngularSize = 12 },
			bloom = { Intensity = 1.6, Size = 38, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.2, TintColor = rgb(255, 240, 215) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "comet", "peaks" },
			ambient = { { kind = "shootingStar", count = 3 } },
			weather = { kind = "embers", rate = 12 },
			hazards = { "bolide" },
			beam = rgb(255, 210, 90),
			mix = { common = 640, uncommon = 230, rare = 95, epic = 30, legendary = 5 },
		},
		{
			id = "nebula", from = 32, fade = 4, name = "Nebula", emoji = "🪐",
			lighting = { ClockTime = 23.5, Brightness = 1.0, ExposureCompensation = 0.3,
				Ambient = rgb(100, 85, 120), OutdoorAmbient = rgb(125, 105, 160),
				FogStart = 800, FogEnd = 6000, FogColor = rgb(80, 40, 110) },
			atmosphere = { Density = 0.05, Offset = 0, Color = rgb(80, 40, 110), Decay = rgb(140, 70, 160), Glare = 0, Haze = 0.3 },
			sky = { StarCount = 4500, SunAngularSize = 10, MoonAngularSize = 10 },
			bloom = { Intensity = 1.7, Size = 42, Threshold = 0.7 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.25, TintColor = rgb(240, 220, 255) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "nebula", "ringedPlanet" },
			ambient = { { kind = "starJelly", count = 3 } },
			weather = { kind = "stardust", rate = 6 },
			hazards = { "plasma", "bolide" },
			beam = rgb(200, 120, 255),
			mix = { common = 560, uncommon = 260, rare = 125, epic = 45, legendary = 10 },
		},
		{
			id = "core", from = 44, fade = 6, name = "Galactic Core", emoji = "✨",
			lighting = { ClockTime = 23.9, Brightness = 0.9, ExposureCompensation = 0.35,
				Ambient = rgb(110, 100, 120), OutdoorAmbient = rgb(135, 120, 165),
				FogStart = 1000, FogEnd = 8000, FogColor = rgb(30, 20, 40) },
			atmosphere = { Density = 0, Offset = 0, Color = rgb(30, 20, 40), Decay = rgb(90, 60, 110), Glare = 0, Haze = 0 },
			sky = { StarCount = 5000, SunAngularSize = 8, MoonAngularSize = 8 },
			bloom = { Intensity = 1.9, Size = 46, Threshold = 0.65 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.18, Saturation = 0.3, TintColor = rgb(255, 230, 245) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "galaxy", "nebula" },
			ambient = { { kind = "comet", count = 2 } },
			weather = { kind = "goldDust", rate = 8 },
			hazards = { "neutron", "bolide" },
			beam = rgb(255, 235, 180),
			mix = { common = 480, uncommon = 280, rare = 160, epic = 60, legendary = 20 },
		},
	},

	-- Weather, one emitter per kind, capped by EnvBands.capRates (Budget). Colours {r,g,b}; accel {x,y,z}.
	Weather = {
		fluff = { color = rgb(255, 250, 235), size = 0.35, lifetime = { 6, 9 }, speed = { 1, 2 }, lightEmission = 0.2, transparency = 0.15, accel = { 0.6, -0.3, 0.3 } },
		mist = { color = rgb(210, 205, 255), size = 18, lifetime = { 6, 9 }, speed = { 1, 2 }, lightEmission = 0.2, transparency = 0.88, accel = { 0, 0, 0 } },
		snow = { color = rgb(235, 250, 255), size = 0.25, lifetime = { 3, 5 }, speed = { 2, 4 }, lightEmission = 0.6, transparency = 0.1, accel = { 0.3, -3, 0 } },
		embers = { color = rgb(255, 200, 110), size = 0.3, lifetime = { 2, 4 }, speed = { 2, 5 }, lightEmission = 1, transparency = 0.1, accel = { 0, 2, 0 } },
		stardust = { color = rgb(200, 212, 255), size = 0.28, lifetime = { 5, 8 }, speed = { 0.2, 0.8 }, lightEmission = 1, transparency = 0.2, accel = { 0, 0, 0 } },
		goldDust = { color = rgb(255, 225, 140), size = 0.3, lifetime = { 5, 8 }, speed = { 0.3, 1 }, lightEmission = 1, transparency = 0.15, accel = { 0, 0, 0 } },
	},

	-- Ambient life: never dangerous, never collidable. Distances in studs from the camera (EnvBands.ambientSpawn).
	Critters = {
		swallow = { rMin = 60, rMax = 220, yMin = 20, yMax = 70, speedMin = 18, speedMax = 26, flock = 5 },
		butterfly = { rMin = 12, rMax = 40, yMin = 1, yMax = 6, speedMin = 2, speedMax = 4 },
		bat = { rMin = 40, rMax = 160, yMin = 15, yMax = 60, speedMin = 14, speedMax = 22 },
		firefly = { rMin = 10, rMax = 45, yMin = 1, yMax = 8, speedMin = 1, speedMax = 2 },
		owl = { rMin = 80, rMax = 240, yMin = 25, yMax = 80, speedMin = 10, speedMax = 16 },
		wisp = { rMin = 15, rMax = 60, yMin = 2, yMax = 12, speedMin = 1, speedMax = 3 },
		shootingStar = { rMin = 400, rMax = 1000, yMin = 200, yMax = 500, speedMin = 300, speedMax = 420 },
		starJelly = { rMin = 60, rMax = 200, yMin = 30, yMax = 120, speedMin = 2, speedMax = 5 },
		comet = { rMin = 700, rMax = 1500, yMin = 200, yMax = 600, speedMin = 90, speedMax = 140 },
	},
}

--============================================================================ server-side colours
-- Everything the server paints. Red is the hazard ring's alone: EnvConfig.spec runs isReddish over all of
-- these, and robloxemu/check_meteordroptycoon.luau over every Part the server actually built.
Config.Palette = {
	Ground = rgb(92, 130, 84),
	Disc = rgb(118, 158, 96),
	Rim = rgb(210, 190, 140),
	Arrival = rgb(240, 225, 170),
	SmelterBody = rgb(70, 72, 84),
	SmelterMouth = rgb(255, 170, 60),
	Chimney = rgb(96, 98, 110),
	HopperFrame = rgb(46, 48, 58),
	HopperFill = rgb(255, 190, 90),
	HopperFull = rgb(255, 230, 120),
	DishRim = rgb(120, 230, 255),
	DishFloor = rgb(170, 220, 240),
	BeaconBase = rgb(200, 205, 220),
	BeaconSegment = rgb(150, 160, 190),
	Crown = rgb(255, 215, 80),
	BoardFrame = rgb(60, 50, 80),
	BoardFace = rgb(24, 22, 40),
	Sign = rgb(236, 230, 210),
	Observatory = rgb(226, 222, 214),
	Dome = rgb(170, 190, 220),
	Telescope = rgb(90, 96, 120),
}

--============================================================================ hazards: rare space junk
-- deep-vein's vertical kinds (drop = "above"): on a flat plot plus1-jump's sideways lanes would start
-- ~8.9 studs underground (DESIGN.md section 6). The red ring is the zone, radius hitRadius + PlayerRadius;
-- stepping out of it in any direction always dodges. Client-only; a hit costs about 1.9 s and nothing else.
Config.Hazards = {
	IntervalMin = 120, -- s of non-rest time on your own plot between hazards [T]
	IntervalMax = 180,
	MinTelegraphSeconds = 3, -- [T]
	MinCommitSeconds = 1.5, -- [T]
	MaxRetargetSpeed = 1.5, -- [T]
	PlayerRadius = 1.5, -- [T]
	AimJitter = 0.8, -- [T: deep-vein]
	-- Kept only because Hazards.validate requires them; vertical kinds ignore the view cone [T: deep-vein].
	SpreadDegrees = 0,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	KnockLift = 8, -- studs/s up, capped at 15 by the module: a shove, never a launch [T]
	KnockSeconds = 0.9, -- PlatformStand after a hit [T]
	NearMissStuds = 6, -- for measurement only
	FirstBand = 2, -- a new player's first band (Dusk) is hazard-free
	RingColor = rgb(255, 40, 40), -- the ONLY red in the game: the zone, exactly (Hazards.zone)
	TrackColor = rgb(255, 210, 60), -- the ring while the hazard still tracks you, before it locks
	Kinds = {
		satellite = { drop = "above", height = 60, fall = 0.8, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.4, visualRadius = 3.2, knock = 36, label = "DEAD SATELLITE" },
		ice = { drop = "above", height = 60, fall = 0.7, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.6, knock = 34, label = "ICE CHUNK" },
		bolide = { drop = "above", height = 80, fall = 0.9, telegraph = 3.6, commit = 1.8, pass = 1.0,
			hitRadius = 3.0, visualRadius = 3.6, knock = 42, label = "BOLIDE" },
		plasma = { drop = "above", height = 60, fall = 1.0, telegraph = 3.4, commit = 1.7, pass = 1.0,
			hitRadius = 2.6, visualRadius = 3.0, knock = 34, label = "PLASMA BLOB" },
		neutron = { drop = "above", height = 70, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.4, knock = 44, label = "NEUTRON SHARD" },
	},
}

--============================================================================ rest: Stargaze
-- plus1-jump's Rest, verbatim. It pauses only hazards (their clock freezes, never resets); it earns
-- nothing standing still does not (pickups need walking, walking wakes you), and the Collector's
-- 10-minute timer does NOT freeze during rest.
Config.Rest = {
	IdleSeconds = 20, -- [T]
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4, -- [T]
	PendingSeconds = 7, -- outlives the longest flight (bolide 3.6 + 1.0 = 4.6 s) by more than 2 s [R]
}

--============================================================================ budgets, capped in code
Config.Budget = {
	-- client (measured per frame in robloxemu/check_meteordroptycoon_sky.luau)
	MaxLocalParts = 200,
	MaxEmitters = 4,
	MaxEmitterRate = 60,
	MaxWeatherEmitters = 2,
	MaxBeams = 8,
	MaxTrails = 8,
	MaxLights = 3,
	MaxHazards = 1,
	-- server (measured in robloxemu/check_meteordroptycoon.luau)
	MaxServerParts = 450, -- 29 static + 23 meteors per plot, x 8, + observatory + baseplate <= 447 [R]
	MaxServerLights = 16, -- one on each dish rim, one on each Beacon
	ObservatoryParts = 8,
}

--============================================================================ the pacing model's player profiles
-- tests/PlotModel.luau and tests/Pacing.spec.luau read these. NOT used by the game. ALL ASSUMPTIONS [A]:
-- replace `normal` with telemetry after the first real sessions and re-run Pacing.spec.
Config.Pacing = {
	BragMinutes = { 30, 45 }, -- the owner's window for a normal player
	HazardHitCost = 1.9, -- KnockSeconds 0.9 + ~1 s to turn back and walk on [A]
	HazardDodgeCost = 0.6, -- stepping out of the ring, then back on course [A]
	Profiles = {
		fast = { react = 0.4, retarget = 0.2, eff = 0.95, shopEvery = 10, buyTime = 0.8, hit = 0.10 },
		normal = { react = 0.8, retarget = 0.4, eff = 0.85, shopEvery = 20, buyTime = 1.2, hit = 0.25 },
		slow = { react = 1.5, retarget = 0.8, eff = 0.70, shopEvery = 45, buyTime = 2.0, hit = 0.40 },
		-- the script bound: no reaction, perfect line, buys the moment it can, at the trusted-speed cap
		bot = { react = 0, retarget = 0, eff = 1.35, shopEvery = 0.1, buyTime = 0, hit = 0 },
	},
}

return Config
