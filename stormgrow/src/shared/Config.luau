--!strict
-- STORMGROW: MUTATION FARM — every tunable in one place (DESIGN.md §2-§5 give the reason for each).
--
-- Pure modules never read this file globally: the server and the clients pass the parts they need, so
-- every rule runs in the luau CLI. Colours are {r, g, b} (0-255), never Color3, for the same reason.
-- Nothing in here is secret. Config replicates, and the schedule and the odds are public by design.

local Config = {}

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

-- ── The weather clock (DESIGN.md §2.1) ─────────────────────────────────────────────────────────────
-- Aligned to Unix seconds, so every server has the same weather at the same second.
-- An event of kind k runs while (t - from) % every lies in [0, len).
Config.Weather = {
	Events = {
		storm = { from = 0, len = 90, every = 600 }, -- :00, :10, :20 ... for 90 s
		rainbow = { from = 90, len = 60, every = 1800 }, -- right after the :00 and :30 storms, 60 s
		frost = { from = 300, len = 90, every = 600 }, -- :05, :15, :25 ... for 90 s
	},
	Kinds = { "storm", "rainbow", "frost" },
	TickSeconds = 5, -- one strike wave every 5 s of an event
	-- chance that a crop ripe for the WHOLE event takes the event's mark (Weather.perTick spreads it
	-- over the event's ticks, so a crop that ripens halfway gets a fair share)
	Chance = { storm = 0.5, frost = 0.5, rainbow = 0.35 },
	FadeSeconds = 4, -- the overlay fades in and out over 4 s inside the window
	CueSeconds = 60, -- the HUD's "keep ripe crops in the ground" cue starts 60 s before an event
	-- A knob for the night shift's SHOTS place only (DESIGN.md §14.2). EnvConfig.spec asserts it is 0 here.
	ClockOffsetSeconds = 0,
	Names = { storm = "Storm", frost = "Frost", rainbow = "Rainbow" },
	Emoji = { storm = "⛈️", frost = "❄️", rainbow = "🌈" },
}

-- ── Marks (DESIGN.md §2.2) ────────────────────────────────────────────────────────────────────────
-- Stored as bits on a crop: 1 = Charged, 2 = Frosted, 4 = Prismatic. Values multiply.
Config.Marks = {
	storm = { bit = 1, mult = 5, name = "Charged", emoji = "⚡" },
	frost = { bit = 2, mult = 5, name = "Frosted", emoji = "❄️" },
	rainbow = { bit = 4, mult = 8, name = "Prismatic", emoji = "🌈" },
}
-- The name of each combination (the value is always the product of its marks).
Config.Variants = {
	[1] = "Charged", [2] = "Frosted", [4] = "Prismatic",
	[3] = "Stormglass", [5] = "Radiant", [6] = "Aurora", [7] = "Tempest",
}

-- ── Crops, in unlock order (DESIGN.md §2.3) ───────────────────────────────────────────────────────
-- unlock: coins to unlock (strictly in order). seed: coins per planting. sell: coins per plain harvest.
-- grow: seconds from planting to ripe. needHarvested: lifetime harvest the unlock also needs.
Config.Crops = {
	{ id = "radish", name = "Radish", emoji = "🍠", unlock = 0, seed = 0, sell = 5, grow = 30, color = rgb(214, 66, 96), leaf = rgb(88, 170, 70), shape = "root" },
	{ id = "carrot", name = "Carrot", emoji = "🥕", unlock = 50, seed = 5, sell = 20, grow = 60, color = rgb(240, 130, 40), leaf = rgb(80, 175, 70), shape = "root" },
	{ id = "corn", name = "Corn", emoji = "🌽", unlock = 250, seed = 20, sell = 80, grow = 120, color = rgb(245, 205, 70), leaf = rgb(95, 160, 60), shape = "stalk" },
	{ id = "tomato", name = "Tomato", emoji = "🍅", unlock = 1000, seed = 60, sell = 280, grow = 180, color = rgb(215, 45, 40), leaf = rgb(70, 150, 60), shape = "bush" },
	{ id = "sunflower", name = "Sunflower", emoji = "🌻", unlock = 3500, seed = 150, sell = 750, grow = 240, color = rgb(250, 200, 40), leaf = rgb(85, 150, 55), shape = "flower" },
	{ id = "pumpkin", name = "Pumpkin", emoji = "🎃", unlock = 10000, seed = 400, sell = 2400, grow = 360, color = rgb(235, 120, 30), leaf = rgb(70, 140, 50), shape = "gourd" },
	{ id = "watermelon", name = "Watermelon", emoji = "🍉", unlock = 35000, seed = 1000, sell = 6500, grow = 480, color = rgb(60, 150, 70), leaf = rgb(70, 140, 50), shape = "melon" },
	{ id = "stormfruit", name = "Stormfruit", emoji = "🔮", unlock = 120000, seed = 2500, sell = 20000, grow = 720, color = rgb(120, 90, 235), leaf = rgb(60, 80, 150), shape = "orb" },
}
-- Stormfruit is only sold in the Eye of the Storm: set below from the band table, one number in one place.

-- ── Farms, fields, the valley (DESIGN.md §2.4) ────────────────────────────────────────────────────
-- A farm's local frame: z runs OUTWARD from the market (z = 0 is its inner edge, InnerRadius from the
-- origin), x runs sideways. Farm k sits at yaw (k - 1) * 60 degrees.
Config.Farm = {
	Slots = 6,
	InnerRadius = 100,
	Width = 84, -- x from -42 to 42
	Depth = 64, -- z from 0 to 64: porch 10, field row 1 (24), path 6, field row 2 (24)
	PorchDepth = 10,
	FieldSize = 24,
	PathWidth = 6,
	TileSize = 8,
	SoilSize = 7.6,
	SoilHeight = 1, -- the plate is SoilHeight * 0.6 tall; its invisible twin, the Tile_ part, carries the attributes
	-- field -> { column, row }: field 1 front centre (in front of the porch), then left, right, back row
	FieldGrid = { { 0, 1 }, { -1, 1 }, { 1, 1 }, { 0, 2 }, { -1, 2 }, { 1, 2 } },
	TilesPerField = 9,
	Fields = 6,
	FieldCosts = { 400, 3000, 20000, 1500000, 6000000 }, -- fields 2..6 (field 1 is free)
	PadSize = 6,
	PadLocalZ = 5, -- the FarmPad sits in the middle of the porch strip
	MarketRadius = 36,
	WallRadius = 230,
	WallSegments = 36,
	-- The server's distance check on a tap (Tap(slot, key) from Farm.client's Pick): a tile farther than this from
	-- your character answers "Walk closer to tap this crop". No client-side cap, so no tap is ever silent (REVIEW-1 B3).
	ServerReach = 40,
	GroundY = 0, -- top of the valley floor
}

Config.StartCoins = 20

-- ── Timers, limits, caches (DESIGN.md §2.5) ───────────────────────────────────────────────────────
Config.Play = {
	ActionMinSeconds = 0.12, -- at most ~8 farm actions a second per player (server tick())
	RateToastSeconds = 2, -- "Easy — one tap at a time" at most once per 2 s
	ServerNowHz = 1, -- workspace ServerNow attribute writes per second
	ClientExtrapolateMax = 1.5, -- a client runs its clock at most this far past the last ServerNow
	RipeLeadSeconds = 0.25, -- the client shows "ripe" this long AFTER the server would accept the tap
}

Config.Save = {
	Enabled = true,
	Store = "StormGrow_v1",
	AutosaveSeconds = 60,
	LockSeconds = 180, -- lock TTL, renewed by every autosave (three missed autosaves)
	LockRetrySeconds = 5,
	LockRetries = 6, -- 30 s, then read-only
	-- REVIEW-1 A2: a failed load call is retried 3 times (after 1, 2 and 4 s) before the session plays a fresh farm
	-- that never saves; the load is then retried every RecoverSeconds and the real farm replaces it when one lands.
	LoadRetries = 3,
	LoadRetrySeconds = 1,
	-- REVIEW-1 A1: a session read-only behind another server's lock asks again every RecoverSeconds, and takes the
	-- lock once it has run out with the record untouched (a crashed server never releases it)
	RecoverSeconds = 10,
	-- REVIEW-1 A5: a new Almanac entry asks for a save this soon after the last one (Roblox allows a write per key
	-- every 6 s); the board writes only what a save has landed
	SoonSeconds = 6,
}

Config.Board = {
	Store = "StormGrowAlmanac_v1",
	Epoch = 2e9, -- value = count * Epoch + (Epoch - reachedAtUnix); valid until Unix 2e9 (2033-05-18)
	PublicShown = 10,
	PublicFetch = 100,
	PublicCacheSeconds = 60,
	FriendsCap = 200,
	TopCachePages = 5, -- 5 pages of 100 = the top 500
	TopCacheSeconds = 120,
	WriteCoalesceSeconds = 30,
	-- REVIEW-1 B5: both prompts are pressed from 12 studs, where a row reads >= 12 pt on a 360-pt phone (FOV 70);
	-- the porch board stands 15 studs from the pad, turned to the spawn camera, and shows the top PorchShown
	PromptReach = 12,
	PorchShown = 5,
	Porch = { X = 15, Z = 4, FaceX = 0, FaceZ = -4, Width = 10, Height = 6.6 }, -- farm-local studs
	-- REVIEW-1 A6: one Friends/Everyone switch a second per player; a name that failed to resolve waits a minute
	PromptCooldownSeconds = 1,
	NameRetrySeconds = 60,
}

-- ══════════════════════════════════════════════════════════════════════════════════════════════════
-- THE SKY OVER YOUR FARM (client only; EYECANDY.md explains every value). Driven by `harvested`, the
-- lifetime coins your harvests earned. It only goes up and only the server writes it.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════
Config.Env = {
	HalfLife = 0.6, -- seconds: every blended value glides (a big harvest or a rejoin never cuts)
	LightingHz = 10, -- Lighting is written at most 10 times a second, and only when a value changed
	BragBandId = "eye", -- the band that is the brag moment
	Bands = {
		{
			id = "meadow", from = 0, fade = 0, name = "Sunny Meadow", emoji = "🌱",
			lighting = { ClockTime = 9.5, Brightness = 3, ExposureCompensation = 0.1,
				Ambient = rgb(120, 130, 120), OutdoorAmbient = rgb(150, 170, 150),
				FogStart = 200, FogEnd = 1600, FogColor = rgb(205, 225, 240) },
			atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(205, 225, 240), Decay = rgb(150, 190, 160), Glare = 0.3, Haze = 1.5 },
			sky = { StarCount = 0 },
			bloom = { Intensity = 0.8, Size = 24, Threshold = 0.95 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.18, TintColor = rgb(245, 255, 240) },
			sunRays = { Intensity = 0.12, Spread = 0.8 },
			ground = rgb(96, 168, 78),
			pieces = { "hills", "oaks", "pond", "farmhouse" },
			ambient = { { kind = "butterfly", count = 8 } },
			weather = { kind = "fluff", rate = 6 },
			hazards = {},
		},
		{
			id = "golden", from = 150, fade = 50, name = "Golden Fields", emoji = "🌾",
			lighting = { ClockTime = 11.5, Brightness = 3.2, ExposureCompensation = 0.15,
				Ambient = rgb(135, 130, 110), OutdoorAmbient = rgb(175, 165, 130),
				FogStart = 220, FogEnd = 1700, FogColor = rgb(240, 225, 185) },
			atmosphere = { Density = 0.26, Offset = 0.18, Color = rgb(240, 225, 185), Decay = rgb(200, 170, 110), Glare = 0.45, Haze = 1.4 },
			sky = { StarCount = 0 },
			bloom = { Intensity = 0.9, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.22, TintColor = rgb(255, 245, 220) },
			sunRays = { Intensity = 0.16, Spread = 0.75 },
			ground = rgb(170, 160, 80),
			pieces = { "hills", "hayRolls", "windmill" },
			ambient = { { kind = "bee", count = 6 }, { kind = "sparrow", count = 5 } },
			weather = { kind = "pollen", rate = 8 },
			hazards = { "hay" },
		},
		{
			id = "orchard", from = 1200, fade = 400, name = "Windy Orchard", emoji = "🍂",
			lighting = { ClockTime = 15.5, Brightness = 2.9, ExposureCompensation = 0.15,
				Ambient = rgb(140, 120, 105), OutdoorAmbient = rgb(180, 150, 120),
				FogStart = 200, FogEnd = 1500, FogColor = rgb(240, 200, 160) },
			atmosphere = { Density = 0.3, Offset = 0.15, Color = rgb(240, 205, 165), Decay = rgb(210, 140, 90), Glare = 0.6, Haze = 1.6 },
			sky = { StarCount = 0 },
			bloom = { Intensity = 0.95, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.2, TintColor = rgb(255, 235, 210) },
			sunRays = { Intensity = 0.2, Spread = 0.7 },
			ground = rgb(150, 130, 70),
			pieces = { "orchard", "barn", "scarecrow" },
			ambient = { { kind = "crow", count = 5 } },
			weather = { kind = "leaves", rate = 10 },
			hazards = { "hay", "crow" },
		},
		{
			id = "thunder", from = 9000, fade = 3000, name = "Thunder Plains", emoji = "⛈️",
			lighting = { ClockTime = 16.8, Brightness = 2.0, ExposureCompensation = 0.05,
				Ambient = rgb(110, 105, 125), OutdoorAmbient = rgb(135, 125, 150),
				FogStart = 160, FogEnd = 1200, FogColor = rgb(130, 120, 150) },
			atmosphere = { Density = 0.4, Offset = 0.08, Color = rgb(150, 140, 170), Decay = rgb(120, 100, 150), Glare = 0.8, Haze = 2.2 },
			sky = { StarCount = 0 },
			bloom = { Intensity = 1.0, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.02, TintColor = rgb(235, 225, 255) },
			sunRays = { Intensity = 0.1, Spread = 0.6 },
			ground = rgb(95, 120, 80),
			pieces = { "cloudBank", "lightningRod" },
			ambient = { { kind = "goose", count = 7 } },
			weather = { kind = "drizzle", rate = 14 },
			lightning = { everyMin = 5, everyMax = 11 }, -- silent distant bolts in the cloud bank
			hazards = { "crow", "ballLightning" },
		},
		{
			id = "frost", from = 55000, fade = 18000, name = "Frost Highlands", emoji = "❄️",
			lighting = { ClockTime = 17.6, Brightness = 2.2, ExposureCompensation = 0.2,
				Ambient = rgb(125, 135, 160), OutdoorAmbient = rgb(150, 170, 205),
				FogStart = 180, FogEnd = 1400, FogColor = rgb(200, 215, 240) },
			atmosphere = { Density = 0.35, Offset = 0.1, Color = rgb(205, 220, 245), Decay = rgb(150, 170, 220), Glare = 0.4, Haze = 1.8 },
			sky = { StarCount = 300 },
			bloom = { Intensity = 1.0, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = -0.05, TintColor = rgb(225, 240, 255) },
			sunRays = { Intensity = 0.12, Spread = 0.6 },
			ground = rgb(170, 190, 200),
			pieces = { "peaks", "pines", "frozenFall" },
			ambient = { { kind = "owl", count = 3 } },
			weather = { kind = "snow", rate = 12 },
			hazards = { "snowball", "ballLightning" },
		},
		{
			id = "eye", from = 300000, fade = 100000, name = "Eye of the Storm", emoji = "🌀", celebrate = true,
			lighting = { ClockTime = 17.2, Brightness = 2.8, ExposureCompensation = 0.3,
				Ambient = rgb(150, 130, 110), OutdoorAmbient = rgb(200, 165, 120),
				FogStart = 300, FogEnd = 2200, FogColor = rgb(255, 210, 160) },
			atmosphere = { Density = 0.22, Offset = 0.05, Color = rgb(255, 215, 170), Decay = rgb(240, 150, 90), Glare = 1.2, Haze = 1.0 },
			sky = { StarCount = 0 },
			bloom = { Intensity = 1.5, Size = 36, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.05, Contrast = 0.14, Saturation = 0.25, TintColor = rgb(255, 235, 205) },
			sunRays = { Intensity = 0.3, Spread = 0.6 },
			ground = rgb(150, 150, 90),
			pieces = { "stormWall", "sunbeam", "isles" },
			ambient = { { kind = "sprite", count = 10 } },
			weather = { kind = "sparks", rate = 10 },
			lightning = { everyMin = 3, everyMax = 7 }, -- veins inside the storm wall
			hazards = { "ballLightning", "dustDevil" },
		},
		{
			id = "starfall", from = 11000000, fade = 3600000, name = "Starfall Summit", emoji = "✨",
			lighting = { ClockTime = 22.5, Brightness = 1.2, ExposureCompensation = 0.5,
				Ambient = rgb(110, 110, 150), OutdoorAmbient = rgb(120, 125, 175),
				FogStart = 400, FogEnd = 3000, FogColor = rgb(20, 25, 55) },
			atmosphere = { Density = 0.15, Offset = 0, Color = rgb(40, 45, 90), Decay = rgb(80, 60, 140), Glare = 0, Haze = 0.4 },
			sky = { StarCount = 3000 },
			bloom = { Intensity = 1.6, Size = 40, Threshold = 0.7 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.12, TintColor = rgb(230, 235, 255) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			ground = rgb(70, 90, 110),
			pieces = { "aurora", "fallingStars", "lanterns" },
			ambient = { { kind = "firefly", count = 14 } },
			weather = { kind = "glints", rate = 8 },
			hazards = { "ballLightning", "snowball", "dustDevil" },
		},
	},

	-- The global weather event is an OVERLAY on the band (EnvBands.overlay for `set`, a multiplier for
	-- `mul`), weighted 0 -> 1 over Weather.FadeSeconds at the start and back at the end.
	Overlays = {
		storm = {
			set = {
				lighting = { FogColor = rgb(95, 80, 130), FogEnd = 700 },
				atmosphere = { Color = rgb(120, 105, 150), Density = 0.5, Haze = 2.6 },
				colorCorrection = { TintColor = rgb(215, 205, 255), Saturation = -0.1 },
			},
			mul = { lighting = { Brightness = 0.5 } },
			weather = { kind = "rain", rate = 40 },
		},
		frost = {
			set = {
				lighting = { FogColor = rgb(225, 235, 250) },
				atmosphere = { Color = rgb(225, 235, 250), Haze = 2.2 },
				colorCorrection = { TintColor = rgb(220, 235, 255), Saturation = -0.15 },
			},
			mul = {},
			weather = { kind = "snow", rate = 30 },
		},
		rainbow = {
			set = { colorCorrection = { Saturation = 0.35, Brightness = 0.05 } },
			mul = { lighting = { Brightness = 1.15 } },
			weather = { kind = "glints", rate = 10 },
		},
	},

	-- Ambient life: never dangerous, never collidable. Distances in studs from the camera.
	Critters = {
		butterfly = { rMin = 20, rMax = 90, yMin = 1, yMax = 8, speedMin = 3, speedMax = 6 },
		bee = { rMin = 15, rMax = 70, yMin = 1, yMax = 6, speedMin = 5, speedMax = 9 },
		sparrow = { rMin = 60, rMax = 200, yMin = 12, yMax = 40, speedMin = 16, speedMax = 24 },
		crow = { rMin = 60, rMax = 180, yMin = 20, yMax = 45, speedMin = 10, speedMax = 16 },
		goose = { rMin = 120, rMax = 260, yMin = 40, yMax = 80, speedMin = 18, speedMax = 26 },
		owl = { rMin = 60, rMax = 160, yMin = 18, yMax = 40, speedMin = 8, speedMax = 12 },
		sprite = { rMin = 15, rMax = 80, yMin = 2, yMax = 20, speedMin = 2, speedMax = 5, rise = true },
		firefly = { rMin = 10, rMax = 70, yMin = 1, yMax = 8, speedMin = 1, speedMax = 3 },
	},
}

-- The brag unlocks the Stormfruit: one number, read from the band table.
do
	local brag = 0
	for _, b in Config.Env.Bands do
		if b.id == Config.Env.BragBandId then brag = b.from end
	end
	Config.Crops[#Config.Crops].needHarvested = brag
end

-- ── Hazards (DESIGN.md §4): rare, telegraphed, one at a time, client only, cost ~2 s and nothing else ─
-- The red ring at your feet IS the zone: radius hitRadius + PlayerRadius (Hazards.zone). Step out of
-- it in any direction and you are safe. Template values unless DESIGN.md §4 says otherwise.
Config.Hazards = {
	IntervalMin = 120,
	IntervalMax = 180,
	MinTelegraphSeconds = 3.0,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	AimJitter = 1.0,
	SpreadDegrees = 35,
	-- 25, not the template's 20: the glue clamps the camera pitch to >= -25 so the window's upper edge is
	-- never below 0 degrees and no lane starts underground (DESIGN.md §4, the one genre adaptation)
	ViewPitchDegrees = 25,
	GroundPitchFloor = -25, -- degrees: Sky.client passes max(cameraPitch, this) as ctx.pitch
	KindFitDegrees = 25,
	KnockLift = 8,
	KnockSeconds = 0.9,
	NearMissStuds = 8,
	Kinds = {
		hay = { speed = 16, telegraph = 3.5, commit = 1.8, pass = 2.0, hitRadius = 2.5, visualRadius = 2.5, knock = 34, pitch = 0, pitchSpread = 0 },
		crow = { speed = 24, telegraph = 3.0, commit = 1.5, pass = 1.5, hitRadius = 1.8, visualRadius = 1.8, knock = 30, pitch = 6, pitchSpread = 4 },
		ballLightning = { speed = 18, telegraph = 3.5, commit = 1.8, pass = 2.0, hitRadius = 2.0, visualRadius = 2.0, knock = 38, pitch = 4, pitchSpread = 3 },
		snowball = { speed = 20, telegraph = 3.2, commit = 1.6, pass = 2.0, hitRadius = 2.5, visualRadius = 2.5, knock = 34, pitch = 0, pitchSpread = 0 },
		dustDevil = { speed = 12, telegraph = 4.0, commit = 2.0, pass = 2.0, hitRadius = 3.0, visualRadius = 3.0, knock = 30, pitch = 0, pitchSpread = 0 },
	},
	Names = { hay = "HAY BALE", crow = "CROW", ballLightning = "BALL LIGHTNING", snowball = "SNOWBALL", dustDevil = "DUST DEVIL" },
}

-- ── Rest (DESIGN.md §5): freezes ONLY the hazard clock. Growth and the weather never stop. ─────────
Config.Rest = {
	-- 90, not the template's 20 (REVIEW-1 B2): a farmer stands still between sweeps waiting for crops, and at 20 s the
	-- idle rule rested a normal player for 44-55% of a session with the hazard clock frozen (one hazard per ~5.3 min
	-- instead of the standard's 2-3). Long walks to the brag (2026-10-01, phases :16:40 and :36:40): 20 s -> 48-51% in
	-- rest, one hazard per 299-338 s; 60 s -> 23-28%, 216-255 s; 90 s -> 5-7%, 176-188 s; 120 s -> 0-1%, 176-180 s.
	-- A minute and a half with no step and no tap is AFK, and a hit costs only a knock here, never a crop.
	IdleSeconds = 90,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 8, -- the longest hazard flight (dust devil, 4.0 + 2.0 s) + 2 s
}

-- ── Budgets (DESIGN.md §3.5): caps the code enforces, measured headless ───────────────────────────
Config.Budget = {
	MaxServerParts = 1400,
	MaxCropParts = 1620,
	MaxPartsPerCrop = 5,
	MaxSceneryParts = 700,
	MaxCritterParts = 60,
	MaxLights = 12,
	MaxWeatherEmitters = 4,
	MaxEmitterRate = 60, -- particles per second summed over the weather emitters
	MaxMarkEmitters = 24,
	MaxBolts = 6,
	MaxHazards = 1,
	MaxHazardParts = 30,
	MarkEmitterRange = 90, -- studs: marked crops farther than this keep their static look only
	BoltRange = 160, -- studs: strikes farther than this leave the mark's look without a bolt
}

-- ── The pacing model's players (tests/FarmModel.luau; never read by the game) ─────────────────────
Config.Pacing = {
	BragMinutes = { 30, 45 },
	HazardEverySeconds = 150, -- the mean of the 120..180 s hazard clock
	Profiles = {
		normal = { checkEvery = 15, tap = 1.0, holdHorizon = 60, dodge = 1.5 },
		fast = { checkEvery = 5, tap = 0.7, holdHorizon = 90, dodge = 1.0 },
		slow = { checkEvery = 40, tap = 1.5, holdHorizon = 30, dodge = 2.5 },
		nohold = { checkEvery = 15, tap = 1.0, holdHorizon = -1, dodge = 1.5, neverHold = true },
		combo = { checkEvery = 15, tap = 1.0, holdHorizon = 60, dodge = 1.5, combo = true, comboHorizon = 420 },
		planner = { checkEvery = 10, tap = 1.0, holdHorizon = 90, dodge = 1.5, combo = true, comboHorizon = 420, hunt = true },
	},
}

return Config
