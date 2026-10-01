--!strict
-- Config.luau — EVERY tunable for SIGNAL LOST: Derelict Station, in one block.
--
-- Every number here was chosen in DESIGN.md, and the reason for each one lives there with the tag it came
-- from ([M1]..[M9] = design-measure/, [ARITH], [DOC], [REPO], [STUDIO]). Do not retune a survival or
-- pacing number without re-running tests/Pacing.spec.luau: the brag's minutes were measured with these
-- exact values, and tests/Config.spec.luau pins them so a silent retune fails loudly.
--
-- Pure data plus two tiny lookups. Requires nothing (a bare `require("./X")` is invalid in Roblox).

local Config = {}

--============================================================================ §8.1 the station
Config.Station = {
	CellSize = 32, -- one module; the schedule was tuned at 32 [M2]
	WallThickness = 1, -- inside the cell: neighbours meet back to back [REPO facility-nightmare]
	CeilingHeight = 18, -- above the vacuum hop's apex (9) + an avatar + 4 [ARITH]
	HatchWidth = 8,
	HatchHeight = 10,
	HatchOpenRadius = 8, -- 0.5 s at 16 studs/s: a walker arrives as the hatch finishes opening [ARITH]
	HatchSeconds = 0.5,
	LeafThickness = 0.6,
	PickupRadius = 5, -- horizontal
	PickupHeightWindow = 4, -- the root part within 4 studs of the item's height
	ItemWallClearance = 6, -- an item stands at least this far off every wall
	SalvageHeightMin = 3,
	SalvageHeightMax = 8,
	CanisterHeight = 3.5,
	StandHeight = 2.51, -- a standing root part above the surface it stands on [REPO SPAWN-ORDER §2]
	SpliceRadius = 6, -- from the relay mast in the module centre
	FloorHatchRadius = 2.5, -- stand this close to the open floor hatch to drop into the next sector
	FloorHatchOffset = 12, -- the floor hatch sits in the relay module's (+x, +z) corner, off every doorway line and out of the item square (|x|, |z| <= 9)
	ConsoleRadius = 10, -- a fabricator or RETURN console works within this many studs (trusted position)
	ExtraDoorChance = 0.2, -- [M2]
	RelayDepthFrac = 0.75, -- relay candidates: air modules with doorway distance >= ceil(0.75 maxD) [M2, M9]
	MaxPartsPerModule = 20, -- hatch leaves counted apart
	MaxPartsPerZone = 900,
	ModuleLightRange = 30,
	ModuleLightBrightness = 1.6, -- [STUDIO]
	VacuumLightBrightness = 0.7, -- the dim red emergency light [STUDIO]
	SplicedLightBrightness = 2.2, -- the payoff: every built module's light at full [STUDIO]
}

--============================================================================ movement
Config.Move = {
	AirWalkSpeed = 16, -- read off a live Humanoid in Studio [REPO fork-tower/STUDIO.md §5]
	VacWalkSpeed = 12, -- +1 per Mag-Boots rank [M2]
	BootsStep = 1,
	AirJumpHeight = 7.2, -- Roblox's default [REPO]
	VacJumpHeight = 1.8, -- a 9-stud apex under 20 % gravity [ARITH] [STUDIO]
	VacGravityFactor = 0.2, -- the client lifts 80 % of its weight with a VectorForce in vacuum [STUDIO]
}

--============================================================================ §8.2 air
Config.Air = {
	TankBase = 20, -- [M2]
	TankStep = 5, -- per Air Tank rank [M5]
	RefillSeconds = 2, -- empty to full in any air module, whatever the tank [M2: a feel number]
	GraceSeconds = 5, -- hypoxia before the blackout [M2]
	CanisterSeconds = 10,
	LowO2Seconds = 10, -- no hazard starts below this much air
	-- Air.vacuumCharge (REVIEW-1 finding 1): vacuum seconds already paid while covering less ground cover a later
	-- burst of trusted distance, at most this much, so a replication stall is never paid twice. A script gains at
	-- most this much per vacuum stretch, and only if it stood still that long first.
	CreditSeconds = 1,
}

--============================================================================ §8.3 the signal and the run
Config.Signal = {
	MaxBars = 5,
	MinBars = 1,
}

Config.Run = {
	SpliceSeconds = 2,
	TransitSeconds = 3,
	BoardingSeconds = 1.0,
	BlackoutBeatSeconds = 2.5,
	LiftCooldownSeconds = 4, -- after a refused boarding, before the lift tries again
}

Config.Brag = {
	Sector = 30, -- relay 30 is the Main Array [M3]
	EchoSector = 60, -- THE ECHO begins
}

--============================================================================ §8.4 server, zones, data
Config.Server = {
	TickSeconds = 0.1,
	StatePushSeconds = 0.2,
	TrustedSpeedFactor = 1.35, -- [REPO vault-runners, facility-nightmare] [STUDIO]
	TrustedBurstSeconds = 3,
	TrustSubstepStuds = 2,
	MaxPlayers = 8,
	Zones = 8, -- max(8, Players.MaxPlayers) at runtime
	ZoneSpacing = 400, -- zone i at (400 i, 0, 0), the lifeboat at the origin
	PodOffset = 44, -- the transit pod stands this far past the grid's -z edge, out of sight
	RespawnTime = 3,
}

Config.Data = {
	Store = "SignalLost_v1",
	Version = 1,
	AutosaveSeconds = 20,
	SessionLockSeconds = 45,
}

--============================================================================ §3 the difficulty schedule
-- The first row whose `upTo` covers k wins. Rows with `deep = true` use Config.Deep's formulas.
Config.Schedule = {
	{ upTo = 1, n = 3, breach = 0.35, reach = 1, salvage = 2, canisters = 1, onboard = true },
	{ upTo = 2, n = 3, breach = 0.35, reach = 1, salvage = 2, canisters = 1 },
	{ upTo = 4, n = 4, breach = 0.45, reach = 2, salvage = 3, canisters = 1 },
	{ upTo = 9, n = 4, breach = 0.55, reach = 2, salvage = 3, canisters = 1 },
	{ upTo = 15, n = 5, breach = 0.60, reach = 3, salvage = 4, canisters = 2 },
	{ upTo = 22, n = 5, breach = 0.65, reach = 3, salvage = 4, canisters = 2 },
	{ upTo = 30, n = 6, deep = true, salvage = 5, canisters = 2 },
	{ upTo = math.huge, n = 6, deep = true, salvage = 5, canisters = 1 },
}

-- From the Array Spine on, air pockets thin toward 0.95 and vacuum stretches grow to 10 hatches.
Config.Deep = {
	From = 23,
	BreachMax = 0.95,
	BreachSpan = 0.30,
	BreachDecay = 0.97,
	ReachBase = 4,
	ReachEvery = 8,
	ReachMax = 10,
}

-- The schedule row for sector k, with the deep formulas resolved. A fresh table.
function Config.scheduleFor(k: number): any
	local kk = math.max(1, math.floor(tonumber(k) or 1))
	for _, r in Config.Schedule do
		if kk <= r.upTo then
			local out = table.clone(r)
			if r.deep then
				local D = Config.Deep
				out.breach = D.BreachMax - D.BreachSpan * D.BreachDecay ^ (kk - D.From)
				out.reach = math.min(D.ReachMax, D.ReachBase + (kk - D.From) // D.ReachEvery)
			end
			out.upTo = nil
			out.deep = nil
			return out
		end
	end
	error("no schedule row for sector " .. tostring(k))
end

--============================================================================ §9 economy
Config.Economy = {
	ValueBase = 5, -- value(k) = 5 + (k - 1) per salvage piece
	ValuePerSector = 1,
	BonusBase = 10, -- bonus(k) = 10 + 2 (k - 1) on the splice
	BonusPerSector = 2,
	KeepNumerator = 1, -- a sector left unspliced banks floor(carried x 1 / 2), integer arithmetic
	KeepDenominator = 2,
}

Config.Upgrades = {
	Order = { "tank", "boots" },
	Catalog = {
		tank = { name = "AIR TANK", max = 4, prices = { 120, 300, 600, 1000 }, per = 5,
			blurb = "+5 s of air per rank" },
		boots = { name = "MAG-BOOTS", max = 4, prices = { 120, 300, 600, 1000 }, per = 1,
			blurb = "+1 stud/s in vacuum per rank" },
	},
	Recommended = "tank", -- when both next ranks cost the same (M5: the tank buys the most survival)
	BuyCooldownSeconds = 0.5,
}

--============================================================================ §2.8 the lifeboat
Config.Hub = {
	SizeX = 60,
	SizeZ = 40,
	Height = 16,
	SpawnX = 4, -- HubSpawn faces +X
	LiftX = 16, -- 12 studs ahead of the spawn [ARITH: 0.75 s at 16]
	LiftSize = 8,
	ArrivalX = -8, -- where a player lands coming home
	ArrivalZ = 0,
	BoardX = 29.4, -- on the wall HubSpawn faces
	BoardZ = 9,
	FabX = 20,
	FabZ = -18.4,
	BenchXs = { -8, -18 },
	WindowZ = 20, -- the planet window on the north wall
}

--============================================================================ §10 the board
Config.Board = {
	Store = "SignalLost_Relays_v1",
	WriteMinSeconds = 60, -- at most one ordered write per player per minute, plus on leaving
	PublicRows = 10,
	PublicCacheSeconds = 60,
	FriendsRows = 10,
	FriendsCap = 200,
	FriendsCacheSeconds = 600, -- the viewer's list
	ScoreCacheSeconds = 300, -- a friend's score, server-wide
	ReadsBurst = 40,
	ReadsPerSecond = 1,
	BudgetReserve = 20, -- never starve profile loads [DOC GetRequestBudgetForRequestType]
	MaxMetric = 4000000, -- best x 2e9 stays an exact integer below 2^53
	PromptDistance = 10,
	ToggleCooldownSeconds = 2,
	Star = "★", -- beside every name with best >= StarAt (photographed rendering in Studio)
	StarAt = 30, -- the Main Array (Config.Brag.Sector)
	Text = {
		Title = "RELAYS RESTORED",
		EmptyPublic = "No relays restored yet. Relay 1 takes about half a minute — be the first.",
		FriendsFailed = "Couldn't load your Roblox friends right now. Try again in a minute.",
		NoFriends = "No Roblox friends yet. Friends you add show up here, ranked against you.",
		FriendsNoScores = "None of your %d friends has restored a relay yet. Relay 1 takes about half a minute — invite one.",
		FriendsChecking = "Checking friends %d of %d…",
		Loading = "Loading…",
		Prompt = "Public / Friends",
	},
}

--============================================================================ HUD
Config.Hud = {
	Accent = { r = 120, g = 200, b = 255 },
	Good = { r = 90, g = 230, b = 130 },
	Danger = { r = 255, g = 80, b = 70 },
	Warn = { r = 255, g = 190, b = 70 },
	Panel = { r = 14, g = 18, b = 28 },
	Text = { r = 232, g = 236, b = 244 },
	Muted = { r = 150, g = 158, b = 176 },
}

-- The four signal colours (§4.3): nothing else that glows may come within 30 degrees of hue of them.
Config.SignalColors = {
	Salvage = { 255, 176, 48 },
	Canister = { 70, 225, 255 },
	HatchVacuum = { 255, 45, 35 },
	HatchAir = { 50, 235, 90 },
}

--============================================================================ §4 environment bands (client)
-- `from` is in progress units p = (k - 1) + visited / n^2 (§4.1); the band NAME follows the integer sector.
-- `first`/`last` are the sectors the band covers. grade = ColorCorrection + Atmosphere on this client;
-- palette = what the client repaints the server's modules with (60-100 % of the server's light, §4.3);
-- kit = the dressing kit (Dressing.luau); weather = one particle kind; critters and exterior are EnvArt's.
Config.Env = {
	HalfLifeSeconds = 0.6, -- the grade glides; five half-lives inside the 3 s ride [ARITH]
	LightingHz = 10,
	DressRadius = 80, -- modules within this of the player are dressed
	DressEverySeconds = 0.25,
	ExteriorFollowStuds = 2, -- in a sector the exterior follows the character overhead (EnvArt.LAYOUT)
	EmitterRadius = 48,
	WeatherRate = 6,
	-- The server's own module colours, which every palette is measured against (§4.3).
	ServerWall = { 176, 182, 194 },
	ServerFloor = { 96, 100, 110 },
	ServerTrim = { 120, 126, 138 },
	Lifeboat = {
		grade = { tint = { 238, 242, 255 }, saturation = 0, contrast = 0.1, brightness = 0,
			atmosColor = { 120, 140, 170 }, atmosDecay = { 40, 50, 70 } },
	},
	Bands = {
		{
			id = "docking", name = "DOCKING RING", first = 1, last = 4, from = 0, fade = 1,
			line = "The ring still turns. Nothing answers.",
			grade = { tint = { 226, 238, 255 }, saturation = -0.05, contrast = 0.12, brightness = 0,
				atmosColor = { 150, 175, 210 }, atmosDecay = { 70, 90, 130 } },
			palette = { wall = { 170, 178, 191 }, floor = { 92, 98, 110 }, trim = { 73, 122, 207 } },
			kit = "docking",
			weather = { kind = "frost", color = { 225, 238, 255 }, size = 0.12 },
			critters = { kind = "tools", where = "vacuum", color = { 170, 176, 186 }, glow = false },
			exterior = { phase = "day", planet = { 70, 130, 220 }, rim = { 200, 225, 255 }, sun = true },
			hazards = {},
		},
		{
			id = "hydro", name = "HYDROPONICS", first = 5, last = 9, from = 4, fade = 1,
			line = "The farms kept growing without anyone.",
			grade = { tint = { 222, 250, 226 }, saturation = 0.05, contrast = 0.1, brightness = 0,
				atmosColor = { 150, 200, 160 }, atmosDecay = { 60, 110, 80 } },
			palette = { wall = { 152, 178, 152 }, floor = { 80, 99, 85 }, trim = { 83, 129, 83 } },
			kit = "hydro",
			weather = { kind = "mist", color = { 210, 240, 220 }, size = 0.25 },
			critters = { kind = "moths", where = "air", color = { 214, 255, 150 }, glow = true },
			exterior = { phase = "limb", planet = { 60, 120, 200 }, rim = { 255, 220, 170 }, sun = true },
			hazards = { "globe" },
		},
		{
			id = "cargo", name = "CARGO SPINE", first = 10, last = 15, from = 9, fade = 1,
			line = "Everything here is strapped down. Almost everything.",
			grade = { tint = { 255, 240, 214 }, saturation = -0.05, contrast = 0.15, brightness = -0.01,
				atmosColor = { 200, 170, 120 }, atmosDecay = { 110, 80, 40 } },
			palette = { wall = { 176, 171, 160 }, floor = { 98, 94, 87 }, trim = { 143, 114, 57 } },
			kit = "cargo",
			weather = { kind = "dust", color = { 200, 184, 150 }, size = 0.1 },
			critters = { kind = "drones", where = "any", color = { 170, 140, 255 }, glow = true },
			exterior = { phase = "trusses", planet = { 50, 100, 180 }, rim = { 255, 200, 140 }, sun = true },
			hazards = { "crate" },
		},
		{
			id = "reactor", name = "REACTOR RING", first = 16, last = 22, from = 15, fade = 1,
			line = "CORE 88%. The heat never stopped.",
			grade = { tint = { 255, 226, 204 }, saturation = 0.08, contrast = 0.2, brightness = -0.01,
				atmosColor = { 220, 150, 110 }, atmosDecay = { 140, 60, 40 } },
			palette = { wall = { 182, 160, 146 }, floor = { 100, 87, 80 }, trim = { 142, 106, 71 } },
			kit = "reactor",
			weather = { kind = "embers", color = { 255, 150, 80 }, size = 0.12 },
			critters = { kind = "wisps", where = "any", color = { 200, 150, 255 }, glow = true },
			exterior = { phase = "terminator", planet = { 40, 70, 140 }, rim = { 255, 90, 60 }, sun = false },
			hazards = { "slag" },
		},
		{
			id = "array", name = "ARRAY SPINE", first = 23, last = 30, from = 22, fade = 1,
			line = "The Main Array waits at the end of the spine.",
			grade = { tint = { 222, 226, 255 }, saturation = 0.02, contrast = 0.16, brightness = 0,
				atmosColor = { 140, 140, 230 }, atmosDecay = { 60, 50, 140 } },
			palette = { wall = { 156, 165, 198 }, floor = { 83, 90, 118 }, trim = { 89, 109, 197 } },
			kit = "array",
			weather = { kind = "static", color = { 150, 140, 255 }, size = 0.1 },
			critters = { kind = "satellites", where = "outside", color = { 200, 205, 220 }, glow = false },
			exterior = { phase = "aurora", planet = { 20, 36, 80 }, rim = { 120, 255, 200 }, sun = false, dish = true },
			hazards = { "shard" },
		},
		{
			id = "deep", name = "THE DEEP", first = 31, last = 59, from = 30, fade = 1,
			line = "Nobody mapped this part of the station.",
			grade = { tint = { 214, 226, 240 }, saturation = -0.3, contrast = 0.18, brightness = -0.02,
				atmosColor = { 110, 130, 150 }, atmosDecay = { 30, 40, 60 } },
			palette = { wall = { 146, 158, 171 }, floor = { 79, 86, 97 }, trim = { 93, 110, 127 } },
			kit = "deep",
			weather = { kind = "ice", color = { 235, 245, 255 }, size = 0.1 },
			critters = { kind = "meteors", where = "outside", color = { 230, 230, 240 }, glow = false },
			exterior = { phase = "eclipse", planet = { 4, 4, 8 }, rim = { 255, 250, 235 }, sun = false, dish = true },
			hazards = { "ice" },
			brag = true,
		},
		{
			id = "echo", name = "THE ECHO", first = 60, last = math.huge, from = 59, fade = 1,
			line = "The answer is coming from here.",
			grade = { tint = { 236, 220, 255 }, saturation = -0.1, contrast = 0.2, brightness = -0.02,
				atmosColor = { 150, 110, 200 }, atmosDecay = { 60, 30, 100 } },
			palette = { wall = { 163, 152, 185 }, floor = { 89, 82, 105 }, trim = { 125, 87, 192 } },
			kit = "echo",
			weather = { kind = "violet", color = { 190, 130, 255 }, size = 0.1 },
			critters = { kind = "shapes", where = "outside", color = { 10, 8, 16 }, glow = false },
			exterior = { phase = "nebula", planet = { 4, 4, 8 }, rim = { 170, 110, 255 }, sun = false, dish = true },
			hazards = { "orb" },
		},
	},
	-- A module in the sector BEFORE a band wears that band's kit when hash01(k, module) < its blend weight
	-- (foreshadowing, facility-nightmare's rule).
	ForeshadowSeed = 77731,
}

--============================================================================ §5 hazards (client)
Config.Hazards = {
	-- the template's clock and rate
	IntervalMin = 55, -- eligible seconds: one warning per 2.32-3.08 min (median 2.54) of play at k >= 5 through the real client, 47 campaigns [REVIEW-1 finding 5]
	IntervalMax = 85, -- (80-120 [M7] gave 3.3-3.6 on the real client path: the eligible share is 0.50-0.57, not M7's 0.62-0.65)
	FirstIntervalSeconds = 30, -- the first hazard of a session [M7b]
	MinTelegraphSeconds = 3, -- [REPO plus1-jump Config]
	MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5,
	PlayerRadius = 1.5,
	KnockLift = 1, -- the capped lift of the template; each kind may ask for less
	SpreadDegrees = 35,
	ViewPitchDegrees = 20,
	KindFitDegrees = 25,
	AimJitter = 0, -- adaptation 6: the lane passes through the ring's exact centre
	HitLeadSeconds = 0.25, -- adaptation 6: a hit counts only from 0.25 s before the arrival
	KnockSeconds = 0.6,
	-- Signal Lost's adaptations (DESIGN.md §5.1)
	ArrivalGraceSeconds = 6, -- none in a sector's first seconds
	LowO2Seconds = 10, -- none below this much air
	WaitForStillSeconds = 15, -- a due hazard waits this long (eligible time) for the player to stand still
	StillSpeed = 4, -- studs/s horizontal
	EscapeSpeed = 7.8, -- the slowest walk the model uses in vacuum (the slow proxy) [DESIGN §5.2]
	ReactionSeconds = 0.5,
	InteriorMargin = 1.5, -- the lane starts at least this far inside the module's walls, floor and ceiling
	MinLaneStuds = 6, -- a lane the module cannot fit this long waits for a better view
	InteriorStuds = 30, -- a module's interior (CellSize - 2 x WallThickness): every lane must fit inside it
	KnockMax = 20,
	LiftMax = 1,
	Kinds = {
		globe = { name = "WATER GLOBE", speed = 5, telegraph = 3.2, commit = 1.5, pass = 1.6, hitRadius = 2.0,
			knock = 14, lift = 0, pitch = 8, pitchSpread = 6 },
		crate = { name = "LOOSE CRATE", speed = 6, telegraph = 3.0, commit = 1.5, pass = 1.6, hitRadius = 2.2,
			knock = 18, lift = 1, pitch = 6, pitchSpread = 6 },
		slag = { name = "SLAG BLOB", speed = 6, telegraph = 3.0, commit = 1.5, pass = 1.6, hitRadius = 2.0,
			knock = 18, lift = 0, pitch = 10, pitchSpread = 6 },
		shard = { name = "PANEL SHARD", speed = 6, telegraph = 3.0, commit = 1.5, pass = 1.6, hitRadius = 2.2,
			knock = 20, lift = 1, pitch = 12, pitchSpread = 8 },
		ice = { name = "ICE CHUNK", speed = 6, telegraph = 3.0, commit = 1.5, pass = 1.6, hitRadius = 2.2,
			knock = 20, lift = 1, pitch = 10, pitchSpread = 8 },
		orb = { name = "STATIC ORB", speed = 5, telegraph = 3.4, commit = 1.5, pass = 1.6, hitRadius = 2.0,
			knock = 16, lift = 0, pitch = 8, pitchSpread = 6 },
	},
}

--============================================================================ §6 rest (client)
Config.Rest = {
	IdleSeconds = 20, -- the template's value
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	PendingSeconds = 7, -- the longest flight (3.4 + 1.6) + 2 s to stand still [ARITH]
	AllowedIn = { hub = true, air = true }, -- never vacuum: validateStation() refuses it
	Text = {
		Resting = "RESTING — the air here holds. Nothing is lost, nothing is earned. Move to go on.",
		NoAir = "No air here — rest where the hatch light is green.",
		NotHere = "You can't rest right now.",
		-- REST asked for in air while debris still flies through a ring the player left (REVIEW-1): queued, and said
		Queued = "Resting as soon as the debris has passed.",
		-- after Player.Idled (about 2 minutes idle): what the idle disconnect would cost (DESIGN.md §6.5)
		IdleWarning = "Idle for 20 minutes and Roblox disconnects you: you would keep half of your %d carried salvage. Splice the relay to keep it all.",
	},
}

--============================================================================ budgets (client), caps in code
Config.Budget = {
	MaxDressPartsPerModule = 10,
	MaxDressParts = 300,
	MaxEmitters = 4,
	MaxWeather = 2,
	MaxLights = 3,
	MaxHazards = 1,
	MaxExteriorParts = 45,
	MaxCritters = 3,
	WeatherMaxTotal = 12, -- particles per second between the weather emitters
}

return Config
