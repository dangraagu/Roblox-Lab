--!strict
-- Config.luau — EVERY tunable for FACILITY: Endless Nightmare, in one block.
--
-- Every number here was chosen in DESIGN.md §5, and the reason for each one lives there with the
-- measurement tag it came from ([M1]..[M11] = design-measure/, [ARITH], [DOC], [STUDIO]). Do not
-- retune a survival number without re-running M4/M5: the whole difficulty curve was measured with
-- these exact values, and tests/Config.spec.luau pins them so a silent retune fails loudly.
--
-- Pure data. Requires nothing (a bare `require("./X")` is invalid in Roblox), reads no global.

local Config = {}

Config.Movement = {
	WalkSpeed = 16, -- read off a live Humanoid in Studio [REPO fork-tower/STUDIO.md §5]
	SprintSpeed = 24,
	StaminaSeconds = 4, -- a full bar = 4 s x 24 = 96 studs = 3.4 rooms [ARITH]
	StaminaRegenSeconds = 8, -- empty to full, while not sprinting
}

Config.Facility = {
	CellSize = 28, -- 1.75 s per room at walk
	WallThickness = 1, -- inside the cell; neighbours meet back to back
	CeilingHeight = 14,
	DoorWidth = 6,
	DoorHeight = 9,
	DoorOpenSeconds = 0.5,
	DoorOpenRadius = 8, -- 8 studs at 16 studs/s = the 0.5 s tween [ARITH]
	PickupRadius = 5,
	ItemWallClearance = 6, -- an item is at least this far from every wall
	ExtraDoorChance = 0.2, -- [M9]
	OnboardFuseMaxDistance = 2, -- doorways from the entry, every run's sublevel 1 [M1]
	PickupDetourSeconds = 0.9, -- model explorer only (Appendix A)
	RoomLightRange = 26,
	RoomLightBrightness = 1.6, -- [STUDIO]
	FlickerLowBrightness = 0.15, -- [STUDIO]
	MaxPartsPerRoom = 20, -- door leaves excluded
	MaxDoorLeavesPerFloor = 40,
	MaxPartsPerZone = 600,
	PropsPerRoomMax = 3,
	PropDoorClearance = 4, -- one character hull
	PropAttempts = 6,
	CenterPadHalf = 5, -- the entry car and the exit lift stand on a 10x10 centre pad
	FloorY = 0, -- top face of every floor

	-- §3. Checked in order; the first row whose `upTo` covers k wins.
	Schedule = {
		{ upTo = 3, grid = 4, fuses = 3, cells = 2 },
		{ upTo = 8, grid = 5, fuses = 4, cells = 2 },
		{ upTo = math.huge, grid = 5, fuses = 5, cells = 1 },
	},

	-- One room kit. Sizes are {x = along the wall, y, z = depth off the wall}.
	PropKit = {
		{ name = "Desk", along = 6, height = 3, depth = 3.5 },
		{ name = "Crate", along = 4, height = 4, depth = 4 },
		{ name = "Cabinet", along = 3, height = 7, depth = 3 },
		{ name = "Pipes", along = 12, height = 1, depth = 1, lift = 11 },
	},
}

Config.Front = {
	LeadSteps = 2, -- the entry ring dies at LeadSteps * step [M6]
	-- slack(k) = Smin + (S1 - Smin) * (1 + (k - 1) / K) ^ -e   [M4, M5, M6]
	SlackStart = 2,
	SlackMin = 1,
	SlackK = 4,
	SlackExponent = 1,
	FlickerSeconds = 2, -- below every measured step (min 2.34 s [M6])
	FlickerToggleSeconds = 0.2, -- the server steps Brightness every other tick
	-- An UNPOWERED elevator room goes dark this many rings after the farthest ring; a powered one never
	-- does. REVIEW-1 B3: an exit that never failed let a run stall for ever. Not measured against
	-- players: one ring is the least that keeps "every other room dies first" [ARITH].
	ExitExtraRings = 1,
}

Config.Battery = {
	CapSeconds = 45, -- [M2, M4, M5]
	CellSeconds = 15,
	DrainPerSecond = 1,
}

-- A SpotLight on the head, so it points where the player looks in LockFirstPerson [STUDIO].
Config.Flashlight = {
	Range = 40, -- from a doorway the next room's far wall is 28 studs away; Roblox caps range at 60 [DOC]
	Angle = 45, -- cone 23.2 studs wide at 28 studs [ARITH]
	Brightness = 3, -- [STUDIO]
}

Config.Exposure = {
	GraceSeconds = 4, -- [ARITH] farthest point from a doorway is 1.96 s at walk, doubled
	RecoverPerSecond = 1,
	RisePerSecond = 1,
}

Config.SecondWind = {
	BatterySeconds = 10,
}

Config.Economy = {
	PayBase = 10, -- FloorPay(k) = PayBase + PayPerSublevel * (k - 1)   [M5]
	PayPerSublevel = 5,
	DeathKeepPercent = 25, -- integer percent, so a payout is exact integer arithmetic
}

Config.Perks = {
	Order = { "deepCell", "nightEyes", "marathon", "soulAnchor", "secondWind" },
	Catalog = {
		deepCell = { name = "Deep Cell", max = 3, prices = { 25, 60, 120 }, per = 10,
			blurb = "Battery +10 s per rank" },
		nightEyes = { name = "Night Eyes", max = 3, prices = { 25, 60, 120 }, per = 1,
			blurb = "Grace in the dark +1 s per rank" },
		marathon = { name = "Marathon", max = 3, prices = { 25, 60, 120 }, per = 1,
			blurb = "Sprint +1 s per rank" },
		soulAnchor = { name = "Soul Anchor", max = 3, prices = { 25, 60, 120 }, per = 10,
			blurb = "Keep +10% of the run on death, per rank" },
		secondWind = { name = "Second Wind", max = 1, prices = { 150 }, per = 1,
			blurb = "Once per run, the dark lets you go" },
	},
}

Config.Run = {
	ServerTickSeconds = 0.1,
	StatePushSeconds = 0.2,
	BoardingSeconds = 1.5,
	RideSeconds = 4,
	DeathBeatSeconds = 2.5,
	TrustedSpeedFactor = 1.35, -- inherited from vault-runners; never measured on real replication [STUDIO]
	TrustedBurstSeconds = 3,
	TrustSubstepStuds = 0.5, -- the trusted walk is checked against walls this finely
}

Config.Apparition = {
	HideRadius = 12,
	HideAngle = 60, -- degrees off the camera's look direction [STUDIO]
	MinVisibleSeconds = 0.5,
	LifetimeSeconds = 10,
	WallOffset = 2,
}

Config.Server = {
	MinZones = 8, -- the pool is max(8, Players.MaxPlayers)
	ZoneSpacing = 400,
	RideCarOffset = 20, -- studs off the 5x5 grid's edge
	RespawnTime = 3,
}

-- The break room at the world origin. x runs spawn -> car.
Config.Hub = {
	SizeX = 60,
	SizeZ = 40,
	Height = 14,
	SpawnX = -24,
	CarX = -8, -- centre of the car interior; 16 studs ahead of the spawn
	CarDepth = 8,
	CarWidth = 10,
	ArrivalX = 12,
	ArrivalZ = 0,
	TerminalX = 12,
	-- Player.CameraMinZoomDistance, set on join. Above the PlayerModule's first-person threshold (1),
	-- so a player returning from LockFirstPerson is put back behind their character (REVIEW-1 B1).
	-- The value itself is unmeasured [STUDIO].
	CameraMinZoomDistance = 6,
}

Config.Data = {
	Store = "FacilityNightmare_v1",
	Version = 1,
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
}

Config.Hud = {
	Accent = { r = 255, g = 196, b = 92 }, -- amber, the fuse colour
	Danger = { r = 235, g = 72, b = 72 },
	Good = { r = 110, g = 220, b = 140 },
	Panel = { r = 14, g = 15, b = 20 },
}

return Config
