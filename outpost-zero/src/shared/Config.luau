--!strict
-- Outpost Zero: Sky City Tycoon — EVERY tunable in one place. Read by the server, both client scripts, the
-- pure modules (passed in as `cfg`) and every spec. DESIGN.md gives the reason for each number; the tag after a
-- value says where it came from ([M n] design/model.py part n, re-measured by tests/Pacing.spec.luau through
-- tests/CityModel.luau; [T] a template game; [R] a rule or worked arithmetic; [A] an assumption).
--
-- Colours are {r, g, b} (0-255), never Color3, so the pure modules and specs can read them in the luau CLI.
-- Nothing in here is secret: this module replicates. The only seeded thing in the game is a city's layout,
-- and its seed never leaves the server (DESIGN 10.3).

local Config = {}

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

--============================================================================ the world: six shelves in the sky
Config.World = {
	Shelves = 6, -- one per player; Players.MaxPlayers = 6 is a Studio setting (EYECANDY needs-Studio)
	RingRadius = 220, -- shelf centres on a ring, 60 degrees apart: rims 60 studs apart [R]
	ShelfRadius = 80, -- the rock disc, top at y = 0 [R]
	RockThickness = 6,
	RailRadius = 79, -- the parapet ring [R]
	ParapetSegments = 16, -- chords stay within 1.5 studs of the circle [R]
	WallHeight = 3, -- the stone wall a player sees
	GlassHeight = 12, -- invisible collidable glass above it: over any jump from the ground (7.2) [R]
	RescueY = -30, -- a character below this is put back on its own pad [R]
	KickMessage = "This server's 6 shelves are taken. Rejoin to get a server with room.",
	CloudSeaY = -80, -- client-drawn scenery only
}

-- Shelf-local coordinates: origin at the shelf centre, -Z faces district 1 and the ring's centre (City.toWorld).
Config.Shelf = {
	PlazaRadius = 26, -- no lot corner comes closer than 33.06 [M1]
	PlazaTopY = 0.2,
	HallSize = 14, -- the Town Hall's footprint, at the centre
	Arrival = { x = 0, z = -16 }, -- the SpawnLocation, 6 x 1 x 6, top at y = 1, facing -Z
	ArrivalSize = 6,
	ArrivalTopY = 1,
	Board = { x = -10, z = -16 }, -- the Census board, facing +X (toward the pad): 10 studs from it [R]
	LotCornerMax = 73, -- every lot corner within 73 of the centre (furthest measured 72.01 [M1])
	SpawnCorrectStuds = 8, -- CharacterAdded belt and braces: re-place a root further than this from the pad [T]
	RootAbovePad = 3, -- root height over a pad top when the server places a character [T]
	SpawnWaitFrames = 300, -- the bounded wait for char.Parent (robloxemu/SPAWN-ORDER.md) [T]
	SignU = 45, -- a locked district's sign stands this far out along its slot's axis
}

--============================================================================ lots and buildings
Config.Lots = {
	Size = 10, -- a 10 x 10 plate
	PlateHeight = 0.4, -- a kerb a character walks over without a jump [R]
	MinGap = 4, -- lots of one district are at least 4 studs apart [M1]
	BodySize = 8, -- the building's footprint, centred on the plate
	StoreyHeight = 4, -- just under a 5-stud avatar, so it reads as a floor [R]
	RoofHeight = 2,
	PostInset = 5.5, -- the sign post: half a stud outside the plate's inner edge, toward the shelf centre
	PostHeight = 4,
	PromptDistance = 8, -- MaxActivationDistance; posts are >= 14 studs apart [M1]
	GrowSeconds = 0.35, -- a new storey's server tween
	PromptReach = 6, -- the pacing model walks to 6 studs from a lot's centre (a conservative stand-in) [R]
}

-- u = distance from the shelf centre along the slot's axis, v = sideways; H = Home, W = Workshop.
Config.Templates = {
	Order = { "rows", "column", "arc" },
	rows = { { 44, -14, "H" }, { 44, 0, "W" }, { 44, 14, "H" }, { 58, -14, "W" }, { 58, 0, "H" }, { 58, 14, "W" } },
	column = { { 38, -7, "H" }, { 38, 7, "W" }, { 52, -7, "W" }, { 52, 7, "H" }, { 66, -7, "H" }, { 66, 7, "W" } },
	arc = { { 45.7, -14, "H" }, { 48, 0, "W" }, { 45.7, 14, "H" }, { 62.3, -14, "W" }, { 64, 0, "H" }, { 62.3, 14, "W" } },
}

--============================================================================ the economy
Config.Economy = {
	Wage = 0.25, -- credits per second per citizen: a starting pair pays for itself in 30 s [R]
	StartCredits = 30, -- exactly the first Home and the first Workshop [R]
	MaxStoreys = 22, -- the dead-end fix: the dearest storey is at most 256.3 s of income [M9, M2]
	Cap = { 4, 20, 100, 500, 2500, 12500 }, -- people per storey, 4 x 5^(d-1)
	Base = { 15, 90, 540, 3240, 19440, 116640 }, -- storey 1 price, 15 x 6^(d-1)
	Growth = 1.35, -- price x1.35 per storey: the brag at 37.1 min [M8]
	OrdersSeconds = 600, -- every build gives the workers 10 minutes of Orders [M3, M7]
	TickSeconds = 0.1, -- the server's economy tick (10 Hz)
	StateSeconds = 0.25, -- the owner's State payload at most 4 times a second (and on change)
	RateHalfLife = 20, -- the HUD's "+X/min" is a measured moving average
}

-- The six districts. A district opens when the population reaches `open`; its band (Config.Env.Bands) opens
-- with it. `palette` = facade colours (one drawn per building with the layout seed), `paving` = the lot plates,
-- `window` = the Neon strip, `roof` = the roof style, `hall` = the piece the Town Hall gains (server, public).
Config.Districts = {
	{ id = "landing", name = "Landing Field", open = 0, roof = "pitched", hall = "hut",
		palette = { rgb(170, 128, 86), rgb(150, 112, 78), rgb(236, 226, 200) }, roofColor = rgb(236, 226, 200),
		paving = rgb(186, 170, 140), window = rgb(255, 222, 150) },
	{ id = "market", name = "Market Row", open = 80, roof = "awning", hall = "clock",
		palette = { rgb(250, 215, 170), rgb(190, 225, 210), rgb(200, 210, 245) }, roofColor = rgb(120, 190, 200),
		paving = rgb(214, 200, 176), window = rgb(255, 236, 182) },
	{ id = "rail", name = "Sky-Rail Yard", open = 900, roof = "sawtooth", hall = "canopy",
		palette = { rgb(150, 80, 60), rgb(128, 92, 72), rgb(92, 96, 106) }, roofColor = rgb(84, 88, 98),
		paving = rgb(150, 150, 156), window = rgb(255, 204, 122) },
	{ id = "skyport", name = "Skyport", open = 6400, roof = "mast", hall = "mast",
		palette = { rgb(240, 240, 246), rgb(44, 58, 104), rgb(210, 220, 236) }, roofColor = rgb(200, 206, 220),
		paving = rgb(176, 190, 214), window = rgb(190, 222, 255) },
	{ id = "reactor", name = "Reactor Quarter", open = 35000, roof = "dome", hall = "halo",
		palette = { rgb(150, 160, 172), rgb(122, 132, 144), rgb(172, 182, 194) }, roofColor = rgb(110, 124, 138),
		paving = rgb(120, 140, 150), window = rgb(60, 222, 200) },
	{ id = "crown", name = "Crown Heights", open = 185000, roof = "spire", hall = "spire",
		palette = { rgb(246, 242, 234), rgb(232, 226, 214), rgb(250, 248, 240) }, roofColor = rgb(255, 212, 92),
		paving = rgb(230, 222, 200), window = rgb(255, 214, 100) },
}
Config.SkyportDistrict = 4 -- the Grand Airship's district: the brag moment (DESIGN 8)

--============================================================================ the brag: the Grand Airship
Config.Airship = {
	FlightSeconds = 12, -- each client flies its own copy in, then the server places the moored one [R]
	FlightFrom = 1500, -- studs out from the mast where the flight starts
	HullBottomY = 120, -- the tallest tower is 22 x 4 + 2 = 90 studs [R]
	GondolaY = 1.5, -- the gondola's centre over the hull bottom: the model's pivot, server and client alike [R]
	-- the moored airship keeps its nose (+X) along the shelf's +X, broadside to the plaza's view toward district 1
	-- (thumbnail 1); the flying copy comes in along that same line, nose first, so it hands over without turning
	-- (round 2, B2). The server sends the nose's direction with the arrival.
	HandOverSeconds = 3, -- the flying copy holds its last pose until the moored model replicates, at most this [A]
	HoldAfterSeconds = 3, -- hazards held from the title card until 3 s after mooring [R]
}

--============================================================================ the board, saving, prompts
Config.Save = {
	Store = "OutpostZero_v1",
	Version = 1,
	SeedMax = 2147483646, -- a layout seed is 1..SeedMax; seed x 7919 + 17 stays under 1.7e13 [R]
	FlushTickSeconds = 7, -- coalesced writes, at most one per player per tick [T]
	AutosaveSeconds = 60, -- renews the lock [T]
	LockSeconds = 120, -- twice the autosave [T]
	LoadAttempts = 3, -- [T: steal-a-cryptid, meteor-drop-tycoon REVIEW-1]
	LoadRetrySeconds = 1,
	LockWaitSeconds = 15,
	LockRetrySeconds = 5,
	LockRecheckSeconds = 15,
	WriteQueueSeconds = 60,
	RejoinWaitSeconds = 60, -- a rejoin to the same server waits this long, at most, for the leave-write [R: = WriteQueueSeconds]
}

Config.Board = {
	Store = "OutpostZero_Census_v1",
	Scale = 2e9, -- value = population x Scale + (Scale - popAt) [T: complete-game-standard.md]
	PublicSize = 10,
	Rows = 10, -- row slots on the board face; the viewer's own row is always one of them (Board.window)
	PublicCacheSeconds = 60,
	FriendsCap = 200,
	FriendReadsPerSecond = 1, -- per server
	BudgetReserve = 10,
	FriendCacheSeconds = 300, -- a friend's score
	FriendListCacheSeconds = 300, -- the friends LIST (GetFriendsAsync): one fetch per viewer per 5 min [R: = FriendCacheSeconds]
	FriendListRetrySeconds = 30, -- after a failed GetFriendsAsync, none for 30 s ("unavailable" at once meanwhile) [A]
	LeaveWriteAttempts = 3, -- the Census write at the leave: tried 3 times, 1 s then 2 s apart [T: Config.Save.LoadAttempts]
	LeaveRetrySeconds = 1,
	WriteMinInterval = 60, -- at most one board write per player per minute, plus one on leaving
	PromptDistance = 14, -- the board is 10 studs from the pad's centre, 13.3 from its far corners [R]
	MaxPopulation = 1031184, -- 36 lots x 22 storeys [M2]
}

Config.Prompts = {
	MaxPerSecond = 8, -- per player [T: steal-a-cryptid]
	SlowToastSeconds = 5,
	ForeignToastSeconds = 5,
}

-- The first-minutes hints: the persisted `tutorial` step 0..3, so a rejoin resumes and never repeats.
Config.Tutorial = {
	Walk = "Walk to the ★ lot and tap BUILD",
	NeedJobs = "Settlers need jobs: build the Workshop ★",
	NeedHomes = "Jobs need settlers: build the Home ★",
	Orders = "Every build keeps your workers busy for 10 minutes.",
	Star = "★ marks the build that pays for itself soonest. Lost it? Tap ★ Show me.",
	StarHintSeconds = 25, -- the last hint stays this long after it first appears
	NotSaving = "⚠️ Progress is not being saved this session",
	NotSavingLocked = "⚠️ Save open on another server: not saving until it lets go",
	LockWaiting = "⏳ Your city is open on another server. Waiting for it…",
	LockTaken = "✅ Your city is back: progress is being saved",
	LockChanged = "⚠️ Your city changed elsewhere: rejoin to load it (not saving)",
	Loading = "Loading your city…",
	Rescue = "The updraft caught you.",
	Idle = "💤 Workers idle: build anything to put them back to work",
}

--============================================================================ server-side colours
-- Everything the server paints. Red is the hazard ring's alone: EnvConfig.spec runs isReddish over all of these
-- and the districts, and robloxemu/check_outpostzero.luau over every Part the server actually built.
Config.Palette = {
	Rock = rgb(120, 112, 104),
	Plaza = rgb(206, 198, 184),
	Wall = rgb(168, 160, 150),
	Glass = rgb(200, 230, 255),
	Arrival = rgb(240, 226, 172),
	HallWood = rgb(150, 112, 76),
	HallCanvas = rgb(236, 226, 200),
	Windsock = rgb(255, 196, 90),
	Clock = rgb(250, 246, 226),
	Canopy = rgb(96, 100, 110),
	Mast = rgb(220, 224, 232),
	Halo = rgb(60, 222, 200),
	CrownGold = rgb(255, 212, 92),
	HallLight = rgb(255, 226, 170),
	BoardFrame = rgb(70, 58, 46),
	BoardFace = rgb(26, 28, 40),
	Sign = rgb(236, 230, 210),
	Post = rgb(92, 84, 76),
	Topped = rgb(255, 214, 100),
	AirshipHull = rgb(236, 230, 214),
	AirshipTrim = rgb(54, 66, 108),
	AirshipGondola = rgb(120, 92, 64),
	AirshipLamp = rgb(255, 214, 110),
}

--============================================================================ the sky: environment bands (client)
-- Everything under Config.Env is COSMETIC and client-side (src/client/Sky.client.luau). The trigger is the
-- owner's population, never time: the integer population names the band, the same number drives the blend
-- (each band fades in over `fade` population before its `from`), and every written value glides with HalfLife.
-- Each band opens with the district at the same population (EnvConfig.spec asserts `from` = Districts[i].open).
Config.Env = {
	HalfLife = 1.5, -- s: a purchase is a deliberate step the player should see happen [T: meteor-drop-tycoon]
	LightingHz = 10, -- Lighting is written at most 10x/s and only on change [T]
	BragBandId = "lantern", -- its district (Skyport) brings the Grand Airship

	Bands = {
		{
			id = "fog", from = 0, fade = 0, name = "Fogbound Dawn", emoji = "🌫️",
			-- = Fx.Presets.Dawn, so the client takes over from the server's light with no jump
			lighting = { ClockTime = 6.4, Brightness = 1.6, ExposureCompensation = 0.05,
				Ambient = rgb(110, 105, 115), OutdoorAmbient = rgb(150, 140, 155),
				FogStart = 80, FogEnd = 700, FogColor = rgb(215, 200, 210) },
			atmosphere = { Density = 0.45, Offset = 0.3, Color = rgb(215, 200, 210), Decay = rgb(170, 160, 175), Glare = 0.2, Haze = 2.4 },
			sky = { StarCount = 0, SunAngularSize = 18, MoonAngularSize = 9 },
			bloom = { Intensity = 0.8, Size = 26, Threshold = 0.95 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.04, Saturation = -0.05, TintColor = rgb(240, 232, 240) },
			sunRays = { Intensity = 0.06, Spread = 0.9 },
			pieces = { "fogBanks", "rockSpires" },
			ambient = { { kind = "gull", count = 3 } },
			weather = { kind = "fogWisps", rate = 4 },
			hazards = {},
		},
		{
			id = "morning", from = 80, fade = 30, name = "Clear Morning", emoji = "☀️",
			lighting = { ClockTime = 9.0, Brightness = 2.6, ExposureCompensation = 0.1,
				Ambient = rgb(120, 125, 135), OutdoorAmbient = rgb(160, 170, 185),
				FogStart = 200, FogEnd = 1800, FogColor = rgb(200, 220, 245) },
			atmosphere = { Density = 0.3, Offset = 0.25, Color = rgb(200, 220, 245), Decay = rgb(140, 170, 210), Glare = 0.4, Haze = 1.6 },
			sky = { StarCount = 0, SunAngularSize = 20, MoonAngularSize = 9 },
			bloom = { Intensity = 0.9, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.1, TintColor = rgb(250, 250, 255) },
			sunRays = { Intensity = 0.15, Spread = 0.8 },
			pieces = { "cloudSea", "farShelves" },
			ambient = { { kind = "swift", count = 5 } },
			weather = { kind = "seeds", rate = 5 },
			hazards = { "crate" },
		},
		{
			id = "trade", from = 900, fade = 300, name = "Trade Winds", emoji = "🎈",
			lighting = { ClockTime = 13.0, Brightness = 3.0, ExposureCompensation = 0.12,
				Ambient = rgb(125, 125, 130), OutdoorAmbient = rgb(170, 175, 185),
				FogStart = 300, FogEnd = 2400, FogColor = rgb(205, 225, 250) },
			atmosphere = { Density = 0.25, Offset = 0.2, Color = rgb(205, 225, 250), Decay = rgb(150, 180, 220), Glare = 0.5, Haze = 1.2 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 9 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.18, TintColor = rgb(255, 250, 240) },
			sunRays = { Intensity = 0.2, Spread = 0.7 },
			pieces = { "cloudSea", "farShelves", "pennants", "skyRail" },
			ambient = { { kind = "balloon", count = 3 } },
			weather = { kind = "leaves", rate = 8 },
			hazards = { "crate", "sandbag" },
		},
		{
			id = "lantern", from = 6400, fade = 2000, name = "Lantern Dusk", emoji = "🏮", celebrate = true,
			lighting = { ClockTime = 17.9, Brightness = 2.2, ExposureCompensation = 0.15,
				Ambient = rgb(120, 100, 95), OutdoorAmbient = rgb(170, 135, 120),
				FogStart = 300, FogEnd = 2200, FogColor = rgb(255, 190, 150) },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(255, 190, 150), Decay = rgb(190, 120, 100), Glare = 0.6, Haze = 1.8 },
			sky = { StarCount = 400, SunAngularSize = 22, MoonAngularSize = 10 },
			bloom = { Intensity = 1.5, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.2, TintColor = rgb(255, 232, 210) },
			sunRays = { Intensity = 0.25, Spread = 0.8 },
			pieces = { "cloudSea", "farShelves", "farWindows" },
			ambient = { { kind = "lantern", count = 12 } },
			weather = { kind = "sparks", rate = 10 },
			hazards = { "crate", "lantern" },
		},
		{
			id = "storm", from = 35000, fade = 10000, name = "Storm Front", emoji = "⛈️",
			lighting = { ClockTime = 20.5, Brightness = 1.1, ExposureCompensation = 0.2,
				Ambient = rgb(85, 85, 110), OutdoorAmbient = rgb(105, 105, 140),
				FogStart = 200, FogEnd = 1600, FogColor = rgb(110, 105, 150) },
			atmosphere = { Density = 0.4, Offset = 0.15, Color = rgb(110, 105, 150), Decay = rgb(80, 76, 120), Glare = 0.1, Haze = 2.0 },
			sky = { StarCount = 0, SunAngularSize = 12, MoonAngularSize = 11 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.14, Saturation = -0.05, TintColor = rgb(215, 215, 245) },
			sunRays = { Intensity = 0, Spread = 0.4 },
			pieces = { "cloudSea", "farWindows", "stormWall", "cloudLightning" },
			ambient = { { kind = "petrel", count = 3 } },
			weather = { kind = "rain", rate = 40 },
			hazards = { "lightning", "hail" },
		},
		{
			id = "aurora", from = 185000, fade = 50000, name = "Aurora Crown", emoji = "🌌",
			lighting = { ClockTime = 23.0, Brightness = 1.0, ExposureCompensation = 0.25,
				Ambient = rgb(90, 105, 120), OutdoorAmbient = rgb(110, 135, 160),
				FogStart = 600, FogEnd = 4000, FogColor = rgb(60, 90, 120) },
			atmosphere = { Density = 0.1, Offset = 0.05, Color = rgb(60, 90, 120), Decay = rgb(70, 120, 140), Glare = 0, Haze = 0.6 },
			sky = { StarCount = 3000, SunAngularSize = 10, MoonAngularSize = 13 },
			bloom = { Intensity = 1.6, Size = 36, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.15, TintColor = rgb(220, 245, 240) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "aurora", "farWindows", "cloudSea" },
			ambient = { { kind = "whale", count = 2 } },
			weather = { kind = "glitter", rate = 15 },
			hazards = { "shard", "lightning" },
		},
	},

	-- Weather, one emitter per kind, capped by EnvBands.capRates (Budget). Colours {r,g,b}; accel {x,y,z}.
	Weather = {
		fogWisps = { color = rgb(235, 230, 236), size = 14, lifetime = { 6, 9 }, speed = { 1, 2 }, lightEmission = 0.1, transparency = 0.86, accel = { 0.6, 0, 0.3 } },
		seeds = { color = rgb(255, 252, 236), size = 0.3, lifetime = { 6, 9 }, speed = { 1, 2 }, lightEmission = 0.2, transparency = 0.15, accel = { 0.8, -0.2, 0.4 } },
		leaves = { color = rgb(214, 190, 96), size = 0.45, lifetime = { 4, 7 }, speed = { 3, 6 }, lightEmission = 0, transparency = 0.1, accel = { 3, -1.2, 1 } },
		sparks = { color = rgb(255, 204, 120), size = 0.28, lifetime = { 2, 4 }, speed = { 2, 4 }, lightEmission = 1, transparency = 0.1, accel = { 0, 2, 0 } },
		rain = { color = rgb(180, 196, 230), size = 0.12, lifetime = { 0.8, 1.2 }, speed = { 40, 55 }, lightEmission = 0.2, transparency = 0.35, accel = { 0, -60, 0 } },
		glitter = { color = rgb(214, 240, 255), size = 0.22, lifetime = { 4, 7 }, speed = { 0.4, 1.2 }, lightEmission = 1, transparency = 0.15, accel = { 0, -0.6, 0 } },
	},

	-- Ambient life: never dangerous, never collidable. Distances in studs from the camera (EnvBands.ambientSpawn).
	Critters = {
		gull = { rMin = 40, rMax = 160, yMin = 10, yMax = 50, speedMin = 10, speedMax = 16 },
		swift = { rMin = 50, rMax = 200, yMin = 15, yMax = 60, speedMin = 18, speedMax = 26, flock = 5 },
		balloon = { rMin = 260, rMax = 600, yMin = 40, yMax = 160, speedMin = 4, speedMax = 8 },
		lantern = { rMin = 60, rMax = 260, yMin = -70, yMax = 10, speedMin = 3, speedMax = 5, rise = true }, -- rising out of the cloud sea
		petrel = { rMin = 60, rMax = 220, yMin = 10, yMax = 70, speedMin = 16, speedMax = 24 },
		whale = { rMin = 400, rMax = 900, yMin = 80, yMax = 260, speedMin = 6, speedMax = 10 },
	},

	-- Storm Front's silent lightning inside the cloud sea: distant, never full-screen, at most one flash per 3 s
	-- (under the common photosensitivity limit of three flashes a second) [R].
	LightningMinGap = 3,
}

--============================================================================ hazards: things fall off the frontier
-- Vertical kinds (meteor-drop-tycoon's merge of plus1-jump + deep-vein): a shelf is flat open ground, and a
-- sideways lane would start underground (DESIGN 6). The red ring is the zone, radius hitRadius + PlayerRadius;
-- stepping out of it in any direction always dodges. Client-only; a hit costs about 1.9 s and nothing else.
Config.Hazards = {
	IntervalMin = 120, -- s of non-rest time on your own shelf between hazards [T]
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
	KnockLift = 8, -- studs/s up: peaks at 0.16 studs [R]
	KnockSeconds = 0.9, -- PlatformStand after a hit [T]
	NearMissStuds = 6,
	FirstBand = 2, -- a new player's first band (Fogbound Dawn) is hazard-free
	RingColor = rgb(255, 40, 40), -- the ONLY red in the game: the zone, exactly (Hazards.zone)
	TrackColor = rgb(255, 210, 60), -- the pillar while the hazard still tracks you, before it locks
	WalkSpeed = 16, -- Humanoid default: the ring checks use it
	Kinds = {
		crate = { drop = "above", height = 60, fall = 0.8, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.4, visualRadius = 2.8, knock = 36, label = "CRATE" },
		sandbag = { drop = "above", height = 55, fall = 0.7, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.0, visualRadius = 2.2, knock = 32, label = "SANDBAG" },
		lantern = { drop = "above", height = 45, fall = 1.4, telegraph = 3.4, commit = 1.7, pass = 1.0,
			hitRadius = 2.0, visualRadius = 2.2, knock = 28, label = "SPENT LANTERN" },
		lightning = { drop = "above", height = 90, fall = 0.3, telegraph = 3.6, commit = 1.8, pass = 1.0,
			hitRadius = 2.6, visualRadius = 2.8, knock = 40, label = "LIGHTNING" },
		hail = { drop = "above", height = 70, fall = 0.7, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.4, knock = 34, label = "HAILSTONE" },
		shard = { drop = "above", height = 70, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.4, knock = 36, label = "ICE SHARD" },
	},
}

--============================================================================ rest: ☕ Break
-- plus1-jump's Rest, verbatim. It pauses only hazards (their clock freezes, never resets); income depends only
-- on population and Orders, and the Orders keep counting down during a break.
Config.Rest = {
	IdleSeconds = 60, -- 0.5 % of a normal player's first hour (max 1.2 %); 20 s would be 16.6 % [M10]
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4, -- [T]
	PendingSeconds = 7, -- outlives the longest flight (lightning 3.6 + 1.0 = 4.6 s) by more than 2 s [R]
}

--============================================================================ budgets, capped in code
Config.Budget = {
	-- client (measured per frame in robloxemu/check_outpostzero_sky.luau)
	MaxLocalParts = 200,
	MaxEmitters = 4,
	MaxEmitterRate = 60,
	MaxWeatherEmitters = 2,
	MaxBeams = 8,
	MaxTrails = 8,
	MaxLights = 3,
	MaxHazards = 1,
	-- server (measured in robloxemu/check_outpostzero.luau)
	MaxServerParts = 1500, -- <= 244 per shelf x 6 = 1464 [R]
	MaxServerLights = 12, -- one in each Town Hall, one on each moored airship
	ShelfParts = 244, -- rock 1 + plaza 1 + parapet 32 + hall 10 + pad 1 + board 2 + signs 5 + lots 180 + airship 12
}

--============================================================================ the pacing model's player profiles
-- tests/CityModel.luau and tests/Pacing.spec.luau read these. NOT used by the game. ALL ASSUMPTIONS [A]:
-- replace `normal` with telemetry after the first real sessions and re-run Pacing.spec.
Config.Pacing = {
	BragMinutes = { 30, 45 }, -- the owner's window for a normal player
	WalkSpeed = 16,
	HazardHitCost = 1.9, -- KnockSeconds 0.9 + about 1 s to turn back and walk on [A]
	Profiles = {
		fast = { react = 0.4, eff = 0.95, notice = 1.0, buy = 0.6, hit = 0.10 },
		normal = { react = 1.0, eff = 0.85, notice = 3.0, buy = 1.0, hit = 0.25 },
		slow = { react = 2.0, eff = 0.70, notice = 8.0, buy = 1.5, hit = 0.40 },
		-- a perfect walking macro: no reaction, a straight line, pressing at the prompt rate limit
		walker = { react = 0, eff = 1.0, notice = 0, buy = 0.125, hit = 0 },
		-- an exploit: no walking at all (teleport + fire the prompt from anywhere)
		teleport = { react = 0, eff = math.huge, notice = 0, buy = 0.125, hit = 0 },
	},
	ProfileOrder = { "fast", "normal", "slow", "walker", "teleport" },
}

return Config
