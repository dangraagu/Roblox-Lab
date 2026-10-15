--!strict
-- Scrapline Tycoon — EVERY tunable in one place. Read by the server, both client scripts, the pure modules
-- (passed in as `cfg`) and every spec. DESIGN.md gives the reason for each number; the tag after a value says
-- where it came from ([M n] design/model.py part n, [T] a template game, [R] a rule or worked arithmetic,
-- [A] an assumption). tests/Pacing.spec.luau re-measures the pacing FROM THIS FILE (tests/LineModel.luau).
--
-- Colours are {r, g, b} (0-255), never Color3, so the pure modules and specs can read them in the luau CLI.
-- Nothing in here is secret: this module replicates, and nothing in the game is seeded from it.
--
-- Indexing used everywhere: a PRODUCT has a state 0..6 (Junk..Rocket) and is stored at index state + 1 in
-- every product array. STATION t (1..6) turns state t-1 into state t. Station ids are strings
-- ("shredder" .. "rocketbay"), so nothing persisted or sent ever has integer keys.

local Config = {}

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

--============================================================================ the world
Config.World = {
	Plots = 6, -- one per player, Players.MaxPlayers = 6 (a Studio setting, EYECANDY needs-Studio) [R]
	RingRadius = 150, -- plot centres on a ring around the Scrap Market, 60 degrees apart [R]
	BaseplateSize = 400, -- one continuous ground plate, top at y = 0 [R]
	-- REVIEW-2 R7: the plate ended 12 studs behind plots 1 and 4 with nothing there. Four invisible, collidable walls
	-- stand on its edges, so nothing can fall off the world (a jump is 7.2 studs, a knock lifts at most 15/s) [R]
	EdgeWallHeight = 60,
	EdgeWallThickness = 4,
	GroundY = 0,
	FloorTopY = 0.2, -- each plot's floor slab sits 0.2 above the plate
	MarketRadius = 30, -- the Scrap Market landmark at the origin, decorative [R]
	MarketMaxParts = 20,
	KickMessage = "This server's 6 factories are taken. Rejoin to get a server with room.",
}

-- Plot-local positions: origin at the plot centre, -Z points at the Scrap Market. The plot is 64 x 76 studs.
Config.Plot = {
	HalfX = 32,
	HalfZ = 38,
	Arrival = { x = 0, z = -30 }, -- the SpawnLocation, 6 x 1 x 6, top at y = 1, facing +Z (up the U)
	ArrivalSize = 6,
	ArrivalTopY = 1,
	Chute = { x = -14, z = -29, size = 8, height = 10 }, -- the junk hopper, front-left
	Dock = { x = 14, z = -29, size = 8, height = 1.2 }, -- the shipping dock, front-right; low enough to stand on
	LaunchPad = { x = 26, z = -28, radius = 4, height = 0.6 },
	-- REVIEW-2 R1: the board was 7 x 4.5 with 10 rows of 0.229 studs, 3.3 px tall on a phone at Roblox's default
	-- camera. Now 10 x 10 (face 10 x 9.2, 11 rows of 0.686 studs): reading it from 5 studs, a row is as tall as the
	-- HUD's own hint text. It stands on the DOCK side of the arrival, 11.4 studs from its centre, so it hides
	-- neither the chute nor the Shredder (the first job); 0.8 studs clear of the right belt leg, 0.75 of the dock [R]
	Board = { x = 7, z = -21, width = 10, height = 10 },
	Belt = { legX = 14, z0 = -25, z1 = 19, turnZ = 19, turnRadius = 14, width = 4, topY = 1, turnSegments = 6, speed = 10 },
	-- station centres along the flow: left leg up (+Z), U-turn, right leg down (-Z)
	StationCentres = { { x = -14, z = -16 }, { x = -14, z = -2 }, { x = -14, z = 12 }, { x = 14, z = 12 }, { x = 14, z = -2 }, { x = 14, z = -16 } },
	MachineOffset = 3.5, -- machine a sits 3.5 studs upstream of the centre, its twin 3.5 downstream [R]
	MachineAlong = 6,
	MachineAcross = 8,
	ConsoleInset = 9, -- each station's console pad, inside the U at x = -9 / +9 [R]
	ConsoleSize = { x = 3, y = 0.4, z = 5 },
	Wall = { z = 37, depth = 2, halfX = 30, height = 14, chimneyHeight = 24, chimneyX = 22 },
	CraneHeight = 28, -- the gantry crane's rails along x = +-30 [R]
	SpawnCorrectStuds = 8, -- CharacterAdded belt and braces: re-place a root further than this from the pad
	RootAbovePad = 3, -- vault-runners' root height over a pad top [T]
	SpawnWaitFrames = 300, -- the bounded wait for char.Parent (SPAWN-ORDER.md) [T]
}

--============================================================================ products and stations
Config.Products = {
	Names = { "Junk", "Scrap", "Ingot", "Plate", "Gear", "Robot", "Rocket" },
	Values = { 1, 2, 5, 12, 30, 75, 200 }, -- about x2.5 per step [M1]
	-- belt item colours; none is reddish (EnvConfig.spec, isReddish)
	Colors = { rgb(120, 100, 80), rgb(150, 150, 160), rgb(255, 160, 60), rgb(205, 215, 225), rgb(205, 165, 60),
		rgb(140, 200, 255), rgb(245, 245, 250) },
}

Config.Stations = {
	Order = { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" },
	Names = { "Shredder", "Furnace", "Press", "Cutter", "Assembler", "Rocket Bay" },
	Emoji = { "🔨", "🔥", "🗜️", "✂️", "🤖", "🚀" },
	BuildPrice = { 0, 650, 13000, 130000, 1100000, 9500000 }, -- the Shredder is free (one tap) [M1, M8]
	BaseSpeed = { 1.0, 1.6, 2.6, 4.1, 6.6, 10.5 }, -- items/s per machine at level 1, x1.6 per station [M1]
	SpeedGrowth = 1.25, -- x per level, shared by a station's machine and twin [M8]
	-- level 1 -> 2 costs UpgradeBase = 8 x BaseSpeed x (value the station adds per item), rounded: every first
	-- upgrade pays for itself in 8 / (1.25 - 1) = 32 s [M1]
	UpgradeBase = { 8, 38, 146, 590, 2380, 10500 },
	UpgradeGrowth = 1.5, -- [M8]
	TwinPrice = 30, -- the twin costs TwinPrice x the station's first upgrade [M1]
	MaxLevel = 100, -- a safety cap only [M5]
	MachineHeight = { 6, 7, 8, 7, 8, 9 },
	-- server colours (never red)
	Colors = { rgb(110, 122, 134), rgb(96, 76, 66), rgb(70, 110, 170), rgb(60, 160, 150), rgb(240, 200, 70), rgb(230, 235, 245) },
	Accents = { rgb(255, 220, 90), rgb(255, 150, 50), rgb(170, 210, 255), rgb(90, 200, 255), rgb(120, 230, 255), rgb(255, 215, 120) },
}

Config.Line = {
	ChuteTrickle = 0.5, -- junk/s before the Shredder exists (and the floor while it is jammed) [M1]
	TickSeconds = 0.5, -- the server sells what reaches the dock on its own clock [T: meteor-drop-tycoon]
	TraceSeconds = 0.1, -- the trusted position steps at 10 Hz
	StateSeconds = 0.5, -- the owner's State is pushed at most this often (and at once on a change)
	LineStateSeconds = 1, -- LineState to all, at most this often on change...
	LineResendSeconds = 5, -- ...and this often anyway (a client that started late still draws every line)
	VisualItemsMaxRate = 2.5, -- client belt items per second at most [R]
}

-- The HUD's star (Economy.star): rule 0 saves for the next station from SaveWindow seconds of income [M2, M8].
Config.Star = {
	SaveWindow = 60,
	-- REVIEW-2 R3: the panel paints an affordable purchase GREEN only when it is the next station or pays for itself
	-- within GreenPayback x the best payback on the list, and paints nothing green while the ★ saves for the next
	-- station (Economy.worth). A player who taps any green button, at random, lands the first Rocket in 30-45 min
	-- (tests/Pacing.spec.luau: the `green` profiles); one who taps any affordable button still takes about 53 [M: Pacing]
	GreenPayback = 2,
}

--============================================================================ jams: the one active job
Config.Jams = {
	FirstJamIn = 240, -- s of line time before a brand-new profile's first sputter [R]
	JamMin = 150, -- s of line time between sputters [M2]
	JamMax = 210,
	SputterSeconds = 15, -- hold Fix within this, or it jams [R, M2]
	FixHold = 0.5, -- the prompt's HoldDuration
	FixRange = 12, -- studs, from the TRUSTED position to the machine (the prompt shows at 10) [R]
	PromptDistance = 10,
}

--============================================================================ recycle and the Gold Bolt
Config.Recycle = {
	Rate0 = 1500, -- rockets/s the line must ship for recycle 1 [M4]
	RateGrowth = 1.35, -- x per recycle [M4]
	BoltValue = 0.5, -- value multiplier = 1 + BoltValue x bolts [M4]
	SequenceSeconds = 3, -- the crumble + flash; Buy, Fix and hazards wait [R]
	GoldenBolts = 4, -- the Golden Factory (the long-term goal) [M4]
	-- REVIEW-2 X3: after a recycle write FAILS, the next try waits this long. One client firing Recycle at the remote
	-- limit made about 7 profile writes a second against a write budget (60 + 10 x players a minute) that every
	-- autosave on the server shares [R]
	RetrySeconds = 10,
}

-- Factory grades by Gold Bolts (server paint on the wall, chimneys, chute and dock; never red).
Config.Grades = {
	{ name = "Rusty", emoji = "🔧", color = rgb(150, 90, 50), material = "CorrugatedPlate", reflectance = 0 },
	{ name = "Painted", emoji = "🎨", color = rgb(230, 190, 60), material = "SmoothPlastic", reflectance = 0 },
	{ name = "Steel", emoji = "🔩", color = rgb(170, 180, 190), material = "Metal", reflectance = 0.05 },
	{ name = "Chrome", emoji = "💎", color = rgb(220, 225, 235), material = "Metal", reflectance = 0.35 },
	{ name = "Gold", emoji = "🥇", color = rgb(255, 200, 60), material = "Foil", reflectance = 0.2 },
}

--============================================================================ trust, save, board, remotes
Config.Trace = {
	WalkSpeed = 16, -- Humanoid default; the server writes it
	TrustedSpeedFactor = 1.35, -- 21.6 studs/s [T: vault-runners]
	BurstSeconds = 3, -- [T: vault-runners]
}

Config.Save = {
	Store = "ScraplineTycoon_v1",
	Version = 1,
	FlushTickSeconds = 7, -- coalesced writes, at most one per player per tick [T]
	AutosaveSeconds = 60, -- renews the lock and saves cash [T]
	LockSeconds = 120, -- twice the autosave [T]
	LoadAttempts = 3, -- [T: meteor-drop-tycoon REVIEW-1]
	LoadRetrySeconds = 1,
	LockWaitSeconds = 15,
	LockRetrySeconds = 5,
	LockRecheckSeconds = 15,
	WriteQueueSeconds = 60,
	-- REVIEW-1 A3: a rejoin on the SAME server waits (at most this long) for its own leave's writes to land before it
	-- loads; the lock lets a session on this JobId through, so without the wait the rejoin's load took the owner
	-- token and the leave's release write was cancelled (up to AutosaveSeconds of income lost) [R]
	LeaveWaitSeconds = 30,
}

Config.Board = {
	Store = "ScraplineTycoon_Board_v1",
	Scale = 2e9, -- value = bolts * Scale + (Scale - boltsAt) [T: complete-game-standard.md]
	PublicSize = 10,
	PublicCacheSeconds = 60,
	FriendsCap = 200,
	FriendReadsPerSecond = 1, -- per server
	BudgetReserve = 10, -- keep this much GetAsync budget for everything else
	FriendCacheSeconds = 300,
	PromptDistance = 13, -- the board's face centre is 11.5 studs from a player on the arrival pad [R]
	ShownRows = 11, -- the public top 10 (PublicSize) and, below it, the viewer's own row when it is not in it (REVIEW-2 R2)
	ResendSeconds = 30, -- the owner's board is re-sent (a slow HUD still gets its rows)
	-- REVIEW-1 A2: a client spamming BoardView must not multiply the server's web calls [T: deep-vein's caches]
	NameRetrySeconds = 60, -- a failed GetNameFromUserIdAsync is not retried sooner (one lookup per id in flight)
	FriendListSeconds = 300, -- each viewer's friend list (GetFriendsAsync) is fetched at most this often...
	FriendListRetrySeconds = 60, -- ...and a failed fetch is retried no sooner than this
}

Config.Remotes = {
	MaxPerSecond = 8, -- per remote per player [T: steal-a-cryptid]
	SlowToastSeconds = 5,
}

-- The first-minutes hints (the persisted `tutorial` step 0..4, so a rejoin resumes and never repeats).
Config.Tutorial = {
	Build = "🔧 Tap Build Shredder (or its glowing pad) to place your free Shredder",
	Upgrade = "Your Shredder makes Scrap. Tap 🏭 Line, then ⬆ on the ★ row to speed it up",
	Save = "Save for a Furnace ★: Ingots sell for more", -- shown only while the ★ IS the Furnace (REVIEW-2 R4)
	Follow = "Buy the ★ row in 🏭 Line: it is the best buy for your line right now", -- step 2 until then
	Fix = "⚠ A machine is sputtering! Walk to it and hold Fix",
	NotSaving = "⚠️ Progress is not being saved this session",
	NotSavingLocked = "⚠️ Save open on another server: not saving until it lets go",
	LockWaiting = "⏳ Your save is open on another server. Waiting for it…",
	LockTaken = "✅ Your save is back: progress is being saved",
	LockChanged = "⚠️ Your save changed elsewhere: rejoin to load it (not saving)",
	LeaveWaiting = "⏳ Still saving your last visit on this server…",
}

--============================================================================ the environment bands
-- Everything under Config.Env is COSMETIC and client-side (src/client/Yard.client.luau), except each band's
-- `accent`, the SCRAPLINE sign's neon, which the server shows everyone. The trigger is the highest product the
-- line has shipped this run (`tier`, 0..6): the game's own logic, never time. Every band has fade 0 (a new
-- product is a discrete achievement); every written value glides with HalfLife.
Config.Env = {
	HalfLife = 1.5, -- s: the glide to a new band [T: meteor-drop-tycoon]
	LightingHz = 10, -- Lighting is written at most 10x/s and only on change [T]
	BragBandId = "launchsite", -- entering it = the first rocket's lift-off (the brag moment)

	Bands = {
		{
			id = "junkyard", from = 0, fade = 0, name = "Junkyard", emoji = "🏚️", product = "Scrap",
			-- = Fx.Presets.Junkyard, so the client takes over from the server's light with no jump
			lighting = { ClockTime = 13.0, Brightness = 2.6, ExposureCompensation = 0.05,
				Ambient = rgb(130, 120, 105), OutdoorAmbient = rgb(160, 150, 130),
				FogStart = 250, FogEnd = 1500, FogColor = rgb(210, 190, 150) },
			atmosphere = { Density = 0.35, Offset = 0.2, Color = rgb(210, 190, 150), Decay = rgb(170, 140, 100), Glare = 0.3, Haze = 2.0 },
			sky = { StarCount = 0, SunAngularSize = 18, MoonAngularSize = 11 },
			bloom = { Intensity = 0.8, Size = 24, Threshold = 0.95 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.06, Saturation = 0.05, TintColor = rgb(255, 245, 225) },
			sunRays = { Intensity = 0.12, Spread = 0.7 },
			pieces = { "junkMounds", "tyreStacks", "carHulks" },
			ambient = { { kind = "crow", count = 5 } },
			weather = { kind = "dust", rate = 6 },
			hazards = {},
			accent = rgb(230, 190, 90),
		},
		{
			id = "foundry", from = 2, fade = 0, name = "Foundry", emoji = "🔥", product = "Ingot",
			lighting = { ClockTime = 15.5, Brightness = 2.3, ExposureCompensation = 0.1,
				Ambient = rgb(135, 110, 90), OutdoorAmbient = rgb(170, 135, 110),
				FogStart = 250, FogEnd = 1500, FogColor = rgb(230, 160, 110) },
			atmosphere = { Density = 0.3, Offset = 0.2, Color = rgb(230, 160, 110), Decay = rgb(180, 110, 70), Glare = 0.4, Haze = 1.8 },
			sky = { StarCount = 0, SunAngularSize = 20, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.12, TintColor = rgb(255, 232, 205) },
			sunRays = { Intensity = 0.15, Spread = 0.7 },
			pieces = { "brickChimneys", "junkMounds" },
			ambient = { { kind = "pigeon", count = 4 } },
			weather = { kind = "embers", rate = 10 },
			hazards = { "scrapBale" },
			accent = rgb(255, 150, 50),
		},
		{
			id = "pressworks", from = 3, fade = 0, name = "Press Works", emoji = "🏗️", product = "Plate",
			lighting = { ClockTime = 17.0, Brightness = 2.0, ExposureCompensation = 0.1,
				Ambient = rgb(115, 105, 110), OutdoorAmbient = rgb(150, 135, 150),
				FogStart = 300, FogEnd = 1700, FogColor = rgb(200, 150, 150) },
			atmosphere = { Density = 0.25, Offset = 0.15, Color = rgb(200, 150, 150), Decay = rgb(150, 110, 120), Glare = 0.4, Haze = 1.5 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 12 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.1, TintColor = rgb(245, 230, 235) },
			sunRays = { Intensity = 0.18, Spread = 0.75 },
			pieces = { "girders", "waterTower" },
			ambient = { { kind = "swallow", count = 5 } },
			weather = { kind = "steam", rate = 5 },
			hazards = { "scrapBale", "pipe" },
			accent = rgb(120, 170, 230),
		},
		{
			id = "machineshop", from = 4, fade = 0, name = "Machine Shop", emoji = "⚙️", product = "Gear",
			lighting = { ClockTime = 18.3, Brightness = 1.5, ExposureCompensation = 0.15,
				Ambient = rgb(95, 100, 115), OutdoorAmbient = rgb(120, 125, 160),
				FogStart = 350, FogEnd = 2000, FogColor = rgb(150, 140, 190) },
			atmosphere = { Density = 0.2, Offset = 0.12, Color = rgb(150, 140, 190), Decay = rgb(120, 100, 150), Glare = 0.3, Haze = 1.2 },
			sky = { StarCount = 300, SunAngularSize = 18, MoonAngularSize = 12 },
			bloom = { Intensity = 1.3, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.12, TintColor = rgb(230, 235, 255) },
			sunRays = { Intensity = 0.1, Spread = 0.6 },
			pieces = { "farGears", "girders" },
			ambient = { { kind = "drone", count = 3 } },
			weather = { kind = "goldSparks", rate = 8 },
			hazards = { "pipe", "bigGear" },
			accent = rgb(90, 220, 200),
		},
		{
			id = "robotworks", from = 5, fade = 0, name = "Robot Works", emoji = "🤖", product = "Robot",
			lighting = { ClockTime = 20.5, Brightness = 1.1, ExposureCompensation = 0.2,
				Ambient = rgb(80, 80, 110), OutdoorAmbient = rgb(100, 95, 150),
				FogStart = 400, FogEnd = 2400, FogColor = rgb(70, 60, 120) },
			atmosphere = { Density = 0.18, Offset = 0.08, Color = rgb(70, 60, 120), Decay = rgb(90, 70, 140), Glare = 0.1, Haze = 1.0 },
			sky = { StarCount = 1500, SunAngularSize = 14, MoonAngularSize = 13 },
			bloom = { Intensity = 1.6, Size = 34, Threshold = 0.78 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.2, TintColor = rgb(235, 220, 255) },
			sunRays = { Intensity = 0, Spread = 0.4 },
			pieces = { "neonSigns", "holoBoards", "searchlights" },
			ambient = { { kind = "deliveryDrone", count = 4 } },
			weather = { kind = "rain", rate = 25 },
			hazards = { "boltBucket", "parcel" },
			accent = rgb(0, 230, 255),
		},
		{
			id = "launchsite", from = 6, fade = 0, name = "Launch Site", emoji = "🚀", product = "Rocket", celebrate = true,
			lighting = { ClockTime = 22.5, Brightness = 0.9, ExposureCompensation = 0.25,
				Ambient = rgb(95, 95, 120), OutdoorAmbient = rgb(120, 120, 160),
				FogStart = 600, FogEnd = 4000, FogColor = rgb(30, 30, 60) },
			atmosphere = { Density = 0.08, Offset = 0.05, Color = rgb(30, 30, 60), Decay = rgb(70, 70, 120), Glare = 0, Haze = 0.5 },
			sky = { StarCount = 4000, SunAngularSize = 10, MoonAngularSize = 16 },
			bloom = { Intensity = 1.8, Size = 40, Threshold = 0.72 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.22, TintColor = rgb(245, 240, 255) },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "gantry", "bigMoon", "sweepLights" },
			ambient = { { kind = "satellite", count = 2 }, { kind = "farRocket", count = 1 } },
			weather = { kind = "stardust", rate = 6 },
			hazards = { "boosterCap", "bigGear" },
			accent = rgb(255, 230, 150),
		},
	},

	-- Weather, one emitter per kind, capped by EnvBands.capRates (Budget). Colours {r,g,b}; accel {x,y,z}.
	Weather = {
		dust = { color = rgb(225, 205, 165), size = 0.3, lifetime = { 6, 9 }, speed = { 0.5, 1.5 }, lightEmission = 0.1, transparency = 0.3, accel = { 0.4, -0.1, 0.2 } },
		embers = { color = rgb(255, 170, 70), size = 0.25, lifetime = { 2, 4 }, speed = { 2, 5 }, lightEmission = 1, transparency = 0.1, accel = { 0, 2, 0 } },
		steam = { color = rgb(235, 235, 240), size = 6, lifetime = { 4, 7 }, speed = { 1, 2 }, lightEmission = 0.1, transparency = 0.8, accel = { 0, 0.8, 0 } },
		goldSparks = { color = rgb(255, 215, 110), size = 0.2, lifetime = { 1, 2 }, speed = { 3, 6 }, lightEmission = 1, transparency = 0.1, accel = { 0, -6, 0 } },
		rain = { color = rgb(170, 190, 230), size = 0.15, lifetime = { 1, 1.5 }, speed = { 20, 26 }, lightEmission = 0.3, transparency = 0.35, accel = { 0, -40, 0 } },
		stardust = { color = rgb(210, 215, 255), size = 0.25, lifetime = { 5, 8 }, speed = { 0.2, 0.8 }, lightEmission = 1, transparency = 0.2, accel = { 0, 0, 0 } },
	},

	-- Ambient life: never dangerous, never collidable. Distances in studs from the camera (EnvBands.ambientSpawn).
	Critters = {
		crow = { rMin = 50, rMax = 200, yMin = 18, yMax = 60, speedMin = 14, speedMax = 20, flock = 5 },
		pigeon = { rMin = 30, rMax = 140, yMin = 12, yMax = 40, speedMin = 10, speedMax = 16, flock = 4 },
		swallow = { rMin = 60, rMax = 220, yMin = 20, yMax = 70, speedMin = 18, speedMax = 26, flock = 5 },
		drone = { rMin = 25, rMax = 90, yMin = 14, yMax = 34, speedMin = 5, speedMax = 9 },
		deliveryDrone = { rMin = 40, rMax = 160, yMin = 20, yMax = 60, speedMin = 10, speedMax = 16 },
		satellite = { rMin = 500, rMax = 1100, yMin = 300, yMax = 600, speedMin = 40, speedMax = 70 },
		farRocket = { rMin = 600, rMax = 1000, yMin = 0, yMax = 40, speedMin = 60, speedMax = 80, rise = true },
	},
}

--============================================================================ server-side colours
-- Everything the server paints. Red is the hazard ring's alone: EnvConfig.spec runs isReddish over all of
-- these, and robloxemu/check_scraplinetycoon.luau over every Part the server actually built.
Config.Palette = {
	Ground = rgb(120, 112, 96),
	Floor = rgb(92, 92, 98),
	Curb = rgb(200, 180, 60),
	Belt = rgb(44, 46, 52),
	BeltRail = rgb(150, 150, 160),
	Arrival = rgb(230, 225, 205),
	Console = rgb(70, 74, 86),
	ConsoleNext = rgb(120, 230, 160),
	ChuteGlow = rgb(255, 200, 100),
	DockGlow = rgb(120, 220, 255),
	LaunchPad = rgb(80, 82, 90),
	LaunchRing = rgb(255, 210, 80),
	Chimney = rgb(110, 100, 96),
	Crane = rgb(230, 180, 40),
	BoardFrame = rgb(60, 56, 70),
	BoardFace = rgb(24, 24, 32),
	Sign = rgb(236, 230, 210),
	Market = rgb(130, 110, 90),
	MarketRust = rgb(160, 100, 60),
	LevelPlate = rgb(30, 30, 36),
	Sputter = rgb(255, 190, 40), -- amber: a machine needs you
	Smoke = rgb(110, 110, 116),
	JamSign = rgb(255, 200, 40),
	Rocket = rgb(245, 245, 250),
	RocketFin = rgb(255, 200, 60),
}

--============================================================================ hazards: the crane drops something
-- meteor-drop-tycoon's merged Hazards.luau (plus1-jump + deep-vein's marked vertical kinds): the yard is flat and
-- open, so a sideways lane would start underground; the crane's trolley gives a natural source straight overhead.
-- The red ring is the zone, radius hitRadius + PlayerRadius; stepping out of it in any direction always dodges.
-- Client-only; a hit costs a stumble and nothing else. Rows: meteor-drop-tycoon's Kinds with the crane's height.
Config.Hazards = {
	IntervalMin = 120, -- s of non-rest time on your own plot between hazards [T]
	IntervalMax = 180,
	MinTelegraphSeconds = 3, -- [T]
	MinCommitSeconds = 1.5, -- [T]
	MaxRetargetSpeed = 1.5, -- [T]
	PlayerRadius = 1.5, -- [T]
	AimJitter = 0.8, -- [T: deep-vein]
	SpreadDegrees = 0, -- kept only because Hazards.validate requires them [T: deep-vein]
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	KnockLift = 8, -- studs/s up, capped at 15 by the module: a shove, never a launch [T]
	KnockSeconds = 0.9, -- PlatformStand after a hit [T]
	NearMissStuds = 6, -- for measurement only
	-- REVIEW-1 B5: a grounded root more than this above the highest LOW surface under it (PlotGeom.floors) stands on a
	-- machine, the crate or a wall, where the ring would be drawn hidden below it: nothing launches or tracks there.
	-- A root stands about 3 over what it stands on (2.5 headless): on any low surface it is at most 3.5 over it; on
	-- the lowest machine (the Shredder, top 6.2, over the belt at 1.0) it is 8 over [R]
	StandAboveFloorMax = 5,
	FirstBand = 2, -- the Junkyard is hazard-free
	RingColor = rgb(255, 40, 40), -- the ONLY red in the game: the zone, exactly (Hazards.zone)
	TrackColor = rgb(255, 210, 60), -- the ring while the hazard still tracks you, before it locks
	Kinds = {
		scrapBale = { drop = "above", height = 25, fall = 0.8, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.4, visualRadius = 3.2, knock = 36, label = "SCRAP BALE" },
		pipe = { drop = "above", height = 25, fall = 0.7, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.6, knock = 34, label = "PIPE" },
		bigGear = { drop = "above", height = 25, fall = 0.9, telegraph = 3.6, commit = 1.8, pass = 1.0,
			hitRadius = 3.0, visualRadius = 3.6, knock = 42, label = "BIG GEAR" },
		boltBucket = { drop = "above", height = 25, fall = 1.0, telegraph = 3.4, commit = 1.7, pass = 1.0,
			hitRadius = 2.6, visualRadius = 3.0, knock = 34, label = "BOLT BUCKET" },
		parcel = { drop = "above", height = 25, fall = 0.6, telegraph = 3.2, commit = 1.6, pass = 1.0,
			hitRadius = 2.2, visualRadius = 2.4, knock = 44, label = "DROPPED PARCEL" },
		boosterCap = { drop = "above", height = 80, fall = 0.9, telegraph = 3.6, commit = 1.8, pass = 1.0,
			hitRadius = 3.0, visualRadius = 3.6, knock = 42, label = "BOOSTER CAP" },
	},
}

--============================================================================ rest: ☕ Break
-- plus1-jump's Rest, verbatim. It pauses only hazards (their clock freezes, never resets); the line earns the
-- same whether you rest or not, and the jam clock does NOT freeze during rest.
Config.Rest = {
	-- 0 = no idle rest, only ☕ Break (Rest.validate: "0 disables idle rest"). ADAPTATION (REVIEW-1 B3): +1 Jump is
	-- played moving, so standing still there means away; a tycoon is played standing still and tapping the HUD, and
	-- the template's 20 s idle rest froze the crane for exactly those players (the walk: one drop per 31.6 min
	-- instead of one per 2-3 min, and the band chip said "Resting" most of the game).
	IdleSeconds = 0,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4, -- [T]
	PendingSeconds = 7, -- outlives the longest flight (big gear and booster cap: 3.6 + 1.0 = 4.6 s) by > 2 s [R]
}

--============================================================================ budgets, capped in code
Config.Budget = {
	-- client (measured per frame in robloxemu/check_scraplinetycoon_yard.luau)
	MaxLocalParts = 200,
	MaxEmitters = 4,
	MaxEmitterRate = 60,
	MaxWeatherEmitters = 2,
	MaxBeams = 8,
	MaxTrails = 8,
	MaxLights = 3,
	MaxHazards = 1,
	BeltItemsOwn = 33, -- 2.5 items/s x 13.2 s on the belt [R]
	BeltItemsOther = 8, -- per other line in view
	-- server (measured in robloxemu/check_scraplinetycoon.luau)
	MaxServerParts = 640, -- 40 static + 12 machines x 5 per plot, x 6, + market + baseplate <= 621 [R]
	MaxServerLights = 12, -- one on each chute, one on each plot's next-station console
	MachineParts = 5,
}

--============================================================================ the pacing model's player profiles
-- tests/LineModel.luau and tests/Pacing.spec.luau read these. NOT used by the game. ALL ASSUMPTIONS [A]:
-- replace `normal` with telemetry after the first real sessions and re-run Pacing.spec.
-- shop: opens the panel every N s; buy: s per purchase; notice: s to notice a sputter; eff: walk efficiency;
-- policy: star | cheapest | random | saver | mixed; fixes: walks to sputters; speed: walk speed override.
Config.Pacing = {
	BragMinutes = { 30, 45 }, -- the owner's window for a normal player
	Dt = 0.5,
	WorkSpot = { x = 0, z = -2 }, -- where an active player stands between jobs: the middle of the U
	Profiles = {
		fast = { shop = 10, buy = 0.8, notice = 2, eff = 0.95, policy = "star", fixes = true },
		normal = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "star", fixes = true },
		slow = { shop = 45, buy = 2.0, notice = 10, eff = 0.70, policy = "star", fixes = true },
		mixed = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "mixed", fixes = true },
		cheapest = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "cheapest", fixes = true },
		random = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "random", fixes = true },
		-- REVIEW-2 R3: taps whatever the panel paints gold or green (Economy.worth), not only the ★; and every 60 s
		green = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "green", fixes = true },
		green60 = { shop = 60, buy = 1.2, notice = 4, eff = 0.85, policy = "green", fixes = true },
		-- the reviewer's: taps any affordable button, whatever its colour
		anyaffordable = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "anyaffordable", fixes = true },
		saver = { shop = 20, buy = 1.2, notice = 4, eff = 0.85, policy = "saver", fixes = true },
		-- the script bound: zero reaction, buys the instant it can, walks at the trusted-speed cap
		bot = { shop = 0.5, buy = 0, notice = 0, eff = 1.0, policy = "star", fixes = true, speed = 21.6 },
		-- an auto-buy + auto-recycle macro that never fixes a jam
		afkmacro = { shop = 0.5, buy = 0, notice = 0, eff = 1.0, policy = "star", fixes = false },
		-- an anti-AFK jiggle and nothing else: never buys, never fixes
		jiggle = { shop = 1e9, buy = 0, notice = 0, eff = 1.0, policy = "star", fixes = false },
	},
}

return Config
