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

return Config
