--!strict
-- Config.luau — every tunable in Lost & Found Depot, in one block.
--
-- Each number has its reason in DESIGN.md §6 (and the model run behind it in design/model.luau).
-- Nothing here is secret: this file replicates to every client. The Back Room note and the code
-- table live in src/server/Secret.luau, which never leaves the server (DESIGN.md §8.2).
--
-- Pure data, requires nothing, so the luau CLI tests and Roblox load the same file.

local Config = {}

-- The date the spec was written. Any constant works: the per-session salt, not this, is what
-- makes a shift unpredictable (DESIGN.md §7.1).
Config.WorldSeed = 20260916

--============================================================================== rules (§3)

Config.Rules = {
	Letters = { "B", "E", "K", "T" },
	Conditions = 5,
	Routes = { "RED", "GREEN", "BLUE", "YELLOW", "PURPLE", "WHITE" },
	-- The six bins, by stable id. The id is server bookkeeping; players read `BinNames`.
	Bins = { "BAGS", "ELECTRONICS", "KEYS", "TOYS", "REPAIR", "CLAIMS" },
	BinNames = {
		BAGS = "BAGS & WEAR",
		ELECTRONICS = "ELECTRONICS",
		KEYS = "KEYS & WALLETS",
		TOYS = "TOYS",
		REPAIR = "REPAIR",
		CLAIMS = "CLAIMS",
	},
	LetterBin = { B = "BAGS", E = "ELECTRONICS", K = "KEYS", T = "TOYS" },
	-- The base manual: RED is claimed, condition 5 is broken.
	ClaimedRoute = "RED",
	BrokenCondition = 5,
	-- 0.25: the lowest value at which both torn clauses decide at least one item in more than 4
	-- shifts in 5 (torn-condition 88.5%, torn-letter 82.0%) [M 1].
	TornChance = 0.25,
	TornUnlockShift = 2,
	MemoUnlockShift = 3,
}

--============================================================================== catalog (§3.2)

-- 16 items, 4 per letter, each in 2 colour variants. `builder` names the Part recipe in the
-- server's BUILDERS table; Shift.missingBuilders reports any archetype without one at boot.
-- No rule reads the variant (§3.2), and nothing about an item's look depends on its tag.
Config.Catalog = {
	{ id = "backpack", name = "Backpack", letter = "B", builder = "backpack",
		colors = { { 60, 110, 190 }, { 200, 90, 60 } } },
	{ id = "sneaker", name = "Sneaker", letter = "B", builder = "sneaker",
		colors = { { 235, 235, 235 }, { 40, 40, 48 } } },
	{ id = "cap", name = "Baseball Cap", letter = "B", builder = "cap",
		colors = { { 190, 40, 50 }, { 40, 120, 70 } } },
	{ id = "scarf", name = "Scarf", letter = "B", builder = "scarf",
		colors = { { 150, 60, 160 }, { 230, 180, 60 } } },

	{ id = "phone", name = "Phone", letter = "E", builder = "phone",
		colors = { { 30, 30, 36 }, { 220, 220, 228 } } },
	{ id = "headphones", name = "Headphones", letter = "E", builder = "headphones",
		colors = { { 50, 50, 58 }, { 240, 120, 170 } } },
	{ id = "camera", name = "Camera", letter = "E", builder = "camera",
		colors = { { 45, 45, 50 }, { 170, 140, 100 } } },
	{ id = "laptop", name = "Laptop", letter = "E", builder = "laptop",
		colors = { { 170, 172, 180 }, { 40, 60, 90 } } },

	{ id = "keyring", name = "Keyring", letter = "K", builder = "keyring",
		colors = { { 210, 175, 60 }, { 180, 185, 195 } } },
	{ id = "wallet", name = "Wallet", letter = "K", builder = "wallet",
		colors = { { 110, 70, 40 }, { 30, 30, 34 } } },
	{ id = "padlock", name = "Padlock", letter = "K", builder = "padlock",
		colors = { { 200, 165, 70 }, { 150, 155, 165 } } },
	{ id = "badge", name = "ID Badge", letter = "K", builder = "badge",
		colors = { { 60, 140, 210 }, { 230, 120, 40 } } },

	{ id = "teddy", name = "Teddy Bear", letter = "T", builder = "teddy",
		colors = { { 160, 110, 60 }, { 235, 225, 210 } } },
	{ id = "toycar", name = "Toy Car", letter = "T", builder = "toycar",
		colors = { { 210, 50, 50 }, { 60, 160, 220 } } },
	{ id = "ball", name = "Beach Ball", letter = "T", builder = "ball",
		colors = { { 250, 200, 60 }, { 90, 200, 190 } } },
	{ id = "duck", name = "Rubber Duck", letter = "T", builder = "duck",
		colors = { { 250, 215, 40 }, { 240, 140, 180 } } },
}

--============================================================================== shift (§6.3)

Config.Shift = {
	Items = 30,
	TraySlots = 8, -- 2 rows x 4; the knee in [M 4]
	-- 330 s: the shortest 30-s step at which a first-timer clears stage 3 in >= 90% of shifts [M 6].
	Seconds = 330,
	-- 8 s: the smallest penalty at which a slow reader beats a guesser by >= 25% [M 5].
	MisfilePenalty = 8,
	PerfectMaxMisfiles = 3,
	IntermissionSeconds = 4,
	TimerPoll = 0.25,
	-- A picked slot refills from the cart this long after the pick, not in the same frame. Without
	-- the beat, two clicks on one item in one frame (a double tap) would carry that item AND the
	-- one the cart rolled into its place. Not in DESIGN.md §6; added at build time for §10.2's
	-- "same item picked twice" row. How it feels is a Studio question.
	RefillSeconds = 0.3,
	-- Career shift 1 only: one item whose tag matches its look, then one whose tag contradicts it.
	-- Each is { archetype id, tag, tray slot }. The answer is fixed and public (§7.2 step 4).
	Tutorial = {
		{ archetype = "teddy", variant = 1, letter = "T", cond = 2, route = "GREEN", slot = 6 },
		{ archetype = "phone", variant = 1, letter = "K", cond = 1, route = "BLUE", slot = 7 },
	},
}

--============================================================================== economy (§6.4)

Config.Economy = {
	PayFirstTry = 10,
	ComboCap = 10, -- first-try pay is PayFirstTry + min(combo, ComboCap), combo counting this sort
	PayResort = 5,
	PerfectBonus = 100,
	-- Both upgrade tracks share one ladder: level 1, 2, 3 cost 250, 800, 2000 [M 9].
	Prices = { 250, 800, 2000 },
	MaxLevel = 3,
	Carry = { 2, 3, 4, 5 }, -- by cartLevel 0..3
	WalkSpeed = { 16, 18, 20, 22 }, -- by shoesLevel 0..3
	BacklogSize = 500,
}

--============================================================================== the bay (§4, §6.2)

-- Bay-local studs: +Y up, floor top at y = 0, the pick point P at the origin, bins toward -Z, the
-- spawn toward +Z.
Config.Bay = {
	Count = 12,
	FirstX = 100,
	Pitch = 80,
	-- interior bounds
	MinX = -36,
	MaxX = 36,
	MinZ = -36,
	MaxZ = 20,
	WallHeight = 16,
	WallThickness = 1,

	-- the bin arc
	ArcRadius = 28,
	ArcFirstDegrees = 15,
	ArcStepDegrees = 30,
	BinSize = { 8, 4, 6 },
	BinPromptDistance = 6,
	BinLightBrightness = 1.2,
	BinLightRange = 10,

	-- the tray
	TrayCentre = { 0, 1.5, 6.5 },
	TraySize = { 16, 3, 6 },
	StepHeight = 1.5,
	SlotXs = { -6, -2, 2, 6 },
	FrontRowZ = 5,
	BackRowZ = 8,
	-- WHAT A TAP HITS. The item's own pieces are the tap target (a ClickDetector on the item Model),
	-- plus a low invisible tile on the tray surface under each slot, so a flat Phone or ID Badge is
	-- easy to hit and an empty slot still answers. The old fixed 3.5 x 3 x 2.5 invisible box stood
	-- above the other row's items: a tap on a visible back-row item from the bin side picked the
	-- front-row item in front of it, and the tutorial Phone took 1 tap in 40 from there. A box
	-- shaped to each item's bounds still lost 30% of pad-side taps to the air around round shapes
	-- (REVIEW-1 finding 6; robloxemu check_lostfounddepot_view.luau measures all three).
	-- The tile's height is measured, not picked: taps on visible FRONT-row items made from the pad
	-- side reach them 90.8% of the time with a 0.4-stud tile (the back row's tiles catch rays that
	-- skim the step), 98.5% at 0.2, 99.4% at 0.1 (3169 of 3187, re-measured on the final source), 100% at 0.05; every other view is 100% at all four.
	SlotTile = { 2, 0.1, 2 },
	-- Two clicks for ONE tap arriving this close together (a double tap, or the engine reporting a
	-- tap to both the item's and the tile's ClickDetector) are one pick, not a pick and a refusal.
	SamePickSeconds = 0.05,
	-- The tag floats this far above the surface its item rests on, whatever the item.
	TagAboveSurface = 3.9,
	ItemReach = 12,
	PutBackDistance = 8,
	TagMaxDistance = 40,

	-- the rest
	PadCentre = { 0, 0.5, 14 },
	PadSize = { 6, 1, 6 },
	LockerCentre = { 12, 3, 16 },
	LockerSize = { 4, 6, 2 },
	LockerPromptDistance = 6,
	DoorWidth = 8,
	DoorHeight = 10,
	DoorPromptDistance = 6,
	BackRoom = { MinX = -10, MaxX = 10, MinZ = -50, RoofY = 14 },
	-- Pressing E at the open door re-sends the note at most this often. The camera tween is 3 s, so
	-- a honest second press inside it has nothing new to show; a spammed one was a DataStore write
	-- and a 592-byte payload per press (REVIEW-1 R1-4).
	SceneCooldownSeconds = 3,

	-- 2 studs of forgiveness on every server-side reach check (§6.2).
	ReachSlack = 2,
	-- The engine places a root part at a SpawnLocation's top face + 2.51 (SPAWN-ORDER.md §2); the
	-- re-place uses +3 so it is never placed inside the pad.
	PlaceAbovePad = 3,
	CharacterWaitFrames = 300,
	-- No collidable fixture inside a bay may have a top face above this (§4.2).
	MaxStandableTop = 6,
	MaxPartsPerBay = 120,
}

Config.BreakRoom = {
	HalfSize = 20,
	WallHeight = 16,
}

--============================================================================== look (§13.2)

Config.Colors = {
	Route = {
		RED = { 255, 90, 90 },
		GREEN = { 80, 220, 110 },
		BLUE = { 110, 170, 255 },
		YELLOW = { 255, 215, 60 },
		PURPLE = { 200, 130, 255 },
		WHITE = { 245, 245, 245 },
	},
	TagBackground = { 34, 36, 42 },
	TagBorder = { 214, 186, 120 },
	TagText = { 245, 245, 245 },
	Torn = { 150, 150, 160 },
	BinSteel = { 118, 124, 134 },
	SignBoard = { 28, 30, 36 },
	SignText = { 245, 245, 245 },
	Floor = { 150, 146, 138 },
	Wall = { 196, 190, 176 },
	Tray = { 120, 92, 64 },
	Locker = { 70, 110, 150 },
	Door = { 86, 60, 40 },
	Brass = { 210, 170, 70 },
}

--============================================================================== persistence (§6.5)

Config.Save = {
	Enabled = true,
	Store = "LostFoundDepot_v1",
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
	-- A load or a leave-time release that raises is tried this many times, waiting 1 s, then 2 s,
	-- between attempts. One transient DataStore error used to drop a veteran into the tutorial with
	-- 0 cash for the whole session (REVIEW-1 R1-3).
	Attempts = 3,
	-- BindToClose waits at most this long for release saves already in flight (Roblox allows 30).
	CloseWaitSeconds = 25,
}

-- At most one State payload per this many seconds answers a burst of Select events; the first one
-- after a quiet moment is answered at once. 10,000 Selects in one frame used to send 9,999 full
-- State payloads, 14.4 MB (REVIEW-1 R1-5).
Config.Remotes = {
	SelectPushSeconds = 0.1,
	-- EVERY STATE-CHANGING IN-WORLD ACTION (pick, put back, deposit, buy) spends one token from a
	-- per-player bucket that holds ActionBurst and refills ActionsPerSecond. Each accepted action
	-- sends a State payload and can build Parts in the shared workspace; only Select was throttled,
	-- and 10,000 pick + put-back pairs in one frame were 20,000 payloads (17.9 MB) and 80,000
	-- Instance.new calls (REVIEW-1 pass 3, exploit finding 1). A player tapping five items in a
	-- frame and putting one back is 6; a brisk put-back-and-re-pick every quarter second is 4 per
	-- second, which never runs dry.
	ActionBurst = 10,
	ActionsPerSecond = 5,
	-- Refusals and info toasts: the same text again within NoticeRepeatSeconds is not re-sent (the
	-- toast on screen already says it), and at most NoticeBurst of them go out at once, refilling
	-- NoticesPerSecond. A deposit's "+11", a misfile and a Perfect Shift are never held back; the
	-- action bucket already bounds them. 10,000 Redeem "NOPE" events used to be 10,000 toasts.
	NoticeRepeatSeconds = 0.05,
	NoticeBurst = 6,
	NoticesPerSecond = 3,
}

Config.Codes = {
	RedeemCooldown = 2,
	MaxLength = 20,
}

--============================================================================== the wings (EYECANDY.md)

-- Everything below is read by the CLIENT only (src/client/Wings.client.luau): cosmetic, or harmful only
-- to the local player. The server never reads it and nothing in it is secret.
--
-- The depot moves you to a new WING as your career grows. Progress = career shifts completed (the
-- server's own `shifts`) plus the share of the RUNNING shift already cleared (Wings.progress), so a wing
-- fades in while you sort the last third of the shift before it, and glides (HalfLife) when progress
-- jumps (a timed-out shift, a join). A wing is NAMED by whole completed shifts: the chip, the title
-- card and which hazards fly. `from` = completed shifts; the career shift you work there is from + 1.
-- Minutes to each wing: tests/Pacing.spec.luau, from design/model.luau's own career (Config.Pacing).
-- Colours are {r, g, b} so EnvBands can blend them in the luau CLI.

Config.Env = {
	SpaceBandId = "station", -- the wing that counts as "I made it to space"
	HalfLife = 0.6, -- s: lighting, fog and scenery glide toward the target, never cut
	LightingHz = 10, -- Lighting is written at most 10 times a second
	-- The overhead pieces (roofs, lamps, string lights; every part of them sits above the 16-stud wall
	-- tops) fade out as the CAMERA rises toward the wall tops (Wings.overheadFade). Every overhead part is at
	-- or above Gone, so a camera that can see any of the roof is below all of it and cannot look down at a
	-- tag through it; a camera at or above Gone sees no roof at all. Shown in full at camera y <= Full.
	-- Studio shots from above the roof: raise both in the shots place only (EYECANDY.md §9).
	OverheadFade = { Full = 13, Gone = 16 },
	Bands = {
		{
			id = "city", from = 0, fade = 0, name = "CITY DEPOT", sub = "Lost & Found, platform level",
			-- = Fx.Presets.Temple (the server's lighting), so the client takes over without a jump
			lighting = { ClockTime = 15.5, Brightness = 3, ExposureCompensation = 0.15,
				Ambient = { 120, 125, 140 }, OutdoorAmbient = { 150, 160, 185 },
				FogStart = 100, FogEnd = 900, FogColor = { 200, 220, 245 } },
			atmosphere = { Density = 0.32, Offset = 0.25, Color = { 200, 220, 245 }, Decay = { 130, 160, 200 }, Glare = 0.4, Haze = 2 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.15, TintColor = { 255, 250, 240 } },
			sunRays = { Intensity = 0.18, Spread = 0.9 },
			pieces = { "cityRoof", "citySkyline" },
			ambient = { { kind = "pigeon", count = 6 } },
			hazards = {},
		},
		{
			id = "airport", from = 3, fade = 0.34, name = "AIRPORT LOST & FOUND", sub = "Arrivals hall, gate B",
			lighting = { ClockTime = 12.5, Brightness = 3.2, ExposureCompensation = 0.1,
				Ambient = { 125, 132, 148 }, OutdoorAmbient = { 160, 175, 205 },
				FogStart = 150, FogEnd = 1400, FogColor = { 205, 225, 250 } },
			atmosphere = { Density = 0.26, Offset = 0.2, Color = { 205, 225, 250 }, Decay = { 150, 180, 220 }, Glare = 0.3, Haze = 1.4 },
			sky = { StarCount = 0, SunAngularSize = 20, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.12, TintColor = { 245, 250, 255 } },
			sunRays = { Intensity = 0.12, Spread = 0.8 },
			pieces = { "airportRoof", "airfield" },
			ambient = { { kind = "airliner", count = 2 } },
			hazards = { "trolley", "suitcase" },
		},
		{
			id = "train", from = 6, fade = 0.34, name = "TRAIN STATION", sub = "Left luggage, under the clock",
			lighting = { ClockTime = 17.2, Brightness = 2.6, ExposureCompensation = 0.15,
				Ambient = { 132, 122, 116 }, OutdoorAmbient = { 172, 150, 130 },
				FogStart = 120, FogEnd = 1100, FogColor = { 232, 204, 172 } },
			atmosphere = { Density = 0.33, Offset = 0.15, Color = { 235, 205, 170 }, Decay = { 200, 140, 100 }, Glare = 0.8, Haze = 2.2 },
			sky = { StarCount = 0, SunAngularSize = 24, MoonAngularSize = 11 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.82 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.18, TintColor = { 255, 240, 222 } },
			sunRays = { Intensity = 0.25, Spread = 0.7 },
			pieces = { "trainShed", "viaduct" },
			ambient = { { kind = "pigeon", count = 8 } },
			weather = { kind = "steam", rate = 6 },
			hazards = { "porter", "pigeon" },
		},
		{
			id = "park", from = 9, fade = 0.34, name = "THEME PARK", sub = "Guest services, by the big wheel",
			lighting = { ClockTime = 18.1, Brightness = 2.0, ExposureCompensation = 0.25,
				Ambient = { 138, 118, 142 }, OutdoorAmbient = { 178, 142, 172 },
				FogStart = 150, FogEnd = 1200, FogColor = { 240, 172, 162 } },
			atmosphere = { Density = 0.3, Offset = 0.1, Color = { 245, 182, 172 }, Decay = { 220, 110, 140 }, Glare = 1.0, Haze = 1.8 },
			sky = { StarCount = 400, SunAngularSize = 26, MoonAngularSize = 12 },
			bloom = { Intensity = 1.3, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.3, TintColor = { 255, 236, 242 } },
			sunRays = { Intensity = 0.3, Spread = 0.6 },
			pieces = { "parkLights", "parkRides" },
			ambient = { { kind = "balloon", count = 8 } },
			weather = { kind = "confetti", rate = 8 },
			hazards = { "beachball", "bumpercar" },
		},
		{
			id = "station", from = 13, fade = 0.34, name = "SPACE STATION", sub = "Orbital lost property, deck 3",
			celebrate = true,
			lighting = { ClockTime = 23, Brightness = 1.2, ExposureCompensation = 0.5,
				Ambient = { 120, 126, 162 }, OutdoorAmbient = { 125, 135, 180 },
				FogStart = 20000, FogEnd = 100000, FogColor = { 5, 8, 20 } },
			atmosphere = { Density = 0, Offset = 0, Color = { 20, 25, 45 }, Decay = { 40, 40, 80 }, Glare = 0, Haze = 0 },
			sky = { StarCount = 3500, SunAngularSize = 12, MoonAngularSize = 14 },
			bloom = { Intensity = 1.4, Size = 40, Threshold = 0.78 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.08, TintColor = { 235, 240, 255 } },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "stationDome", "earthView" },
			ambient = { { kind = "satellite", count = 2 }, { kind = "astronaut", count = 1 } },
			weather = { kind = "motes", rate = 5 },
			hazards = { "crate", "drone" },
		},
		{
			id = "galaxy", from = 36, fade = 0.34, name = "BEYOND THE GALAXY", sub = "The last lost & found there is",
			lighting = { ClockTime = 23.8, Brightness = 1.0, ExposureCompensation = 0.6,
				Ambient = { 128, 116, 152 }, OutdoorAmbient = { 145, 125, 175 },
				FogStart = 20000, FogEnd = 100000, FogColor = { 15, 5, 25 } },
			atmosphere = { Density = 0, Offset = 0, Color = { 40, 20, 60 }, Decay = { 90, 40, 110 }, Glare = 0, Haze = 0 },
			sky = { StarCount = 5000, SunAngularSize = 8, MoonAngularSize = 6 },
			bloom = { Intensity = 1.5, Size = 44, Threshold = 0.76 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.2, Saturation = 0.3, TintColor = { 250, 232, 255 } },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "stationDome", "galaxyView" },
			ambient = { { kind = "comet", count = 1 }, { kind = "satellite", count = 1 } },
			weather = { kind = "stardust", rate = 6 },
			hazards = { "blob", "meteorite" },
		},
	},
	-- Ambient life: spawned on a ring around the CAMERA (EnvBands.ambientSpawn), always outside the bay
	-- (rMin >= 60) and over the 16-stud walls (yMin >= 25 above the camera). Pooled, recycled when out of range.
	Critters = {
		pigeon = { rMin = 60, rMax = 220, yMin = 26, yMax = 70, speedMin = 14, speedMax = 22, flock = 3 },
		airliner = { rMin = 380, rMax = 800, yMin = 90, yMax = 260, speedMin = 55, speedMax = 75 },
		balloon = { rMin = 80, rMax = 300, yMin = 25, yMax = 90, speedMin = 3, speedMax = 6, rise = true },
		satellite = { rMin = 160, rMax = 480, yMin = 60, yMax = 220, speedMin = 6, speedMax = 12 },
		astronaut = { rMin = 90, rMax = 220, yMin = 40, yMax = 110, speedMin = 2, speedMax = 4 },
		comet = { rMin = 700, rMax = 1500, yMin = 200, yMax = 600, speedMin = 90, speedMax = 140 },
	},
}

-- Hazards: RARE, telegraphed, one at a time, client-only (they can only ever bump YOU). A hit is a
-- stumble: a short sideways shove and 0.6 s off your feet. Nothing is dropped, lost or recorded; the
-- server never hears of it. The clock they run on counts only RUNNING shift time you are not resting
-- (Wings.hazardsMayRun): none between shifts, none on a break, none in the first wing.
-- The red ring at your feet IS the danger zone (Hazards.checkHit): step out of it in any direction.
Config.Hazards = {
	IntervalMin = 120, -- s of running shift clock between hazards, at least ...
	IntervalMax = 180, -- ... and at most
	MinTelegraphSeconds = 3,
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	AimJitter = 0.8,
	SpreadDegrees = 35, -- a lane STARTS within ±35 degrees of where the camera looks ...
	ViewPitchDegrees = 20, -- ... and within ±20 degrees of its pitch
	KindFitDegrees = 25,
	KnockLift = 6, -- studs/s up on a hit: 0.1 studs of lift, never onto the tray step
	KnockSeconds = 0.6, -- PlatformStand after a hit: the stumble
	NearMissStuds = 6, -- for measurement: passing within 6 studs is a near-hit
	-- The bay is walled. A lane starts at least FloorMargin off a wall (Wings.clipLane pulls it in and
	-- slows it, so the warning keeps its length), and a hazard waits until the camera's view window has at
	-- least MinLaneStuds of floor ahead (Wings.room), so it never pops out of a wall in your face.
	FloorMargin = 2,
	MinLaneStuds = 10,
	-- The tray, the six crates and the locker are obstacles too (Wings.obstacles), grown by this much: a
	-- trolley never rolls through a crate. 1.5, because a bin stand is only 2 studs in front of its crate.
	ObstacleMargin = 1.5,
	-- A lane also LOCKS (turns red, stops following you) the moment the hazard comes within its reach + this
	-- many studs of you (Wings.lockNear): on a small floor a homing hazard could otherwise touch a player
	-- before its ring turned red. 3 is more than one frame can close (a 22-stud/s walker + 1.5x a hazard).
	LockExtraStuds = 3,
	-- ... and early enough that a player standing in the ring has MinReactSeconds between the ring turning
	-- red and the first moment the hazard can touch them (Wings.lockNear locks at reach + speed x this). A
	-- fitted lane is slow, and a slow hazard touches a player well before it "arrives" at the aim point, so
	-- the template's commit time alone is not enough here.
	-- ENFORCED by the hit rule (Wings.checkHit, REVIEW-2 finding 1): a knock needs the player to have been
	-- INSIDE THE RED RING this long without leaving it (counted from the ring turning red or from stepping into
	-- it, whichever is later), whatever they do; a walker could otherwise meet a hazard 0.13 s after red.
	-- Walking out of a ring takes 0.21-0.28 s. EYECANDY.md promises the player 1 s: never lower it.
	MinReactSeconds = 1.0,
	-- ENFORCED (Wings.checkHit): no knock sooner than this after the warning appeared. EYECANDY.md promises 2 s.
	MinWarnSeconds = 2.0,
	-- `ground` kinds roll on the floor: their lane is kept level (Wings.groundLane), the model sits on the floor.
	-- hitRadius is smaller than the model: forgiving, never unfair.
	Kinds = {
		trolley = { label = "RUNAWAY TROLLEY", speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, visualRadius = 2.6, knock = 24, pitch = 0, pitchSpread = 0, ground = true },
		suitcase = { label = "TUMBLING SUITCASE", speed = 12, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 1.5, visualRadius = 2, knock = 22, pitch = 0, pitchSpread = 0, ground = true },
		porter = { label = "PORTER'S CART", speed = 13, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, visualRadius = 2.6, knock = 24, pitch = 0, pitchSpread = 0, ground = true },
		pigeon = { label = "PIGEON", speed = 16, telegraph = 3.0, commit = 1.5, pass = 2.0, hitRadius = 1.2, visualRadius = 1.2, knock = 16, pitch = 12, pitchSpread = 6 },
		beachball = { label = "GIANT BEACH BALL", speed = 12, telegraph = 3.2, commit = 1.6, pass = 3.0, hitRadius = 2.0, visualRadius = 2.5, knock = 26, pitch = 0, pitchSpread = 0, ground = true },
		bumpercar = { label = "BUMPER CAR", speed = 13, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.9, visualRadius = 2.8, knock = 26, pitch = 0, pitchSpread = 0, ground = true },
		crate = { label = "FLOATING CRATE", speed = 8, telegraph = 3.6, commit = 2.0, pass = 3.5, hitRadius = 1.8, visualRadius = 2.2, knock = 20, pitch = 0, pitchSpread = 10 },
		drone = { label = "REPAIR DRONE", speed = 14, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 1.4, visualRadius = 1.8, knock = 20, pitch = 10, pitchSpread = 6 },
		blob = { label = "RUNAWAY ALIEN PET", speed = 10, telegraph = 3.4, commit = 1.8, pass = 3.0, hitRadius = 1.8, visualRadius = 2.2, knock = 22, pitch = 0, pitchSpread = 0, ground = true },
		meteorite = { label = "SPACE ROCK", speed = 14, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 1.8, visualRadius = 2.2, knock = 26, pitch = 8, pitchSpread = 6 },
	},
}

-- The BREAK (EYECANDY.md §4): the button, or standing still IdleSeconds. It STARTS only while the shift
-- clock is not running; pressed mid-shift it is booked for the end of the shift; the first pickup ends it
-- (Wings.pressBreak / updateBreak). Rest's own rules on top: never mid-air, never with a hazard in the
-- air (queued instead), any movement wakes you.
Config.Rest = {
	IdleSeconds = 20,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	-- a queued break outlives the longest hazard flight (crate: 3.6 + 3.5 = 7.1 s) by at least 2 s
	PendingSeconds = 10,
}

-- Client budget, phone first. Measured in robloxemu/check_lostfounddepot_wings.luau at every wing and
-- every seam. The server builds none of this.
Config.Budget = {
	MaxLocalParts = 220,
	MaxEmitters = 4,
	MaxWeatherEmitters = 2, -- enforced in WingArt through EnvBands.capRates
	MaxEmitterRate = 60, -- particles per second, summed over active emitters (also enforced)
	MaxBeams = 8,
	MaxTrails = 8,
	MaxLights = 3,
	MaxHazards = 1,
}

-- The pacing model behind the wings' `from` numbers (tests/Pacing.spec.luau). NOT used in the game.
-- Career = cumulative minutes after each career shift 1..40, the running `minutes` total of
-- design/model.luau PART 9 (career(): 30 items, 330 s clock, stage by shift number, the 250/800/2000
-- ladder, buying the cheapest next upgrade as soon as affordable, 4 s intermission per shift, medians of
-- 2000 seeded shifts). Printed by adding one print per shift inside career(); the numbers are that run's,
-- to 0.1 min. The model's durations are LOWER bounds (no reading of the summary, no walk back, no locker
-- visit), so BetweenShiftsSeconds adds an ASSUMED human overhead per shift.
Config.Pacing = {
	SpaceMinutes = { 30, 45 }, -- the owner's target for a normal player (+1 Jump's brief, applied here)
	NormalProfile = "regular",
	SlowProfile = "first-timer",
	BetweenShiftsSeconds = 10, -- [A] summary, walk back to the tray, the odd locker visit
	Career = {
		regular = { 2.8, 5.3, 8.0, 10.6, 13.1, 15.6, 18.2, 20.7, 23.1, 25.6, 28.0, 30.4, 32.9, 35.3, 37.7, 40.1,
			42.5, 44.9, 47.3, 49.7, 52.1, 54.5, 56.9, 59.3, 61.8, 64.2, 66.6, 69.0, 71.4, 73.8, 76.2, 78.6, 81.0,
			83.4, 85.8, 88.2, 90.7, 93.1, 95.5, 97.9 },
		["first-timer"] = { 4.2, 8.3, 12.7, 17.2, 21.5, 25.8, 30.0, 34.2, 38.4, 42.6, 46.9, 51.1, 55.2, 59.4, 63.5,
			67.7, 71.8, 75.9, 80.0, 84.1, 88.2, 92.3, 96.3, 100.4, 104.5, 108.6, 112.7, 116.8, 120.9, 125.0, 129.1,
			133.2, 137.2, 141.3, 145.4, 149.5, 153.6, 157.7, 161.8, 165.9 },
	},
	-- the sorter the hazard-rarity model walks (tests/SortModel.luau): design/model.luau's `regular`
	-- reactSeconds [A]: a human's delay between the ring turning red under them and starting to step out
	Sorter = { decode = 2.5, press = 0.5, carry = 3, walkSpeed = 18, cameraPitchDegrees = -20, reactSeconds = 0.4 },
}

return Config
