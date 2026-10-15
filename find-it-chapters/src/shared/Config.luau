--!strict
-- Find It! Chapters: every tunable in one place (docs/new-game-checklist.md §1).
-- Numbers carry their source: [DESIGN §n] is DESIGN.md, [M] a measurement in tests/ (Pacing.spec re-derives
-- every clock from tests/FinderModel.luau on the REAL Dressing layout), [C] a design choice, [S file] a sibling.

local Config = {}

--============================================================================ the traits [DESIGN §3.1]
Config.Traits = {
	Kinds = { "box", "basket", "jar", "vase", "pot", "cushion", "bag", "chest" },
	Colours = { "white", "yellow", "blue", "green" }, -- never red (the hazard ring) and never gold (found / hinted)
	Heights = { "floor", "table", "high" },
	Words = {
		box = "BOX", basket = "BASKET", jar = "JAR", vase = "VASE", pot = "POT", cushion = "CUSHION", bag = "BAG", chest = "CHEST",
		white = "WHITE", yellow = "YELLOW", blue = "BLUE", green = "GREEN",
		floor = "FLOOR", table = "TABLE", high = "HIGH",
	},
	-- the prop body colours (RGB 0-255). Bands.validate keeps them apart under every band's light and away
	-- from the two reserved colours below.
	RGB = {
		white = { 238, 236, 228 },
		yellow = { 250, 228, 80 },
		blue = { 52, 112, 232 },
		green = { 52, 176, 84 },
	},
}

-- clue forms: which traits a clue names [DESIGN §3.2]
Config.Forms = {
	K = { "kind" },
	CK = { "colour", "kind" },
	CH = { "colour", "height" },
	KH = { "kind", "height" },
}

-- Reserved colours [DESIGN §7]: nothing but a hazard ring is red, nothing but a found or hinted thing is gold.
Config.Reserved = {
	Ring = { 255, 40, 40 },
	Gold = { 255, 168, 0 },
	MinDistance = 90, -- RGB distance every other colour keeps from both
	ClueMinDistance = 70, -- pairwise RGB distance of the four clue colours under every band's light
}

--============================================================================ Book One [DESIGN §4]
-- n items, k candidates per clue, S props, rho = share of fillers that are partial matches, forms with
-- weights, room interior W x D (studs), clock (s). The clocks are DERIVED by tests/Pacing.spec.luau from the
-- normal profile on the real layout (ch1-3 at p97, ch4-15 at p90, rounded up to 5 s; 4000 attempts each) and it
-- fails if they differ. The design model's clocks (DESIGN.md §4) assumed uniform points; the real room puts HIGH
-- props on wall shelves and TABLE props on tables, which moved 9 of the 15 by 5-10 s.
Config.Chapters = {
	{ n = 3, k = 3, S = 16, rho = 0.25, forms = { K = 2, CK = 1 }, W = 32, D = 24, clock = 70 },
	{ n = 4, k = 3, S = 20, rho = 0.25, forms = { K = 1, CK = 2 }, W = 32, D = 24, clock = 95 },
	{ n = 4, k = 4, S = 26, rho = 0.30, forms = { CK = 2, CH = 1 }, W = 40, D = 30, clock = 115 },
	{ n = 5, k = 4, S = 30, rho = 0.30, forms = { CK = 1, CH = 1 }, W = 40, D = 30, clock = 120 },
	{ n = 5, k = 4, S = 34, rho = 0.35, forms = { CK = 1, CH = 1, KH = 1 }, W = 44, D = 34, clock = 130 },
	{ n = 6, k = 4, S = 38, rho = 0.35, forms = { CK = 1, CH = 1, KH = 1 }, W = 44, D = 34, clock = 160 },
	{ n = 6, k = 4, S = 42, rho = 0.40, forms = { CK = 1, CH = 1, KH = 1 }, W = 44, D = 34, clock = 160 },
	{ n = 6, k = 5, S = 46, rho = 0.40, forms = { CK = 1, CH = 1, KH = 1 }, W = 44, D = 34, clock = 180 },
	{ n = 7, k = 5, S = 50, rho = 0.45, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 215 },
	{ n = 7, k = 5, S = 52, rho = 0.45, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 215 },
	{ n = 7, k = 5, S = 54, rho = 0.45, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 215 },
	{ n = 8, k = 5, S = 56, rho = 0.50, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 245 },
	{ n = 8, k = 5, S = 58, rho = 0.50, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 250 },
	{ n = 8, k = 5, S = 60, rho = 0.50, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 250 },
	{ n = 9, k = 5, S = 64, rho = 0.50, forms = { CK = 1, CH = 1, KH = 1 }, W = 48, D = 38, clock = 285 },
}
Config.BookChapters = 15

--============================================================================ the Daily Case [DESIGN §5]
Config.Daily = {
	n = 6, k = 4, S = 44, rho = 0.40, forms = { CK = 1, CH = 1, KH = 1 }, W = 44, D = 34, clock = 195,
	OpensAfter = 3, -- Book chapter 3 cleared
	FirstDay = 20733, -- dayIndex of Case #1 (2026-10-07 UTC); the theme rotates from here
	Titles = { { at = 7, name = "Detective" }, { at = 30, name = "Inspector" }, { at = 100, name = "Master Finder" } },
}

--============================================================================ searching [DESIGN §3.4-3.7]
Config.Search = {
	Seconds = 1.0, -- the rummage; hit and miss are answered after exactly this long
	Reach = 10, -- horizontal studs, root to prop, client side
	ReachSlack = 2, -- the server allows this much more (a walking root reaches it ~0.1 s late)
	LooksSlack = 2, -- looks = n * k + LooksSlack
	SwiftFraction = 2 / 3,
	SharpSlips = 1,
	HintsPerAttempt = 1,
}

Config.Cards = {
	IntroFirst = 3.0,
	IntroRetry = 1.5,
	Clear = 4.0,
	Move = 1.0,
}

Config.Pause = {
	ResumeMinSeconds = 3, -- a Resume lands no sooner than this after the Pause [DESIGN §9]
	-- REVIEW-1 A4: a Resume re-deals the unfound part of the room. The next Pause needs this much attempt CLOCK
	-- after a re-dress, so a re-roll costs at least 30 s of the clock (the first pause of an attempt is free).
	EverySeconds = 30,
	-- REVIEW-1 round 2 C2: the break is capped. After 600 s of break in total (the server's frame clock) the room
	-- closes, earning nothing: an unbounded Pause carried a Daily's start-day credit across midnight. A longer break
	-- belongs in the hub, where nothing runs a clock. [C]
	MaxBreakSeconds = 600,
}

-- remote rate limits (seconds between accepted calls of one kind, per player)
Config.Limits = {
	Open = 1.0,
	Book = 0.5, -- the lectern prompt opening the Case Book menu (its own bucket: REVIEW-1 B1)
	Card = 1.0, -- Next / Retry
	Hub = 1.0, -- its own bucket (REVIEW-1 round 2 D4: sharing Next's, a Hub tap after a refused Next was swallowed)
	Hint = 0.5,
	Pause = 0.5,
	Resume = 0.25,
	Hello = 2.0,
	-- refusals are answered from a per-player bucket (REVIEW-1 A6): a burst of 4, refilled 4 a second
	RefusalBurst = 4,
	RefusalsPerSecond = 4,
}

--============================================================================ the room geometry [DESIGN §6]
Config.Room = {
	ShellW = 50, -- interior of the server-built lane shell
	ShellD = 40,
	Height = 16, -- the ceiling; the indoor hazard geometry [S escape-room-lab]
	Wall = 1,
	Margin = 2, -- floor props keep this far from a wall
	Spacing = 3, -- floor props keep this far apart (centres)
	DoorClear = 6, -- nothing within this of the door mat's centre
	CornerClear = 3.6, -- the four floor corners belong to decor (RoomArt.DECOR_CORNER): no prop or table enters them
	TableSize = { 6, 3 }, -- footprint (x, z)
	TableTop = 3, -- the TABLE height band
	TableSlots = { -2, 0, 2 },
	TableClear = 1.5, -- floor props keep this far from a table's edge
	TableGapX = 9, -- table centres keep at least this apart in x, or TableGapZ in z
	TableGapZ = 6,
	ShelfY = 8, -- the HIGH band: a wall shelf's top, above head height
	ShelfLength = 8,
	ShelfPitch = 10,
	ShelfSlots = { -3, -1, 1, 3 },
	ShelfOff = 0.75, -- a shelf slot sits this far from its wall
	ShelfDoorClear = 10, -- no south-wall shelf within this of the door (x)
	MatDepth = 3, -- the door mat
	Attempts = 200, -- generator restarts before it gives up (measured: never more than a few, Dressing.spec)
}

--============================================================================ the world [DESIGN §6]
Config.World = {
	MaxPlayers = 12,
	WalkSpeed = 16,
	JumpHeight = 7.2,
	HubSize = 64,
	HubWallHeight = 18, -- over the board's top (10) + JumpHeight (7.2) + 0.8: nobody jumps out of the hub (REVIEW-1 B9)
	HubSpawn = { 0, 0.5, 18 },
	Lectern = { 0, 0, 8 },
	DailyDoor = { 18, 0, 10 },
	Board = { -18, 0, 10 },
	LecternPromptDistance = 8,
	DailyPromptDistance = 8,
	BoardPromptDistance = 10,
	Lanes = 12,
	LaneX0 = -385,
	LaneDX = 70,
	LaneZ = -220,
	ArrivalGrace = 5, -- no hazard in the first 5 s of a room [DESIGN §8]
	LegalInset = 4, -- the hazard's legal spot: the room shrunk by 4, more than 4 from the door mat
	RespawnTime = 3,
}

--============================================================================ items [DESIGN §4]
Config.Items = {
	Shared = { "key", "duck", "teacup", "coin", "gem", "toycar", "button", "marble", "whistle", "thimble", "watch", "bell" },
	Band = {
		cottage = { "wool", "teddy", "cookie" },
		library = { "quill", "glasses", "bookmark" },
		greenhouse = { "seeds", "shell", "gnome" },
		ship = { "compass", "spyglass", "bottle" },
		observatory = { "starmap", "moonrock", "planet" },
	},
	Names = {
		key = "Key", duck = "Rubber Duck", teacup = "Teacup", coin = "Coin", gem = "Gem", toycar = "Toy Car",
		button = "Button", marble = "Marble", whistle = "Whistle", thimble = "Thimble", watch = "Pocket Watch",
		bell = "Little Bell", wool = "Ball of Wool", teddy = "Teddy", cookie = "Cookie", quill = "Quill",
		glasses = "Reading Glasses", bookmark = "Bookmark", seeds = "Seed Packet", shell = "Snail Shell",
		gnome = "Tiny Gnome", compass = "Compass", spyglass = "Spyglass", bottle = "Message in a Bottle",
		starmap = "Star Map", moonrock = "Moon Rock", planet = "Tiny Planet",
	},
}

--============================================================================ environment bands [DESIGN §7]
-- Trigger: the chapter you are in (progress = chapter; the Daily uses its theme's band's first chapter).
-- from = 0, 4, 7, 10, 13 with fade = 0: the light changes only on entering a room and on clearing a band's
-- last chapter, never during a search. `tint` is the light a prop colour is seen under (Bands.validate).
local function band(id, name, from, payload)
	payload.id = id
	payload.name = name
	payload.from = from
	payload.fade = 0
	return payload
end
Config.Env = {
	HalfLife = 0.8, -- EnvBands.approach [S same-door DESIGN §7]
	LightingHz = 10, -- Lighting is written at most 10 times a second [S plus1-jump]
	Hub = {
		lighting = { Ambient = { 120, 108, 92 }, OutdoorAmbient = { 150, 140, 125 }, Brightness = 2.4, ExposureCompensation = 0.1,
			ClockTime = 14.5, EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.3 },
		atmosphere = { Density = 0.22, Offset = 0.15, Color = { 235, 222, 200 }, Decay = { 190, 160, 120 }, Glare = 0.2, Haze = 1.0 },
		bloom = { Intensity = 0.7, Size = 24, Threshold = 0.95 },
		colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.1, TintColor = { 255, 246, 232 } },
		sky = { StarCount = 0 },
	},
	Bands = {
		band("cottage", "Sunny Cottage", 0, {
			lighting = { Ambient = { 150, 140, 120 }, OutdoorAmbient = { 175, 165, 145 }, Brightness = 2.8, ExposureCompensation = 0.12,
				ClockTime = 9, EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.3 },
			atmosphere = { Density = 0.25, Offset = 0.1, Color = { 240, 228, 205 }, Decay = { 210, 185, 150 }, Glare = 0.25, Haze = 1.0 },
			bloom = { Intensity = 0.8, Size = 24, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.12, TintColor = { 255, 249, 238 } },
			sky = { StarCount = 0 },
			tint = { 255, 249, 238 },
			palette = { wall = { 232, 218, 192 }, floor = { 150, 108, 72 }, trim = { 118, 86, 58 }, table = { 168, 120, 80 },
				shelf = { 140, 100, 66 }, wallMaterial = "SmoothPlastic", floorMaterial = "WoodPlanks" },
			lamp = { color = { 255, 232, 196 }, brightness = 1.4, range = 22 },
			decor = { "curtains", "rug", "herbs", "clock" },
			critters = { { kind = "cat", count = 1 }, { kind = "butterfly", count = 2 } },
			weather = { { kind = "motes", rate = 5 } },
			hazards = { "pinecone" },
		}),
		band("library", "Old Library", 4, {
			lighting = { Ambient = { 128, 100, 70 }, OutdoorAmbient = { 120, 96, 66 }, Brightness = 2.0, ExposureCompensation = 0.05,
				ClockTime = 16.5, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.25 },
			atmosphere = { Density = 0.3, Offset = 0.08, Color = { 215, 180, 130 }, Decay = { 140, 100, 60 }, Glare = 0.15, Haze = 1.5 },
			bloom = { Intensity = 0.9, Size = 26, Threshold = 0.92 },
			colorCorrection = { Brightness = 0.0, Contrast = 0.12, Saturation = 0.0, TintColor = { 255, 238, 210 } },
			sky = { StarCount = 0 },
			tint = { 255, 238, 210 },
			palette = { wall = { 128, 94, 64 }, floor = { 96, 66, 44 }, trim = { 70, 48, 30 }, table = { 110, 74, 46 },
				shelf = { 92, 62, 40 }, wallMaterial = "Wood", floorMaterial = "WoodPlanks" },
			lamp = { color = { 255, 206, 140 }, brightness = 1.3, range = 20 },
			decor = { "bookcase", "ladder", "globe", "books" },
			critters = { { kind = "moth", count = 3 } },
			weather = { { kind = "dust", rate = 6 } },
			hazards = { "book" },
		}),
		band("greenhouse", "Greenhouse", 7, {
			lighting = { Ambient = { 136, 150, 100 }, OutdoorAmbient = { 170, 170, 110 }, Brightness = 2.6, ExposureCompensation = 0.1,
				ClockTime = 17.6, EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 0.4 },
			atmosphere = { Density = 0.36, Offset = 0.18, Color = { 225, 225, 170 }, Decay = { 190, 150, 80 }, Glare = 0.4, Haze = 1.8 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.06, Saturation = 0.2, TintColor = { 248, 255, 226 } },
			sky = { StarCount = 0 },
			tint = { 248, 255, 226 },
			palette = { wall = { 190, 214, 196 }, floor = { 112, 116, 100 }, trim = { 76, 106, 72 }, table = { 128, 112, 90 },
				shelf = { 110, 96, 74 }, wallMaterial = "Glass", floorMaterial = "Slate" },
			lamp = { color = { 255, 236, 180 }, brightness = 1.2, range = 20 },
			decor = { "ferns", "vines", "cans", "pots" },
			critters = { { kind = "butterfly", count = 3 }, { kind = "frog", count = 1 } },
			weather = { { kind = "mist", rate = 5 }, { kind = "drizzle", rate = 8 } },
			hazards = { "flowerpot" },
		}),
		band("ship", "Ship's Cabin", 10, {
			lighting = { Ambient = { 70, 84, 120 }, OutdoorAmbient = { 60, 72, 110 }, Brightness = 1.6, ExposureCompensation = 0.1,
				ClockTime = 21.5, EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.5 },
			atmosphere = { Density = 0.32, Offset = 0.05, Color = { 120, 140, 180 }, Decay = { 60, 70, 110 }, Glare = 0.1, Haze = 1.4 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.12, Saturation = 0.05, TintColor = { 236, 240, 255 } },
			sky = { StarCount = 800 },
			tint = { 236, 240, 255 },
			palette = { wall = { 112, 82, 58 }, floor = { 84, 60, 42 }, trim = { 56, 40, 28 }, table = { 104, 74, 50 },
				shelf = { 88, 62, 42 }, wallMaterial = "WoodPlanks", floorMaterial = "WoodPlanks" },
			lamp = { color = { 255, 190, 110 }, brightness = 1.6, range = 20 },
			decor = { "ropes", "barrels", "hammock", "portholes" },
			critters = { { kind = "parrot", count = 1 }, { kind = "fish", count = 2 } }, -- the fish swim in the portholes
			weather = { { kind = "rain", rate = 30 } }, -- running down the portholes (RoomArt.weatherSpots)
			lightning = true, -- REVIEW-1 round 2 D2: the storm the store text promises, flashing in the portholes
			hazards = { "crate" },
		}),
		band("observatory", "Star Observatory", 13, {
			lighting = { Ambient = { 96, 84, 140 }, OutdoorAmbient = { 80, 70, 130 }, Brightness = 1.4, ExposureCompensation = 0.15,
				ClockTime = 0.5, EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.4 },
			atmosphere = { Density = 0.2, Offset = 0, Color = { 110, 96, 170 }, Decay = { 40, 30, 90 }, Glare = 0, Haze = 0.6 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.05, Contrast = 0.1, Saturation = 0.05, TintColor = { 226, 220, 255 } },
			sky = { StarCount = 3000 },
			tint = { 226, 220, 255 },
			palette = { wall = { 70, 66, 104 }, floor = { 80, 78, 100 }, trim = { 150, 140, 210 }, table = { 96, 90, 122 },
				shelf = { 86, 80, 112 }, wallMaterial = "Concrete", floorMaterial = "Marble" },
			lamp = { color = { 196, 200, 255 }, brightness = 1.2, range = 20 },
			decor = { "telescope", "charts", "orrery", "dome" },
			critters = { { kind = "starmote", count = 4 } },
			weather = { { kind = "twinkle", rate = 8 } },
			hazards = { "pebble" },
		}),
	},
}

--============================================================================ hazards [DESIGN §8]
-- Hazards.luau (plus1-jump's, verbatim) under escape-room-lab's reviewed INDOOR config: every kind comes from
-- pitch 85 and the glue passes ctx.pitch = rad(85), so a lane is a near-vertical drop from the ceiling.
-- commit = telegraph locks the lane on its first frame, so the ring never moves.
local function drop()
	return { speed = 4, telegraph = 3.0, commit = 3.0, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 }
end
Config.Hazards = {
	-- seconds of EXPOSED time (the client's hazard clock runs on a legal spot only). DESIGN §8 had 100-140 [M 4]; with
	-- the legal-spot rule in FinderModel that gave one near-miss per 3.13-3.17 min (REVIEW-1 round 2 D5). 85-120 gives
	-- 2.69 [M Pacing.spec].
	IntervalMin = 85,
	IntervalMax = 120,
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	AimJitter = 0.8,
	SpreadDegrees = 0,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	KnockLift = 0,
	KnockSeconds = 0.6,
	PitchDegrees = 85, -- what the glue passes as ctx.pitch
	RootHeight = 3, -- the root stands this far over the floor; the ring is drawn at the feet
	Kinds = { pinecone = drop(), book = drop(), flowerpot = drop(), crate = drop(), pebble = drop() },
	Names = { pinecone = "PINECONE", book = "BOOK", flowerpot = "FLOWERPOT", crate = "CRATE", pebble = "METEORITE PEBBLE" },
}

--============================================================================ rest: the Pause button [DESIGN §9]
Config.Rest = {
	IdleSeconds = 0, -- ADAPTATION: idle rest off. Standing still is how a room is read.
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 6, -- the longest drop (3.6 s) + 2.4 s to stand still
}

--============================================================================ budgets [DESIGN §18], capped in code
Config.Budget = {
	LocalParts = 280,
	HazardParts = 8, -- reserved inside LocalParts for the hazard model and its ring
	Lights = 4,
	Emitters = 4, -- 2 weather + the found burst + the hint glint
	WeatherEmitters = 2,
	MaxEmitterRate = 60,
	MinWeatherRate = 0.5,
	Critters = 6,
	DecorParts = 40,
	ItemsShown = 9, -- found items standing on the room's "found" shelf
	HubParts = 160,
	LaneParts = 9,
}

--============================================================================ the board [DESIGN §11]
Config.Board = {
	Store = "FindIt_Solved_v1",
	MaxMetric = 100000, -- Cases Solved; 1e5 * 2e9 + 2e9 = 2.0e14 < 2^53
	PublicRows = 10,
	FriendsRows = 10,
	PublicCacheSeconds = 60,
	FriendListCacheSeconds = 300,
	FriendScoreCacheSeconds = 120,
	FriendCap = 200,
	GetAsyncReserve = 20,
	FriendReadMaxWaitSeconds = 30,
	NameCacheSeconds = 3600,
	NameCacheMax = 500,
	Text = {
		Title = "CASES SOLVED",
		EmptyPublic = "No cases solved yet. Be the first: open the Case Book!",
		NoFriends = "None of your friends has solved a case yet. Invite one: every room is different, so nobody can tell them where things are.",
		FriendsFailed = "Couldn't load your friends right now. Try again in a minute.",
		FriendsChecking = "Checking your friends: %d of %d...",
		FriendsNoScores = "None of your %d friends has solved a case yet. Invite one: every room is different, so nobody can tell them where things are.",
		FriendsPartial = "Checked %d of %d friends (Roblox's request limit). Toggle again later for the rest.",
		Unavailable = "The board is resting. Back soon.",
		ShowFriends = "Show friends",
		ShowPublic = "Show public",
	},
}

--============================================================================ saving [DESIGN §12]
Config.Save = {
	Store = "FindIt_Players_v1",
	SessionLockSeconds = 45,
	AutosaveSeconds = 20,
	MinWriteGap = 6, -- writes to one key stay at least this far apart [S fork-tower REVIEW-4 §9.3]
	ReleaseTries = 3, -- the release on leave / shutdown retries a failed write this often (it carries queued clears)
	ReleaseRetrySeconds = 1,
	-- REVIEW-1 round 2 C3: a first load that finds the old server's lock still held (a server hop) or fails is retried
	-- after 3 s, up to 4 times, before the 20 s autosave tick takes over: a hopper is loaded seconds after the old
	-- server lets go, not up to 20 s later. [C]
	QuickRetrySeconds = 3,
	QuickRetries = 4,
	Text = {
		NoStore = "Saving is off in this server (Studio without API access). Play on: nothing here is saved.",
		-- REVIEW-1 round 2 C3: not "won't save": clears made meanwhile are merged when the load lands (round 1 A3)
		Locked = "Your progress is still open in another server - retrying. Play on: what you clear now is added when it loads.",
		LoadRetry = "Couldn't load your progress yet - retrying. Play on: what you clear now is added when it loads.",
		Loaded = "Your progress is loaded.",
		CantSave = "Kept on this server: your progress is still open in another server, so it is added when it loads.",
		-- REVIEW-1 A2/A3: a clear is queued until a write carrying it lands; the card says which wait it is in
		SaveLater = "Kept on this server: Roblox's storage didn't answer, so it is saved again in a moment.",
		LoadPending = "Kept on this server: it is added to your Case Book when your progress loads.",
		Saved = "Your case is saved.",
	},
}

--============================================================================ Studio staging [DESIGN §21.2]
-- Honoured ONLY when RunService:IsStudio() AND the profile cannot save (CLAUDE.md trap 13).
Config.Studio = {
	ShotSeed = nil :: number?, -- deterministic dressing and secret, so a shot can be framed twice
	Cleared = nil :: number?, -- chapters unlocked for staging later bands (the profile is never saved there)
}

--============================================================================ words [DESIGN §17.2]
Config.Text = {
	Intro = "Find %d things! Each one hides in something that fits its clue. Tap to look, tap again to search.",
	IntroRetry = "New room! Find %d things.",
	DecorTap = "Nothing to search there",
	WalkCloser = "Walk closer: you can search things within 10 studs",
	GetReady = "Get ready...",
	OneAtATime = "One search at a time",
	OnBreak = "You're on a break: move or tap Resume",
	TimeUp = "Time's up",
	NoLooks = "No looks left",
	OutOfLooks = "Out of looks! Read the clues and try again",
	Already = "Already searched",
	NoFit = "That %s doesn't fit any clue you still need",
	HintUsed = "You've used this chapter's hint",
	HintPick = "Tap a thing on your list first",
	HintFound = "That one is already found",
	Locked = "Clear Chapter %d first",
	DailyLocked = "The Daily Case opens after Chapter 3",
	DailyDone = "You solved today's case! The next one opens at 00:00 UTC.",
	PausingAfterDrop = "Pausing after the drop...",
	Paused = "Paused. The clock is stopped. While you rest, things get moved around.",
	Resuming = "Resuming in a moment...",
	PauseSoon = "You can pause again in %d s",
	Busy = "One moment...",
	FinishFirst = "Finish or leave this room first",
	NotInRoom = "You're not in a room",
	BookSolved = "BOOK ONE SOLVED",
	BookSolvedSub = "You found all %d things",
	BookSolvedNotice = "%s solved Book One!",
	Hint = "Walk to the Case Book and press E (tap Open)",
	-- REVIEW-1 round 2 (C2, C3, D1, D4, D6)
	PausedLeft = "Paused. The clock is stopped. While you rest, things get moved around. This room stays open %s more.",
	BreakOver = "BREAK OVER",
	BreakOverSub = "The room closed after a %d-minute break. Retry builds a new one.",
	BreakClosed = "This room closed during your break",
	LeaveConfirm = "Tap Leave again to go to the hub (this room's finds are not kept)",
	NextAfterSave = "Saving your case... the next chapter opens in a moment",
	GoldBook = "GOLD BOOK! Every chapter at three stars.",
	GoldBookToo = "and the GOLD BOOK!",
	LoadingBook = "  Loading your Case Book...",
	StillLoading = "Your Case Book is still loading: your chapters appear in a moment",
	MenuTitle = "THE CASE BOOK  \u{2605} %d/%d",
	MenuTitleGold = "THE GOLD BOOK  \u{2605} %d/%d",
}

return Config
