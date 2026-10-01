-- Config.luau — EVERY tunable of Escape Room Lab in one block. Pure data; no Roblox.
-- Each number carries its source in DESIGN.md (section in brackets). Colours are {r, g, b} so the
-- band blends (EnvBands) run in the luau CLI; the glue turns them into Color3.

local Config = {}

local D10 = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
local D6 = { 1, 2, 3, 4, 5, 6 }

--============================================================================ the world [§5, §6.1]
Config.World = {
	WalkSpeed = 16,           -- read off a live Humanoid in Studio (fork-tower STUDIO.md §5)
	MaxPlayers = 8,
	MinZones = 8,             -- Zones = max(MinZones, Players.MaxPlayers): a floor, never a cap
	ZoneSpacing = 300,        -- zone i sits at (300 * i, 0, 0)
	RoomHalf = 16,            -- room interior x, z in -16..16
	RoomHeight = 16,          -- floor top y 0, ceiling y 16
	Wall = 1,
	DoorwayWidth = 6,
	DoorwayHeight = 8,
	CabHalf = 4,              -- lift cabs are 8 x 8 inside
	CabHeight = 10,
	CorridorLength = 3,       -- exit door -> exit cab
	AtriumHalfX = 32,
	AtriumHalfZ = 24,
	AtriumHeight = 20,
	Spawn = { 0, 0.5, 14 },   -- AtriumSpawn centre; 6 x 1 x 6, top face y 1
	SpawnSize = { 6, 1, 6 },
	SoloCab = { -7, -3 },     -- cab centre (x, z); doorway on +Z
	PairCab = { 8, -3 },      -- 12 x 8, two pads
	PairPadDX = 3,            -- pads at cab x -/+ 3
	PairCabHalfX = 6,         -- the Pair Lift's inside is 12 x 8 (walls at cab x -/+ 6.5, 1 thick)
	Board = { 16, 6, 12 },    -- the Star Board's centre; faces the spawn (-X)
	BoardSize = { 10, 7 },
	RoofDoor = { 0, -24 },    -- north wall of the Atrium
	Arrival = { 0, 6 },       -- AtriumArrival: where ATRIUM and "Back down" put you
	RoofY = 150,              -- the Roof deck's top face, 48 x 48 over the origin
	RoofHalf = 24,
	RespawnTime = 3,
	LightRange = 26,          -- ceiling fixtures at (0, 15, +-8)
	MaxRoomParts = 160,       -- server parts per room, asserted headless
	-- stations: the prompt's position, room-local
	Stations = {
		A = { -15.5, 6.5, 0 },
		B = { 15.5, 6.5, 0 },
		Door = { 0, 4, -15.5 },
	},
	DoorBoard = { -10, 8, -15.5 },  -- 12 x 7, left of the doorway
	Keypad = { 7, 5, -15.5 },
}

--============================================================================ lifts [§6.2]
Config.Lift = {
	BoardSeconds = 1.0,          -- standing in the Solo Lift this long starts the ride
	RideSeconds = 2.5,           -- doors shut; the server generates and builds meanwhile
	PairGoWindowSeconds = 10,    -- both GO presses within this window
	PairCountdownSeconds = 3,    -- time to step off after a mistaken GO
	ArrivalGraceSeconds = 8,     -- no hazard in a room's first 8 s
	PollSeconds = 0.25,          -- how often the server looks at who stands in which cab
	-- several players in the Solo Lift each ride to a room of their own (review 2026-10-01: "One at a
	-- time" let one player hold everyone else in the Atrium)
	SoloTogetherText = "Solo Lift: each of you gets a room of your own. Take the PAIR LIFT to play together.",
	-- a lift takes only who is still inside it when it leaves (review-1 A2, B2)
	SteppedOutText = "You stepped out of the lift before it left. Step back in to ride.",
	-- the Pair Lift takes one player per pad; anyone idle on a pad is ignored (review-1 A1)
	OtherPadText = "One player per pad: step onto the other pad and press GO.",
}

--============================================================================ the Lab [§4.1, the V4 table]
local function lamp(n, k) return { kind = "lamp", n = n, k = k } end
local function shelf(N) return { kind = "shelf", N = N } end
Config.Lab = {
	Wings = {
		{ id = "reception", name = "Reception", door = { L = 3, alphabet = D6 },
			rooms = { { lamp(3, 2) }, { shelf(3) }, { lamp(3, 3) } } },
		{ id = "archive", name = "Archive", door = { L = 3, alphabet = D10 },
			rooms = { { shelf(4) }, { lamp(3, 4) }, { shelf(4) } } },
		{ id = "greenhouse", name = "Greenhouse", door = { L = 3, alphabet = D10 },
			rooms = { { lamp(3, 4), shelf(4) }, { shelf(4), lamp(4, 3) }, { lamp(4, 4), shelf(4) } } },
		{ id = "coldstore", name = "Cold Storage", door = { L = 3, alphabet = D10 },
			rooms = { { shelf(4), lamp(4, 4) }, { lamp(4, 4), shelf(4) }, { shelf(4), lamp(4, 5) } } },
		{ id = "reactor", name = "Reactor", door = { L = 4, alphabet = D10 },
			rooms = { { lamp(4, 5), shelf(5) }, { shelf(5), lamp(4, 5) }, { lamp(4, 5), shelf(5) } } },
	},
}

--============================================================================ puzzles [§3.4, §6.3]
Config.Puzzles = {
	MaxDoorLines = 6,        -- the in-world board has six rows
	FirstRoomMaxLines = 3,   -- room 1: a door a new player takes in at a glance
	MaxShelfClues = 7,       -- the overlay's list stays one short scroll
	MaxGenerations = 50,
}

--============================================================================ stars, hints, actions [§4.3, §6.4]
Config.Stars = {
	PerRoom = 3,
	Max = 45,
	Lockout = { 3, 6, 12, 20 },  -- seconds per consecutive wrong try on a station
}
Config.Hints = {
	CooldownSeconds = 20,
}
Config.Act = {
	RatePerSecond = 10,
	Burst = 10,
	RateToastSeconds = 5,
	PromptDistance = 8,      -- station prompts are 21.9+ studs apart: one shows at a time
	StationReach = 12,       -- prompt reach + a stride of latency, checked on the server's view
	MaxIdLength = 16,
	-- the ATRIUM buttons in a room's cabs: on arrival the entry cab's is the only prompt in reach, and a
	-- stray tap must not throw a room away (review 2026-10-01). Every other prompt stays a plain tap.
	LeaveHoldSeconds = 0.5,
}

--============================================================================ save [§6.5, §12.1]
Config.Save = {
	Store = "EscapeRoomLab_v1",
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
	CoalesceSeconds = 6,     -- one write per key per 6 s
	Text = {
		-- a load call that failed (a throttle, a 5xx): retried on every autosave tick, and what is
		-- earned meanwhile is merged in (review 2026-10-01: one failed call used to cost the session)
		LoadRetry = "Couldn't load your stars yet. Play on: we keep trying, and what you earn now is kept.",
		Loaded = "Your stars are loaded. Saving is on.",
		NoStore = "Progress will not save this session.",
	},
}

--============================================================================ the Star Board [§11]
Config.Board = {
	Store = "EscapeRoomLab_Stars_v1",
	MaxMetric = 45,
	PublicRows = 10,
	PublicCacheSeconds = 60,
	FriendCap = 200,
	FriendsRows = 10,
	FriendScoreCacheSeconds = 300,
	FriendListCacheSeconds = 600,
	GetAsyncReserve = 10,
	FriendReadMaxWaitSeconds = 30, -- one read waits at most this long for budget, then the view stops there
	FriendsFailSeconds = 10,       -- a failed friend-list call is not retried sooner than this
	NameCacheSeconds = 3600,
	PromptDistance = 10,
	Text = {
		EmptyPublic = "No stars on the board yet. Escape a room to be first!",
		NoFriends = "Add friends on Roblox to compare stars here. Met someone in the Pair Lift? Add them!",
		FriendsFailed = "Couldn't load your friends list. Try again in a minute.",
		FriendsChecking = "Loading friends %d/%d",
		FriendsPartial = "Checked %d of %d friends (Roblox's request limit). The rest next time.",
		FriendsNoScores = "None of your %d friends has a star yet. Ride the Pair Lift with one!",
		Unavailable = "Board unavailable",
	},
}

--============================================================================ environment bands [§7]
-- Progress p = (wing - 1) + (room - 1 + solved / stations) / 3: 0 in the Atrium, 5 on the Roof. Every band
-- after the first fades in over the last third before its `from`, which is exactly the last room of the
-- wing before: the next wing seeps into the last room, and is fully there when its door opens.
Config.Env = {
	HalfLife = 0.6,
	LightingHz = 10,
	Bands = {
		{
			id = "reception", name = "Reception", from = 0, fade = 0,
			lighting = { Ambient = { 150, 132, 112 }, OutdoorAmbient = { 170, 150, 120 }, Brightness = 2.2,
				ExposureCompensation = 0.1, ClockTime = 16.8, EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.3 },
			atmosphere = { Density = 0.25, Offset = 0.1, Color = { 230, 205, 165 }, Decay = { 170, 130, 90 }, Glare = 0.2, Haze = 1.0 },
			bloom = { Intensity = 0.6, Size = 24, Threshold = 1.0 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.1, TintColor = { 255, 240, 220 } },
			sky = { StarCount = 0 },
			palette = { wall = { 236, 226, 204 }, floor = { 40, 120, 120 }, trim = { 150, 110, 70 },
				wallMaterial = "SmoothPlastic", floorMaterial = "Fabric" },
			light = { color = { 255, 222, 170 }, brightness = 1.6 },
			props = { "desk", "fern", "cooler", "fern2" },
			critters = { { kind = "fly", count = 2 } },
			weather = { { kind = "dust", rate = 4 } },
			hazards = {},
		},
		{
			id = "archive", name = "Archive", from = 1, fade = 1 / 3,
			lighting = { Ambient = { 112, 86, 56 }, OutdoorAmbient = { 90, 70, 45 }, Brightness = 1.4,
				ExposureCompensation = -0.15, ClockTime = 18.5, EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.2 },
			atmosphere = { Density = 0.35, Offset = 0.05, Color = { 190, 150, 100 }, Decay = { 110, 80, 50 }, Glare = 0.1, Haze = 1.6 },
			bloom = { Intensity = 0.8, Size = 26, Threshold = 0.95 },
			colorCorrection = { Brightness = -0.01, Contrast = 0.15, Saturation = -0.15, TintColor = { 255, 226, 182 } },
			sky = { StarCount = 0 },
			palette = { wall = { 122, 92, 62 }, floor = { 92, 62, 40 }, trim = { 60, 40, 25 },
				wallMaterial = "Wood", floorMaterial = "WoodPlanks" },
			light = { color = { 255, 190, 110 }, brightness = 1.2 },
			props = { "shelves", "ladder", "boxes", "bankerlamp" },
			critters = { { kind = "moth", count = 4 } },
			weather = { { kind = "dust", rate = 3 }, { kind = "paper", rate = 3 } },
			hazards = { "spider" },
		},
		{
			id = "greenhouse", name = "Greenhouse", from = 2, fade = 1 / 3,
			lighting = { Ambient = { 120, 162, 112 }, OutdoorAmbient = { 150, 190, 140 }, Brightness = 3,
				ExposureCompensation = 0.2, ClockTime = 12, EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 0.5 },
			atmosphere = { Density = 0.4, Offset = 0.2, Color = { 200, 235, 200 }, Decay = { 120, 170, 120 }, Glare = 0.4, Haze = 2.0 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.06, Saturation = 0.25, TintColor = { 222, 255, 222 } },
			sky = { StarCount = 0 },
			palette = { wall = { 182, 216, 184 }, floor = { 104, 112, 96 }, trim = { 70, 110, 70 },
				wallMaterial = "SmoothPlastic", floorMaterial = "Slate" },
			light = { color = { 230, 255, 222 }, brightness = 2.0 },
			props = { "palm", "planter", "planter2", "mistpipe" },
			critters = { { kind = "butterfly", count = 5 } },
			weather = { { kind = "mist", rate = 6 }, { kind = "drip", rate = 2 } },
			hazards = { "seedpod" },
		},
		{
			id = "coldstore", name = "Cold Storage", from = 3, fade = 1 / 3,
			lighting = { Ambient = { 150, 176, 212 }, OutdoorAmbient = { 170, 195, 230 }, Brightness = 2.4,
				ExposureCompensation = 0, ClockTime = 10, EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.7 },
			atmosphere = { Density = 0.3, Offset = 0.1, Color = { 215, 230, 250 }, Decay = { 150, 175, 210 }, Glare = 0.3, Haze = 1.2 },
			bloom = { Intensity = 0.9, Size = 24, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.25, Saturation = -0.35, TintColor = { 210, 230, 255 } },
			sky = { StarCount = 0 },
			palette = { wall = { 216, 230, 240 }, floor = { 170, 185, 200 }, trim = { 120, 140, 160 },
				wallMaterial = "Ice", floorMaterial = "DiamondPlate" },
			light = { color = { 200, 226, 255 }, brightness = 1.8 },
			props = { "rack", "crates", "rack2", "crates2" },
			critters = { { kind = "drone", count = 3 } },
			weather = { { kind = "snow", rate = 20 } },
			hazards = { "icedrone" },
		},
		{
			id = "reactor", name = "Reactor", from = 4, fade = 1 / 3,
			lighting = { Ambient = { 40, 62, 82 }, OutdoorAmbient = { 30, 40, 60 }, Brightness = 1.2,
				ExposureCompensation = -0.2, ClockTime = 22, EnvironmentDiffuseScale = 0.3, EnvironmentSpecularScale = 0.8 },
			atmosphere = { Density = 0.45, Offset = 0.05, Color = { 70, 110, 130 }, Decay = { 60, 30, 90 }, Glare = 0.2, Haze = 1.8 },
			bloom = { Intensity = 1.6, Size = 36, Threshold = 0.7 },
			colorCorrection = { Brightness = -0.02, Contrast = 0.3, Saturation = 0.2, TintColor = { 200, 236, 255 } },
			sky = { StarCount = 0 },
			palette = { wall = { 40, 46, 62 }, floor = { 30, 34, 44 }, trim = { 90, 60, 150 },
				wallMaterial = "Metal", floorMaterial = "DiamondPlate" },
			light = { color = { 80, 255, 232 }, brightness = 1.4 },
			props = { "core", "pipes", "stripes", "pipes2" },
			critters = { { kind = "sparkbug", count = 4 } },
			weather = { { kind = "steam", rate = 6 }, { kind = "sparks", rate = 4 } },
			hazards = { "claw" },
		},
		{
			id = "roof", name = "Roof", from = 5, fade = 1 / 3,
			lighting = { Ambient = { 60, 70, 112 }, OutdoorAmbient = { 70, 82, 130 }, Brightness = 1.5,
				ExposureCompensation = 0, ClockTime = 0.5, EnvironmentDiffuseScale = 0.3, EnvironmentSpecularScale = 0.3 },
			atmosphere = { Density = 0.15, Offset = 0, Color = { 60, 70, 120 }, Decay = { 20, 25, 60 }, Glare = 0, Haze = 0.5 },
			bloom = { Intensity = 1.0, Size = 28, Threshold = 0.85 },
			colorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = 0.05, TintColor = { 200, 210, 255 } },
			sky = { StarCount = 3000 },
			palette = { wall = { 70, 76, 96 }, floor = { 88, 94, 110 }, trim = { 200, 210, 255 },
				wallMaterial = "Concrete", floorMaterial = "Slate" },
			light = { color = { 200, 212, 255 }, brightness = 1.0 },
			props = {},
			critters = { { kind = "bat", count = 3 } },
			weather = { { kind = "leaves", rate = 4 } },
			hazards = {},
		},
	},
}

--============================================================================ hazards [§8]
-- The +1 Jump template (Hazards.luau, verbatim). The adaptation lives HERE and in the glue: every kind
-- comes from pitch 85 (the template's MAX_ELEVATION) and the glue passes ctx.pitch = rad(85), so the
-- template plans a near-vertical lane from the ceiling straight down onto the player.
Config.Hazards = {
	-- 80-120 s of EXPOSED time (review-1 B4): the clock now runs only on a legal spot past the arrival grace,
	-- so the door station, where a room's longest think happens, no longer counts. At the template's 120-180
	-- that left 6-7 hazards per run to the Roof (rev3_path x4, median gaps 241-302 s); at 80-120 it is 9-11
	-- (x8), median gaps 170-206 s: about the standard's one per 2-3 minutes of play, as the reviewed build had.
	IntervalMin = 80,
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
	PitchDegrees = 85,          -- what the glue passes as ctx.pitch (CLAUDE.md trap 4)
	RootHeight = 3,             -- the root stands this far over the floor; the ring is drawn there
	-- commit = telegraph (review-1 B1): the lane LOCKS on its first frame, so the ring stands where the player
	-- stood when it appeared and never moves. With the template's commit 1.5 the ring followed the player for
	-- 1.5 s, and a 4 studs/s drop touches the 3.5-stud zone 0.875 s before arrival (at 2.13 s): stepping out
	-- dodged only 1.45-2.05 s after the ring showed. Now it dodges from the first frame until the hit at 2.13 s.
	-- The template's tracking suits +1 Jump's 14-120 studs/s lanes; a ceiling drop in a 16-stud room cannot
	-- be fast (speed x telegraph = 12 studs puts the start under the ceiling), so here it only cost the dodge.
	Kinds = {
		spider = { speed = 4, telegraph = 3.0, commit = 3.0, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		seedpod = { speed = 4, telegraph = 3.0, commit = 3.0, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		icedrone = { speed = 4, telegraph = 3.0, commit = 3.0, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		claw = { speed = 4, telegraph = 3.0, commit = 3.0, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
	},
	Names = { spider = "SPIDER", seedpod = "SEED POD", icedrone = "ICE DRONE", claw = "CRANE CLAW" },
}

--============================================================================ rest: the Break button [§9]
Config.Rest = {
	IdleSeconds = 0,          -- ADAPTATION: idle rest off. Standing still is how a puzzle is thought through.
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 6,       -- the longest flight (3.6 s) + 2.4 s to stand still
}

--============================================================================ budgets [§7.2], capped in code
Config.Budget = {
	LocalParts = 120,
	Emitters = 3,             -- 2 weather + 1 hazard
	WeatherEmitters = 2,
	MaxEmitterRate = 60,      -- particles per second over the weather emitters together
	MinWeatherRate = 0.5,
	Beams = 4,
	Trails = 2,
	LocalLights = 2,
	DecorPerBand = 30,
	HazardParts = 8,          -- the hazard model (up to 6) + the ring + its thread
}

--============================================================================ Studio staging [§19.2]
-- Honoured ONLY when RunService:IsStudio() AND the profile cannot save (CLAUDE.md trap 7).
Config.Studio = {
	StartSlot = nil,
}

return Config
