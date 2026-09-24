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

--============================================================================ environment (EYECANDY.md)
-- Everything below is PRESENTATION, run on the client (src/client/Env.client.luau). Nothing here is read
-- by the server, and no survival number above changed. The progress value that drives it is the
-- sublevel number k: the server's run.k, the number on the HUD and in leaderstats.Deepest. Never time.
-- tests/EnvConfig.spec.luau holds these numbers to the brief's rules: never brighter or easier to see
-- than Fx.Presets.Facility and the server's room colours (the `Base` block, checked headless against the
-- real Lighting and a real built room), nothing that looks like a fuse or a cell, hazards rare and
-- escapable, rest only between runs, budgets that add up.

local function rgb3(r: number, g: number, b: number): { number }
	return { r, g, b }
end

Config.Env = {
	HalfLifeSeconds = 0.8, -- lighting glides; the 4 s ride down is five half-lives
	LightingHz = 10, -- Lighting is written at most this often, and only on change
	DressRadius = 60, -- a built room is dressed while its centre is this close (two rooms, through two doorways)
	DressEverySeconds = 0.25,
	EmitterRadius = 32, -- particles and screens run only in rooms this close (yours and the ones you see into)
	SeamSalt = 7127,
	-- Where dressing may stand (room-local: floor top y = 0, wall inner faces at +-13, ceiling at 14):
	WallBand = 2.5, -- a wall piece lies entirely within this of a wall face (items stand >= 6 off)
	OverheadMinY = 6.5, -- anything else is overhead: a standing eye is ~4.5 [STUDIO], so it can never come between an eye and an item
	OverheadPadKeepOut = 5.5, -- overhead pieces keep out of the centre column (lift and car roofs, the fixture)
	DoorKeepOut = 4, -- below the door height, wall pieces keep this far past a doorway's edge (every wall's middle)
	FilmMaxTop = 0.2, -- water, moss, papers: at most this thick (items float at >= 0.7)
	MaxDullLuma = 190, -- a painted (non-glowing) piece is at most this bright
	MaxPartsPerRoom = 14,
	MaxScreensPerRoom = 3,
	MaxRoomEmitterRate = 10,
	-- A palette repaints the server's room parts on this client; it may change their hue and material, not how
	-- much light they give back (Dressing.paletteOk, in LINEAR light, under the flashlight's white and under the
	-- room's own light). EYECANDY.md §11: gamma luma let the void's walls return 7 % of the server's light and a
	-- server-vault door match its wall.
	ReflectanceMin = 0.6, -- every surface returns 60-100 %: on screen at least ~80 % as bright (0.6^(1/2.2)), the grade tint's allowance
	LightOutputMin = 0.9, -- the room light's colour carries 90-100 % of the server's light (a tint, not a dimmer)
	DoorContrastMin = 0.9, -- a closed door returns 1/2.6 of its wall's light in the server's room: held within
	DoorContrastMax = 1.1, -- 90-110 %, so doors are no harder (and no easier) to find than designed

	-- What the bands may never exceed. tint/brightness/contrast/saturation/atmos* = Fx.Presets.Facility;
	-- light/wall/floor/ceiling/door/fuse/cell = the colours Main.server.luau builds rooms and items with.
	Base = {
		tint = rgb3(215, 222, 235),
		brightness = -0.02,
		contrast = 0.2,
		saturation = -0.3,
		atmosColor = rgb3(40, 44, 54),
		atmosDecay = rgb3(8, 8, 12),
		light = rgb3(255, 240, 215),
		wall = rgb3(150, 158, 150),
		floor = rgb3(88, 92, 90),
		ceiling = rgb3(46, 48, 50),
		door = rgb3(96, 100, 104),
		fuse = rgb3(255, 176, 60),
		cell = rgb3(90, 230, 120),
	},

	-- The break room between runs: warm, never brighter than the facility's grade either (so any blend
	-- between the two is safe too).
	BreakRoom = {
		grade = { tint = rgb3(228, 214, 196), saturation = -0.15, contrast = 0.2, brightness = -0.02,
			atmosColor = rgb3(40, 40, 40), atmosDecay = rgb3(8, 8, 8) },
	},

	-- A band blends in over `fade` sublevels BEFORE its `from`: with fade 1.5, the last sublevel of the
	-- band before shows ~26 % of the next (a quarter of its rooms, a quarter of its colour grade).
	Bands = {
		{ id = "offices", name = "ADMIN OFFICES", from = 0, fade = 0, kit = "offices", hazards = {},
			line = "Someone left in a hurry.",
			grade = { tint = rgb3(214, 224, 196), saturation = -0.35, contrast = 0.2, brightness = -0.02,
				atmosColor = rgb3(38, 42, 36), atmosDecay = rgb3(9, 8, 6) },
			palette = { wall = rgb3(150, 152, 130), wallMaterial = "SmoothPlastic", floor = rgb3(72, 78, 96), floorMaterial = "Fabric",
				ceiling = rgb3(46, 48, 44), door = rgb3(104, 98, 86), light = rgb3(236, 246, 205) } },
		{ id = "labs", name = "LABORATORIES", from = 3, fade = 1.5, kit = "labs", hazards = { "chemLeak" },
			line = "Do not touch the samples.",
			grade = { tint = rgb3(196, 226, 232), saturation = -0.25, contrast = 0.22, brightness = -0.02,
				atmosColor = rgb3(32, 42, 54), atmosDecay = rgb3(6, 8, 12) },
			palette = { wall = rgb3(132, 158, 158), wallMaterial = "SmoothPlastic", floor = rgb3(82, 92, 94), floorMaterial = "SmoothPlastic",
				ceiling = rgb3(44, 48, 50), door = rgb3(92, 100, 104), light = rgb3(224, 245, 255) } },
		{ id = "servers", name = "SERVER VAULT", from = 5, fade = 1.5, kit = "servers", hazards = { "cableArc" },
			line = "The machines are still thinking.",
			grade = { tint = rgb3(180, 206, 245), saturation = -0.2, contrast = 0.26, brightness = -0.03,
				atmosColor = rgb3(26, 36, 62), atmosDecay = rgb3(4, 6, 14) },
			palette = { wall = rgb3(123, 133, 153), wallMaterial = "Metal", floor = rgb3(73, 77, 85), floorMaterial = "DiamondPlate",
				ceiling = rgb3(37, 39, 46), door = rgb3(78, 84, 95), light = rgb3(223, 235, 255) } },
		{ id = "flooded", name = "FLOODED MAINTENANCE", from = 7, fade = 1.5, kit = "flooded", hazards = { "pipeBurst" },
			line = "Mind the water. Mind the pipes.",
			grade = { tint = rgb3(178, 214, 200), saturation = -0.3, contrast = 0.24, brightness = -0.03,
				atmosColor = rgb3(28, 44, 42), atmosDecay = rgb3(5, 9, 8) },
			palette = { wall = rgb3(126, 136, 114), wallMaterial = "Concrete", floor = rgb3(69, 79, 74), floorMaterial = "Concrete",
				ceiling = rgb3(38, 42, 40), door = rgb3(91, 83, 71), light = rgb3(215, 240, 229) } },
		{ id = "reactor", name = "REACTOR CORE", from = 9, fade = 1.5, kit = "reactor", hazards = { "steamVent" },
			line = "It is warmer down here.",
			grade = { tint = rgb3(245, 196, 172), saturation = -0.15, contrast = 0.3, brightness = -0.04,
				atmosColor = rgb3(56, 34, 28), atmosDecay = rgb3(12, 5, 4) },
			palette = { wall = rgb3(142, 130, 125), wallMaterial = "Metal", floor = rgb3(80, 76, 73), floorMaterial = "DiamondPlate",
				ceiling = rgb3(44, 38, 36), door = rgb3(100, 82, 36), light = rgb3(255, 229, 217) } },
		{ id = "biolab", name = "OVERGROWN BIO-LAB", from = 11, fade = 1.5, kit = "biolab", hazards = { "sporePod" },
			line = "Something grew while nobody was looking.",
			grade = { tint = rgb3(186, 222, 196), saturation = -0.1, contrast = 0.24, brightness = -0.03,
				atmosColor = rgb3(28, 45, 34), atmosDecay = rgb3(5, 9, 6) },
			palette = { wall = rgb3(115, 139, 111), wallMaterial = "Concrete", floor = rgb3(67, 80, 60), floorMaterial = "Ground",
				ceiling = rgb3(36, 44, 36), door = rgb3(76, 87, 74), light = rgb3(212, 242, 216) } },
		{ id = "void", name = "THE VOID", from = 13, fade = 1.5, kit = "void", hazards = { "rift" },
			line = "There was never a sublevel this deep.",
			grade = { tint = rgb3(206, 190, 236), saturation = -0.5, contrast = 0.34, brightness = -0.05,
				atmosColor = rgb3(36, 26, 50), atmosDecay = rgb3(8, 3, 14) },
			palette = { wall = rgb3(141, 125, 173), wallMaterial = "Slate", floor = rgb3(78, 74, 95), floorMaterial = "Slate",
				ceiling = rgb3(41, 37, 50), door = rgb3(89, 79, 109), light = rgb3(238, 231, 255) } },
	},
}

-- Environmental hazards (client, src/shared/Hazards.luau). Something comes down from the ceiling onto the
-- spot the player stood on; the ring on the floor is exactly what hits. Only in LIT rooms, only on a
-- legal spot (the interior, off the car/lift pad), called off the moment the room starts to flicker. A hit
-- is a shove and a camera shake: nothing is lost, and the server never hears of it.
Config.Hazards = {
	IntervalMin = 120, -- seconds of EXPOSED time (on a sublevel, in a lit room whose band has hazards)
	IntervalMax = 180,
	MinTelegraphSeconds = 2.5,
	ReactionSeconds = 1.0, -- assumed, [STUDIO]
	PlayerRadius = 1.5,
	EscapeSpeed = 10.4, -- every warning is escapable at the SLOW proxy's speed, not only at walk
	SpotMinWallDistance = 6, -- = Facility.ItemWallClearance: the room's interior, never a doorway
	PadKeepOut = 5.5, -- the car's and the lift's 10x10 pads, and a little more
	FixtureKeepOut = 2.5, -- every other room: not under its 4x4 light fixture
	-- none in the first seconds on a sublevel: the arrival's THE POWER IS FAILING banner (3 s, the dark's own
	-- warning) and hint (6 s) have the screen, and a hazard that fell due at the lift's choice must wait
	ArrivalGraceSeconds = 6,
	Kinds = {
		chemLeak = { name = "CHEMICAL LEAK", telegraph = 3.0, burst = 0.5, hitRadius = 2.0, knock = 18, lift = 0 },
		cableArc = { name = "ARCING CABLE", telegraph = 2.8, burst = 0.4, hitRadius = 1.8, knock = 22, lift = 2 },
		pipeBurst = { name = "BURST PIPE", telegraph = 3.0, burst = 0.6, hitRadius = 2.0, knock = 20, lift = 0 },
		steamVent = { name = "STEAM VALVE", telegraph = 3.0, burst = 0.6, hitRadius = 2.0, knock = 22, lift = 1 },
		sporePod = { name = "SPORE POD", telegraph = 3.2, burst = 0.6, hitRadius = 2.2, knock = 16, lift = 0 },
		rift = { name = "RIFT", telegraph = 3.0, burst = 0.5, hitRadius = 2.0, knock = 24, lift = 3 },
	},
}

-- Rest (src/shared/Rest.luau): only between runs, in the break room. A run is a race against the blackout
-- front; nothing may pause it (Rest.validate refuses any phase of a run).
Config.Rest = {
	Phases = { hub = true },
	IdleSeconds = 20,
}

-- Client budgets, measured headless by robloxemu/check_facilitynightmare_env.luau (EYECANDY.md §6).
Config.Budget = {
	MaxLocalParts = 240, -- every BasePart the environment client has parented at once
	MaxHazardParts = 8,
	MaxHubParts = 40,
	MaxEmitters = 4, -- enabled at once, nearest first
	MaxEmitterRate = 40, -- particles per second, all enabled emitters together
	HazardEmitterRate = 10, -- a hazard's warning particles at their fastest (rooms get MaxEmitters - 1 while one is live)
	MaxScreens = 16, -- SurfaceGuis enabled at once (dressing screens only run near the player)
	MaxLights = 0, -- NO light source: glow is self-lit surfaces, off when their room is dark
	MaxHazards = 1,
}

return Config
