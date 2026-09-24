--!strict
-- Config.luau - EVERY tunable in Steal a Cryptid, in one block.
--
-- The reason behind each number lives in DESIGN.md (section named in brackets). This file
-- requires NOTHING and touches no Roblox global: it is loaded by the luau CLI specs as well as by
-- the game, so colours are {r, g, b} tables and enums are strings the server converts.

local Config = {}

-- [7] Changing it redraws every lair; Layout.reconcile refunds traps on now-invalid cells.
Config.WorldSeed = 20260916

--============================================================================ [3] the world
-- Plot-local frame: origin at the road-side front-left corner of a plot, +x across the plot,
-- +z away from the road, y = 0 at floor top. Cell (col, row) spans
--   x = CellSize * (col - 1) .. CellSize * col
--   z = ApronDepth + CellSize * row .. ApronDepth + CellSize * (row + 1)
-- Row 0 is the fence row with the gate at GateCol, rows 1..8 the yard, row 9 the cages.
Config.World = {
	CellSize = 8,
	YardCols = 9,
	YardRows = 8,
	CageRow = 9,
	CageWalkRow = 8,
	GateCol = 5,
	EntryCol = 5,
	EntryRow = 1,
	-- one cage per column, unlocked centre-out
	CageOrder = { 5, 4, 6, 3, 7, 2, 8, 1, 9 },
	FenceHeight = 10,
	RockHeight = 10,
	ApronDepth = 16,
	PlotWidth = 72,
	PlotDepth = 96,
	PlotPitch = 96,
	RoadWidth = 32,
	-- max(Plots, Players.MaxPlayers) plots are built (fork-tower's rule)
	Plots = 8,
	PocketOriginX = 4000,
	PocketPitch = 128,
	TrailheadSize = { x = 12, y = 1, z = 12 },
	TrailheadPosition = { x = 0, y = 0.5, z = 0 },
	-- where an R15 root sits over the floor it stands on (vault-runners' RunnerRootHeight)
	RootHeight = 3,
	-- apron positions, plot-local studs (x, z)
	Apron = {
		P1 = { x = 26, z = 8 },
		P2 = { x = 16, z = 8 },
		P3 = { x = 6, z = 8 },
		Arrival = { x = 36, z = 8 },
		Pad = { x = 48, z = 8 },
		Board = { x = 62, z = 8 },
	},
	PadSize = { x = 8, y = 1, z = 8 },
	-- pad half-diagonal 5.7 + a character width + replication slack
	PadReach = 12,
	-- apron objects stand 10-14 studs apart, so a prompt belongs to the object you stand at
	PromptDistance = 10,
	-- farthest apron point to any trap tile centre measured 101.98
	BuildTileDistance = 128,
	-- the board's prompt reaches 10; the other 10 let a player drift while reading the panel
	HuntStartReach = 20,
	LairFenceRows = { 3, 6 },
	LairGapsPerLine = 3,
	LairRocks = 6,
	-- part budgets asserted headless by walking the workspace
	LairPartBudget = 300,
	PocketPartBudget = 200,
	RoadPartBudget = 100,
}

--============================================================================ [4] species
-- price = rate * Economy.Payback[tier] (computed in Economy.price, never typed here).
-- `look` feeds CryptidModel: body/accent/eye colours and the per-plan proportions.
Config.Species = {
	{
		id = "jackalope", name = "Jackalope", tier = 1, plan = "quadruped", rate = 1,
		look = { body = { 176, 140, 100 }, accent = { 235, 225, 205 }, eye = { 30, 20, 20 }, scale = 0.8, antlers = true },
	},
	{
		id = "hodag", name = "Hodag", tier = 1, plan = "quadruped", rate = 2,
		look = { body = { 70, 92, 60 }, accent = { 225, 215, 190 }, eye = { 230, 60, 40 }, scale = 1.0, horns = true, ridge = true },
	},
	{
		id = "chupacabra", name = "Chupacabra", tier = 1, plan = "quadruped", rate = 3,
		look = { body = { 110, 110, 118 }, accent = { 60, 60, 66 }, eye = { 255, 60, 60 }, scale = 0.95, spines = true },
	},
	{
		id = "dogman", name = "Dogman", tier = 2, plan = "biped", rate = 12,
		look = { body = { 84, 64, 48 }, accent = { 40, 30, 24 }, eye = { 255, 200, 60 }, scale = 1.0, snout = true, ears = true },
	},
	{
		id = "jerseydevil", name = "Jersey Devil", tier = 2, plan = "winged", rate = 18,
		look = { body = { 96, 40, 36 }, accent = { 50, 24, 24 }, eye = { 255, 120, 40 }, scale = 0.9, horns = true },
	},
	{
		id = "mothman", name = "Mothman", tier = 3, plan = "winged", rate = 70,
		look = { body = { 36, 36, 44 }, accent = { 70, 66, 80 }, eye = { 255, 20, 20 }, scale = 1.15, bigEyes = true },
	},
	{
		id = "nessie", name = "Nessie", tier = 3, plan = "serpent", rate = 100,
		look = { body = { 46, 96, 88 }, accent = { 30, 70, 64 }, eye = { 240, 240, 200 }, scale = 1.0 },
	},
	{
		id = "bigfoot", name = "Bigfoot", tier = 4, plan = "biped", rate = 450,
		look = { body = { 92, 62, 40 }, accent = { 60, 40, 26 }, eye = { 20, 20, 20 }, scale = 1.35 },
	},
}

-- [4] and [13] Colour is never the only signal: the tier name is written on every cage label.
Config.Tiers = {
	{ name = "Common", color = { 150, 176, 140 } },
	{ name = "Rare", color = { 80, 150, 255 } },
	{ name = "Legendary", color = { 185, 95, 255 } },
	{ name = "Mythic", color = { 255, 200, 60 } },
}

--============================================================================ [4] economy
Config.Economy = {
	Payback = { 30, 300, 2400, 14400 },
	StartEssence = 30,
	StartCages = 3,
	MaxCages = 9,
	-- price of unlocking cage number n
	ExpansionPrice = { [4] = 150, [5] = 1500, [6] = 15000, [7] = 150000, [8] = 1500000, [9] = 6000000 },
	SellFraction = 0.5,
	JarHours = 8,
	IncomeTickSeconds = 1,
	CollectDebounceSeconds = 0.5,
	ReleaseHoldSeconds = 1.0,
	BuyTweenSeconds = 2,
}

Config.Offers = {
	Pedestals = 3,
	RerollCooldownSeconds = 30,
}

--============================================================================ [5] rival camps
-- lines: fence-line rows; gaps: gaps per line; armed: lasers per line (armed == gaps is forced).
Config.Camps = {
	{ lines = { 4 }, gaps = { 3 }, armed = { 1 }, rocks = 6, snares = 1, on = 1.0, off = 2.2, hold = 1.0 },
	{ lines = { 3, 6 }, gaps = { 2, 2 }, armed = { 2, 1 }, rocks = 6, snares = 2, on = 1.4, off = 1.9, hold = 1.5 },
	{ lines = { 3, 6 }, gaps = { 2, 2 }, armed = { 2, 2 }, rocks = 6, snares = 3, on = 1.8, off = 1.6, hold = 2.0 },
	{ lines = { 2, 4, 6 }, gaps = { 2, 1, 2 }, armed = { 2, 1, 2 }, rocks = 4, snares = 3, on = 2.2, off = 1.4, hold = 3.0 },
}

Config.Camp = {
	MaxLayoutAttempts = 32,
	Cages = 3,
	NameFirst = { "Muddy", "Crooked", "Old", "Lanky", "Grim", "Silent", "Rusty", "Lucky" },
	NameLast = { "Boots", "Hank", "Maggie", "Earl", "Dot", "Jeb", "Rosa", "Pike" },
}

Config.Raid = {
	TickSeconds = 0.1,
	WalkSpeed = 16,
	CarrySpeed = 12,
	WarnSeconds = 0.5,
	LatencyGraceSeconds = 0.2,
	TrustedSpeedFactor = 1.35,
	-- no bank: each tick moves at most speed x factor x min(dt, this). REVIEW-1 R1-4 (Trace2D.luau)
	MaxTrustedTickSeconds = 0.5,
	-- the trusted wall test lets a root this close to a wall (R15 root half-width)
	WallShrinkStuds = 1,
	-- REVIEW-1.md B1 backstop (Trace2D step 4): a trusted position that makes no progress toward a
	-- claim more than StuckStuds away for StuckSeconds has the character pulled back to it. Honest
	-- catch-up always progresses; only a freeze geometry the slide cannot undo, or a noclip, stalls.
	StuckStuds = 4,
	StuckSeconds = 1.0,
	-- a trap's danger area is its cell inset by this much towards open floor
	TrapInset = 1,
	RaidSeconds = 150,
	-- at most one raid START per player per this many seconds: bounds pocket churn (REVIEW-1 measured
	-- 491 Parts/s from a Hunt + LeaveCamp loop). Heist.spec measures the median padded tier-1 raid at
	-- 15.00 s over 300 camps, so an honest player never meets it; guards G7 measured 4 pockets in 10 s
	RestartCooldownSeconds = 3,
	PermitFraction = 0.10,
	-- human model for the solver: every ON window padded this much on both sides
	HumanPad = 0.3,
	-- the grab prompt's anchor: over the grab cell's centre, at root height
	AnchorHeight = 3,
	-- a grab press that reaches the server before its trusted position reaches the grab spot waits
	-- this long for it to arrive (five raid ticks; the position lags a claim by at most one)
	HoldAskSeconds = 0.5,
	-- REVIEW-1.md B2: the server grabs when the trusted position is within GrabReach of the anchor on
	-- the flat, and the prompt reaches exactly as far, so the prompt shows where a grab works and
	-- nowhere else. 5 covers the whole cage front (z 87: hypot(4, 3) = 5) and 98 % of the cell; the
	-- 4.25 before it missed 12-14 % of the cell and showed 0.25 studs past it, where grabs were refused
	GrabReach = 5,
	GrabPromptDistance = 5,
}

--============================================================================ [6] defense
Config.Traps = {
	LaserPrice = 250,
	SnarePrice = 100,
	MaxLasers = 4,
	MaxSnares = 6,
	RefundFraction = 1.0,
	LairLaserOn = 1.4,
	LairLaserOff = 1.9,
	-- build mode rebuilds its tiles when it switches ON, so it switches on at most once a second
	BuildOnCooldownSeconds = 1,
}

Config.Poacher = {
	FirstAfterSeconds = 300,
	MinCryptids = 2,
	IntervalMin = 180,
	IntervalMax = 240,
	WarningSeconds = 10,
	Speed = 10,
	HoldSeconds = 2,
	PathLaserCost = 5,
	Caution = 0.6,
	TheftFraction = 0.5,
	BountySeconds = 30,
	BountyMin = 10,
	TickSeconds = 0.1,
}

--============================================================================ [8] data
Config.Save = {
	Enabled = true,
	Store = "StealACryptid_v1",
	FlushTickSeconds = 7,
	AutosaveSeconds = 60,
	LockSeconds = 120,
	-- a load is tried this many times, waiting LoadRetrySeconds x attempt between tries (1 s, 2 s),
	-- before the session falls back to not saving. REVIEW-1: one transient failure used to be final.
	LoadAttempts = 3,
	LoadRetrySeconds = 1,
	-- REVIEW-1.md A1: a record another server still holds is re-read every LockRetrySeconds for up to
	-- LockWaitSeconds at join (the old server's leave-write usually lands in a few seconds), and a
	-- session that still started unsaved re-checks every LockRecheckSeconds for a lock that lapsed
	LockWaitSeconds = 15,
	LockRetrySeconds = 5,
	LockRecheckSeconds = 15,
	-- a write that must go after the one in flight (the grant, a leave) waits at most this long;
	-- after that the in-flight write is treated as lost and this one reports failure
	WriteQueueSeconds = 60,
}

Config.Remotes = {
	MaxPerSecond = 8,
	SlowDownToastSeconds = 5,
}

Config.Tutorial = {
	CollectHintJar = 5,
}

--============================================================================ [13] visuals
-- Fx.Presets.Horror with four overrides (FogStart/FogEnd 40/220, Saturation -0.10, bloom
-- Threshold 0.95, no depth of field). Colours as {r,g,b}; the server builds the Color3 table.
Config.Lighting = {
	lighting = {
		Technology = "Future",
		Ambient = { 20, 22, 30 },
		OutdoorAmbient = { 15, 18, 28 },
		Brightness = 1,
		ExposureCompensation = -0.15,
		ClockTime = 0.2,
		FogStart = 40,
		FogEnd = 220,
		FogColor = { 12, 14, 22 },
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.4,
	},
	atmosphere = { Density = 0.42, Offset = 0.1, Color = { 90, 100, 120 }, Decay = { 30, 34, 46 }, Glare = 0.1, Haze = 1.6 },
	bloom = { Intensity = 0.5, Size = 24, Threshold = 0.95 },
	colorCorrection = { Brightness = -0.02, Contrast = 0.18, Saturation = -0.10, TintColor = { 200, 210, 235 } },
}

Config.Hud = {
	Accent = { 150, 230, 170 },
	Danger = { 255, 80, 80 },
	Gold = { 255, 205, 90 },
	Panel = { 18, 22, 28 },
}

--============================================================================ [13b] the night (EYECANDY.md)
-- Client-only eye candy: src/client/Night.client.luau + src/shared/NightArt.luau, rules in
-- src/shared/Night.luau (tests/Night.spec.luau, tests/NightConfig.spec.luau). The server builds none of
-- it and trusts none of it.
--
-- HOME is named by the Journal's rank (Economy.rank, the highest tier ever owned; the server reports it
-- in State.rank): the rarer your collection, the deeper the night over Pine Hollow. A CAMP is its own
-- place, named by the camp's tier. Every band keeps the readability floor (Night.readable): never darker
-- or foggier than Config.Lighting above, never less saturated, bloom never harder to trigger, no depth
-- of field. ClockTime is in NIGHT HOURS (18 = 6 pm, 24 = midnight, 27 = 3 am; the client writes h % 24)
-- and stays inside 17.5..30, so a glide between two bands never passes through daylight.
Config.Night = {
	HalfLife = 0.6,          -- seconds: every written value glides; a teleport or a new rank never cuts
	LightingHz = 10,         -- Lighting written at most 10 times a second, only on change
	-- The world's edge at home: the server's Ground is the only floor, so the local far forest floor starts
	-- past a ravine round it (Night.farGroundRects), never at walking height beside it (EYECANDY section 13).
	Ravine = {
		Width = 24,       -- studs from the Ground's edge to the far floor: well over twice a running jump (8.5)
		Depth = 80,       -- the cliff faces on both sides of it drop this far (a drop, not a step)
		FarHalf = 1024,   -- the far floor reaches this far from the road's centre (the old 2 048-stud floor)...
		MinFar = 200,     -- ...or this far past the ravine, on a road longer than that (50 players: 2 520 studs)
		PineMargin = 36,  -- far pines stand at least this far past the edge (Width + a pine's 8.4-stud radius, + slack)
	},
	-- Nothing local may stand between the camera and what the player must see (NightArt:occlude): in a camp,
	-- the camp; at home, a box this many studs round the player's root (the character, with room to spare).
	HomeViewRadius = 4,
	CampMargin = 8,          -- camp scenery and critters keep this far outside the camp's fences
	CameraCorridorHalfWidth = 30, -- and out of the corridor behind the gate, where the raider's camera is
	CameraCorridorDepth = 70,

	Home = {
		{
			id = "dusk", from = 0, fade = 0, name = "Dusk", sub = "Pine Hollow at sundown",
			lighting = { ClockTime = 18.15, Brightness = 1.8, ExposureCompensation = 0, Ambient = { 70, 58, 66 },
				OutdoorAmbient = { 112, 86, 94 }, FogStart = 60, FogEnd = 600, FogColor = { 196, 122, 110 },
				EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.4 },
			atmosphere = { Density = 0.32, Offset = 0.12, Color = { 236, 160, 128 }, Decay = { 120, 66, 110 }, Glare = 0.7, Haze = 1.3 },
			sky = { StarCount = 300, MoonAngularSize = 14, SunAngularSize = 26 },
			bloom = { Intensity = 0.7, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.06, TintColor = { 255, 226, 206 } },
			sunRays = { Intensity = 0.12, Spread = 0.6 },
			pieces = { "farGround", "ridges", "farPines" },
			ambient = { { kind = "crow", count = 3 } },
			weather = { kind = "fireflies", rate = 5 },
			hazards = { "crow" },
		},
		{
			id = "moonrise", from = 2, fade = 0, name = "Moonrise", sub = "A Rare cryptid stirs the woods",
			lighting = { ClockTime = 20.4, Brightness = 1.4, ExposureCompensation = 0.05, Ambient = { 50, 58, 88 },
				OutdoorAmbient = { 66, 80, 122 }, FogStart = 50, FogEnd = 480, FogColor = { 40, 52, 92 },
				EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.45 },
			atmosphere = { Density = 0.34, Offset = 0.1, Color = { 110, 126, 176 }, Decay = { 60, 64, 120 }, Glare = 0.3, Haze = 1.4 },
			sky = { StarCount = 1500, MoonAngularSize = 26, SunAngularSize = 21 },
			bloom = { Intensity = 0.8, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.16, Saturation = 0.02, TintColor = { 220, 230, 255 } },
			sunRays = { Intensity = 0.04, Spread = 0.4 },
			pieces = { "farGround", "ridges", "farPines", "owls" },
			ambient = { { kind = "bat", count = 6 } },
			weather = { kind = "mist", rate = 3 },
			hazards = { "bat", "crow" },
		},
		{
			id = "strange", from = 3, fade = 0, name = "Strange Lights", sub = "Legendary lights over the ridge",
			lighting = { ClockTime = 23.7, Brightness = 1.3, ExposureCompensation = 0.1, Ambient = { 42, 66, 72 },
				OutdoorAmbient = { 58, 98, 98 }, FogStart = 60, FogEnd = 520, FogColor = { 30, 60, 64 },
				EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.5 },
			atmosphere = { Density = 0.3, Offset = 0.1, Color = { 90, 170, 150 }, Decay = { 80, 40, 130 }, Glare = 0.2, Haze = 1.2 },
			sky = { StarCount = 3000, MoonAngularSize = 22, SunAngularSize = 21 },
			bloom = { Intensity = 1.0, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.18, Saturation = 0.08, TintColor = { 210, 255, 235 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "farGround", "ridges", "farPines", "owls", "auroraGreen" },
			ambient = { { kind = "wisp", count = 5 }, { kind = "redEyes", count = 4 }, { kind = "bat", count = 3 } },
			weather = { kind = "wisplights", rate = 6 },
			hazards = { "wisp", "bat" },
		},
		{
			id = "mythic", from = 4, fade = 0, name = "Mythic Night", sub = "Bigfoot walks Pine Hollow",
			lighting = { ClockTime = 26.8, Brightness = 1.35, ExposureCompensation = 0.1, Ambient = { 66, 56, 76 },
				OutdoorAmbient = { 98, 84, 112 }, FogStart = 60, FogEnd = 560, FogColor = { 60, 40, 70 },
				EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.5 },
			atmosphere = { Density = 0.3, Offset = 0.1, Color = { 200, 160, 120 }, Decay = { 120, 60, 140 }, Glare = 0.4, Haze = 1.2 },
			sky = { StarCount = 4500, MoonAngularSize = 30, SunAngularSize = 21 },
			bloom = { Intensity = 1.2, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.2, Saturation = 0.12, TintColor = { 255, 236, 214 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "farGround", "ridges", "farPines", "owls", "auroraGold", "ufos", "bigfoot" },
			ambient = { { kind = "meteor", count = 3 }, { kind = "wisp", count = 4 }, { kind = "redEyes", count = 2 } },
			weather = { kind = "stardust", rate = 6 },
			hazards = { "meteorite", "wisp" },
		},
	},

	-- One place per camp tier (progress = tier - 1). No hazards here, ever: a knock in a camp would
	-- decide a raid. Camp weather hangs behind the back fence (`at = "campBack"`), never over the yard.
	Camp = {
		{
			id = "badlands", from = 0, fade = 0, name = "Badlands Camp", sub = "Common camp",
			lighting = { ClockTime = 21.6, Brightness = 1.5, ExposureCompensation = 0.05, Ambient = { 62, 52, 50 },
				OutdoorAmbient = { 94, 78, 72 }, FogStart = 60, FogEnd = 700, FogColor = { 70, 50, 60 },
				EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.4 },
			atmosphere = { Density = 0.24, Offset = 0.1, Color = { 180, 130, 110 }, Decay = { 90, 60, 90 }, Glare = 0.3, Haze = 1.0 },
			sky = { StarCount = 3500, MoonAngularSize = 18, SunAngularSize = 21 },
			bloom = { Intensity = 0.7, Size = 24, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.16, Saturation = 0, TintColor = { 255, 232, 214 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "campSand", "mesas", "cacti" },
			ambient = { { kind = "tumbleweed", count = 3 }, { kind = "bat", count = 2 } },
			hazards = {},
		},
		{
			id = "barrens", from = 1, fade = 0, name = "Pine Barrens Camp", sub = "Rare camp",
			lighting = { ClockTime = 23, Brightness = 1.3, ExposureCompensation = 0.05, Ambient = { 42, 52, 58 },
				OutdoorAmbient = { 58, 76, 86 }, FogStart = 50, FogEnd = 420, FogColor = { 30, 40, 48 },
				EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.4 },
			atmosphere = { Density = 0.36, Offset = 0.1, Color = { 100, 120, 130 }, Decay = { 40, 50, 60 }, Glare = 0.1, Haze = 1.4 },
			sky = { StarCount = 2000, MoonAngularSize = 16, SunAngularSize = 21 },
			bloom = { Intensity = 0.8, Size = 24, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.01, Contrast = 0.18, Saturation = 0, TintColor = { 215, 230, 240 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "campNeedles", "pineRing" },
			ambient = { { kind = "bat", count = 4 } },
			weather = { kind = "fireflies", rate = 3, at = "campBack" },
			hazards = {},
		},
		{
			id = "loch", from = 2, fade = 0, name = "Loch Shore Camp", sub = "Legendary camp",
			lighting = { ClockTime = 24.8, Brightness = 1.4, ExposureCompensation = 0.1, Ambient = { 48, 60, 76 },
				OutdoorAmbient = { 72, 92, 120 }, FogStart = 60, FogEnd = 520, FogColor = { 54, 70, 96 },
				EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.55 },
			atmosphere = { Density = 0.33, Offset = 0.1, Color = { 130, 150, 190 }, Decay = { 60, 70, 110 }, Glare = 0.2, Haze = 1.3 },
			sky = { StarCount = 2500, MoonAngularSize = 24, SunAngularSize = 21 },
			bloom = { Intensity = 0.9, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.18, Saturation = 0.02, TintColor = { 220, 232, 255 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "campShore", "loch", "castle", "nessie" },
			ambient = { { kind = "bat", count = 2 } },
			weather = { kind = "mist", rate = 3, at = "campBack" },
			hazards = {},
		},
		{
			id = "redwoods", from = 3, fade = 0, name = "Redwood Camp", sub = "Mythic camp",
			lighting = { ClockTime = 27.2, Brightness = 1.3, ExposureCompensation = 0.1, Ambient = { 48, 62, 56 },
				OutdoorAmbient = { 72, 96, 84 }, FogStart = 50, FogEnd = 440, FogColor = { 60, 74, 70 },
				EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.45 },
			atmosphere = { Density = 0.4, Offset = 0.1, Color = { 160, 180, 170 }, Decay = { 60, 80, 70 }, Glare = 0.1, Haze = 1.5 },
			sky = { StarCount = 1500, MoonAngularSize = 20, SunAngularSize = 21 },
			bloom = { Intensity = 0.9, Size = 28, Threshold = 0.88 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.2, Saturation = 0, TintColor = { 225, 245, 232 } },
			sunRays = { Intensity = 0, Spread = 0.3 },
			pieces = { "campFerns", "redwoods", "bigfootGlimpse" },
			ambient = { { kind = "wisp", count = 3 } },
			weather = { kind = "mist", rate = 4, at = "campBack" },
			hazards = {},
		},
	},

	-- Ambient life: never dangerous, never collidable. Distances in studs from the camera (y too), except
	-- `ground`, an absolute height for things that roll along the floor. In a camp every critter keeps
	-- out of Night.keepOut (the yard and the camera corridor) and is recycled if it wanders in.
	Critters = {
		crow = { rMin = 90, rMax = 260, yMin = 25, yMax = 70, speedMin = 14, speedMax = 22, flock = 3 },
		bat = { rMin = 40, rMax = 170, yMin = 14, yMax = 45, speedMin = 16, speedMax = 26, flock = 3 },
		wisp = { rMin = 30, rMax = 130, yMin = -4, yMax = 6, speedMin = 2, speedMax = 5 },
		redEyes = { rMin = 70, rMax = 150, yMin = -6, yMax = 0, speedMin = 0.5, speedMax = 1.2 },
		meteor = { rMin = 500, rMax = 1200, yMin = 250, yMax = 600, speedMin = 260, speedMax = 380 },
		tumbleweed = { rMin = 70, rMax = 200, yMin = 0, yMax = 0, ground = 0.3, speedMin = 6, speedMax = 11 },
	},

	-- Hazards: RARE, telegraphed, one at a time, and only at HOME (never in a camp, never before the
	-- tutorial is done, never with a poacher about, never with the Hunt panel or build mode open, never
	-- near the ground's edge). They only ever harm the local player, so they run on the client; a hit is
	-- a stumble (PlatformStand + a push). Nothing is lost. The clock runs only while the gate is open and
	-- the player is not resting (frozen, never reset). The red ring IS the danger zone: step out of it.
	Hazards = {
		IntervalMin = 120,
		IntervalMax = 180,
		MinTelegraphSeconds = 3,
		MinCommitSeconds = 1.5,
		MaxRetargetSpeed = 1.5,
		PlayerRadius = 1.5,
		AimJitter = 1.0,
		SpreadDegrees = 35,       -- a lane starts within +-35 degrees of where the camera looks ...
		ViewPitchDegrees = 20,    -- ... and +-20 degrees of its pitch: it starts ON SCREEN
		KindFitDegrees = 25,
		KnockLift = 8,            -- studs/s up on a hit: a stumble, never a launch
		KnockSeconds = 0.9,       -- PlatformStand after a hit
		NearMissStuds = 8,        -- for measurement: passing within 8 studs is a near-hit
		AfterTutorial = 4,        -- hazards start once State.tutorial reaches this (after the first steal)
		SettleSeconds = 8,        -- after the gate reopens (home from a raid, a panel closed) wait this long
		EdgeMarginStuds = 33,     -- no launch within this of the ground's edge: a knock never pushes anyone off
		                          -- (>= the hardest knock 34 x KnockSeconds 0.9 + PlayerRadius, frictionless)
		-- the camera looks DOWN at a player on the ground: a launch waits while it looks down more than this,
		-- and the lane's window never dips below the horizon (Night.hazardPitch), so nothing starts underground
		MaxLookDownDegrees = 40,
		-- how a hazard is DRAWN (Night.drawPosition; the hit rule stays the lane's): after it arrives a flier
		-- swoops up and away at SwoopDegrees instead of flying on into the ground (an `impact` kind ends at
		-- the ground), and it rises over a player who has left the ring so its centre stays ClearStuds away
		SwoopDegrees = 35,
		ClearStuds = 4.5,
		Kinds = {
			crow = { label = "Crow", speed = 26, telegraph = 3.2, commit = 1.5, pass = 3.0, hitRadius = 1.8, knock = 30, pitch = 14, pitchSpread = 8 },
			bat = { label = "Bat", speed = 22, telegraph = 3.2, commit = 1.6, pass = 3.0, hitRadius = 2.0, knock = 28, pitch = 10, pitchSpread = 8 },
			wisp = { label = "Will-o'-wisp", speed = 12, telegraph = 3.6, commit = 2.0, pass = 4.0, hitRadius = 1.8, knock = 24, pitch = 4, pitchSpread = 4 },
			meteorite = { label = "Meteorite", speed = 40, telegraph = 3.2, commit = 1.7, pass = 2.5, hitRadius = 2.2, knock = 34, pitch = 28, pitchSpread = 8, impact = true },
		},
	},

	-- Rest: the HUD's Rest toggle, or standing still IdleSeconds. Critters leave you alone; nothing else
	-- changes: poachers still come, jars fill as always, a camp's clock is never paused (rest is refused
	-- in a camp, and a raid's teleport wakes you). It cannot start in the air or with a hazard inbound.
	Rest = {
		IdleSeconds = 20,
		RequireGrounded = true,
		BlockWhileThreat = true,
		WakeOnMove = true,
		WakeGraceSeconds = 0.4,
		PendingSeconds = 10,      -- longest hazard flight (7.6 s) + 2.4 s to stand still
	},

	-- Mobile budget for everything the client builds (measured in robloxemu/check_stealacryptid_night.luau
	-- at every band, every camp and every seam). The server builds none of it.
	Budget = {
		MaxLocalParts = 200,
		MaxEmitters = 4,
		MaxWeatherEmitters = 2,   -- enforced with EnvBands.capRates
		MaxHabitatEmitters = 1,   -- only the rarest habitat in your lair gets particles
		MaxEmitterRate = 40,      -- particles per second, summed over what is on
		MaxWeatherRate = 24,      -- of which weather (the rest: one habitat 4/s + the campfire 8/s)
		MaxBeams = 8,
		MaxTrails = 6,
		MaxLights = 3,
		MaxHazards = 1,
	},

	-- Your own cages get a habitat patch per species (other lairs keep the plain cage: budget).
	Habitats = {
		Species = {
			jackalope = "prairie", hodag = "northwoods", chupacabra = "desert", dogman = "moonfield",
			jerseydevil = "barrens", mothman = "bridge", nessie = "loch", bigfoot = "rainforest",
		},
		GlowTransparency = { 0.72, 0.58, 0.44, 0.3 }, -- per tier: the rarer, the brighter the rim
		EmitterRate = 4,          -- particles/s of the one lit habitat
	},

	-- The campfire that appears beside a resting player (local; others see you sit, not the fire).
	Campfire = { Rate = 8, LightRange = 14, LightBrightness = 1.6 },

	-- The HUD chip (Hud.client's RaidChip slot, via its NightBus) and the Rest toggle. ASCII only.
	Text = {
		Incoming = "%s incoming from %s",
		Locked = "Move! Leave the red ring - %s",
		Resting = "Resting - poachers still come",
		Idle = "Idle - critters leave you alone",
		Queued = "Rest starts when the sky is clear",
		RestButton = "Rest",
		RestingButton = "Resting",
		QueuedButton = "Rest...",
		ChipMaxChars = 44,
	},
}

return Config
