--!strict
-- Config.luau — EVERY tunable of The Same Door in one place (docs/new-game-checklist.md §1).
--
-- Replicated (ReplicatedStorage) on purpose, and that is safe: nothing here can produce a layout.
-- The day's dungeon is not derived from a seed; it is drawn from server entropy on the day and
-- stored as data (DESIGN.md §3). The generator lives in ServerScriptService (src/server/Dungeon).
-- `StudioDoorSeed` only ever drives the Studio fallback door, which is unranked twice over (§3.5).
--
-- Tags on numbers, as in DESIGN.md: [M] measured by the design-stage model, [R] repo precedent,
-- [D] Roblox documentation, [C] a design choice, [S] provisional until Studio measures it.

local Config = {}

--============================================================================ the dungeon grid
Config.Grid = {
	W = 9, -- [M] DESIGN §3.2: first run p50 151 s, perfect line p50 27.3 s
	H = 9,
	Cell = 16, -- [C] one cell per second at WalkSpeed 16
	Loops = 8, -- [M] extra loop openings after the backtracker
	EntranceX = 4, -- [C] the south-middle cell; the antechamber and start line are the same every day
	EntranceY = 0,
	WallThick = 2, -- [C] a wall is centred on the cell boundary, 1 stud into each cell
	WallHeight = 14, -- [C] the ceiling is at 14: a jumping head stays under it
	RevealSteps = 2, -- [C] cells within 2 open-passage steps of a visited cell are sent
}

Config.Walk = {
	Speed = 16, -- [R] Roblox default WalkSpeed
	JumpHeight = 7.2, -- [R] Roblox default
}

-- Placement rules (DESIGN §3.2). Distances are BFS steps through open passages.
Config.Place = {
	SealAMin = 3, -- [M] first seal p50 8.4 s after the line
	SealAMax = 6,
	SealMin = 6, -- [C] seals B and C at least this far from the entrance
	SealSep = 6, -- [C] every pair of seals at least this far apart, so the ORDER matters
	DoorFrac = 0.6, -- [C] the Door at >= 0.6 x the farthest cell's distance
	DoorSealSep = 4, -- [C] and >= 4 from each seal
}

Config.Perfect = {
	-- P is the shortest line in the whole-run check's OWN geometry (Dungeon.tightLine; REVIEW-1
	-- findings 2 and 5): Check.TautMargin off every jamb, the start anywhere on the line, each seal
	-- touched within Pickup.Radius - PickupInset, the end on the Door's pickup circle. There is no
	-- separate P margin any more: a P measured more loosely than the check lets a script walk the
	-- published line faster than honest players and still pass.
	PickupInset = 0.25, -- [C] a 60 Hz walk of the line cuts the corner at a touch point; 0.25 keeps it inside 4
	MinSeconds = 21, -- [M] accept a mint only if 21 s <= P <= 32 s (see CLAUDE.md for the acceptance rate)
	MaxSeconds = 32,
	MaxAttempts = 50, -- [C] then fail closed; P(50 rejections) is negligible
	-- Per leg, every simple cell path up to PathSlack steps over the BFS distance is a candidate
	-- corridor. [M] design/measure/pgap.luau, 200 days, against an independent search at slack 8:
	-- slack 0 or 1 (min-step paths only; grid paths differ by even step counts) still left a shorter
	-- line on 11 days (worst 4.1 %); slack 2, 4 and 8 on none. 4 keeps a margin. The search stops
	-- after MaxExpansions nodes per leg, so it is bounded and deterministic (every server must
	-- recompute the same perfectMs); [M] the largest leg needed 932.
	PathSlack = 4,
	MaxExpansions = 200000,
}

Config.Pickup = {
	Radius = 4, -- [C] a seal / the Door is reached within 4 studs (horizontal) of its centre
}

Config.RunCapSeconds = 900 -- [M] 1.72 x the slowest of 2000 model first runs

Config.Medals = {
	-- A run earns the best medal whose threshold it meets: time <= mult x P. Stored as percent so the
	-- comparison is exact integer arithmetic (time * 100 <= P * pct).
	-- REVIEW-1: P is now the tight line, 0.912-0.969 of the first build's centre line (median 0.937,
	-- 200 days), so the first build's 160 / 125 / 110 became 171 / 133 / 118: about the same seconds on
	-- a median day, and the same slack over the best possible line on EVERY day. Sealer is the brag
	-- moment, and it is steep: [M] tests/Pacing.spec, normal profile's first Sealer at a median of
	-- 50.9 / 36.6 / 30.6 / 18.9 cumulative minutes for SealerPct 117 / 118 / 119 / 120.
	SilverPct = 171,
	GoldPct = 133,
	SealerPct = 118,
}

Config.Day = {
	SecondsPerDay = 86400,
	-- Door #1 is 2026-09-30 (dayIndex 20726, measured with Python's datetime), so Door # = day - 20725.
	Epoch = 20725,
	-- v2 (REVIEW-1): perfectMs is the tight line (Dungeon.tightLine). A v1 record's perfectMs was the
	-- first build's centre line, so a v1 day can never validate here; the store moved with it.
	StoreName = "SameDoor_Days_v2",
	RecordVersion = 2,
	-- A live server whose Days store fails keeps retrying: 2, 4, 8, 16, then every 30 s. [C]
	RetrySchedule = { 2, 4, 8, 16 },
	RetryEvery = 30,
}

-- Studio fallback door (DESIGN §3.5): ONLY when RunService:IsStudio() and the Days store cannot be
-- reached. Deterministic from this public seed, and never ranked.
Config.StudioDoorSeed = 20260930

--============================================================================ the world
Config.World = {
	LaneSpacing = 256, -- [C] lane i at x = (i - 1) * 256
	LaneZ = 1000, -- [C] every lane sits at z = +1000 from the hub
	MaxLanes = 12, -- one per player (MaxPlayers 12)
	FloorY = 0, -- floor top of the hub and of every lane
	HubSpawnToArch = 14, -- [C] the spawn stands 14 studs south of the arch, facing it
	PromptDistance = 10, -- MaxActivationDistance of the arch and board prompts
	AntechamberDepth = 16,
	SanctumOffset = 40, -- the Dawn Sanctum sits this far north of the grid's north wall
}

--============================================================================ the run monitor
-- Server-side movement checks (DESIGN §11). Every limit is [S]: provisional until Studio records
-- honest runs on desktop and on a phone over 4G, with a target of < 1 % honest runs voided.
Config.Check = {
	-- The slacks carry a 0.4 s replication stall (the server sees the root frozen, then caught up):
	-- on a straight hall a window then spans 16 x (w + 0.4) studs, so slack >= 16 x (0.4 - w x (factor
	-- - 1)). REVIEW-1 pass: with slacks of 2, a 0.4 s stall voided an honest walk at 25 of 44 spots
	-- along the line (RunCheck.spec walks it at every 40th frame).
	BurstWindow = 0.5,
	BurstFactor = 1.5,
	BurstSlack = 3, -- 16 * 0.5 * 1.5 + 3 = 15 studs in any 0.5 s (a stall of up to 0.43 s)
	SustainWindow = 3,
	SustainFactor = 1.05,
	SustainSlack = 4.5, -- 16 * 3 * 1.05 + 4.5 = 54.9 studs in any 3 s (a stall of up to 0.43 s)
	WholeRunFactor = 1.02, -- the time may not beat the taut line through the cells passed at 16 * 1.02
	TautMargin = 2, -- the taut line keeps 2 studs off a jamb: wall half-thickness 1 + half a 2-wide root
	GapSeconds = 0.25, -- a sample gap longer than this widens the continuity allowance
	GapFactor = 1.5,
	MinRootY = -2, -- root Y relative to the floor top
	MaxRootY = 13, -- the ceiling is at 14
}

--============================================================================ hazards
-- DoorHazards.luau (from labyrint-spill CellHazards; DESIGN §8). Cells come from the day record.
Config.Hazards = {
	CellSize = 16,
	Count = 3, -- [M] 3 fork cells per day
	Cycle = 12, -- [M] slot k impacts at First + Slot * (k - 1) + Cycle * n
	Slot = 4,
	First = 6, -- the first warning starts at 3 s after the line
	WarnSeconds = 3.0, -- [R] labyrint (floor 2 s)
	MinWarnSeconds = 2,
	DebrisSeconds = 0.8,
	StrikeRadius = 2.5, -- [C] zone 2.5 + 1.5 = 4.0: an 8-stud ring in a 14-stud free cell
	PlayerRadius = 1.5,
	LaneWidth = 1.5, -- the root's free lane beside the ring
	MaxHitHeight = 12, -- [R] labyrint MIN_HIT_HEIGHT: a jump is no dodge
	KnockSeconds = 0.8, -- [R] labyrint
	KnockPush = 5, -- studs/s, horizontal, away from the impact
	MaxKnockDisplacement = 4,
	NearRadius = 12, -- [R] labyrint: an impact within 12 studs that does not hit
	MinFromEntrance = 3, -- placement (server): >= 3 steps from the entrance
	MinSpacing = 4, -- pairwise >= 4 steps apart
	MinOpenSides = 3, -- forks only
	RingColor = { 230, 40, 40 },
	Kinds = { "stalactite", "spore pod", "crystal", "ember bomb", "stalactite" }, -- by band, cosmetic only
}

--============================================================================ rest
-- Rest.luau verbatim (DESIGN §9). Rest lives between runs, in the hub; the run clock never stops.
Config.Rest = {
	IdleSeconds = 0, -- [C] the hub has nothing to be safe from (labyrint does the same)
	RequireGrounded = true,
	BlockWhileThreat = true, -- validate requires it; the hub never has a threat
	WakeOnMove = true,
	WakeGraceSeconds = 0.4, -- [R] plus1
	PendingSeconds = 2, -- a default jump lasts 0.54 s; 2 s covers landing from any hub jump
}

--============================================================================ colours
-- Two colours are RESERVED (DESIGN §7): only a Seal glows seal-gold, only a hazard ring is red.
-- Every decor, critter, weather, torch and door colour keeps MinColourDistance (RGB) from both.
Config.Colours = {
	SealGold = { 255, 200, 70 },
	HazardRed = { 230, 40, 40 },
	MinColourDistance = 75,
	DoorAwake = { 255, 230, 180 },
	DoorAsleep = { 70, 66, 78 },
	Veil = { 0, 0, 0 },
}

--============================================================================ environment bands
-- Progress = the number of Seals the player carries (0..3), 4 once the Door has opened. From the
-- server's Run payload, NEVER from time. fade 0: a seal pickup is a step, glided by `HalfLife`.
Config.Env = {
	HalfLife = 0.8, -- [C] 87.5 % of the change has landed after 2.4 s
	LightingHz = 10, -- [R] plus1 Config.Env.LightingHz: Lighting written at most 10 times a second
	DecorRadius = 24, -- [C] decor only on revealed walls within 24 studs of the player
	DecorMaxOut = 1.2, -- [C] decor sits at most 1.2 studs out of a face
	Bands = {
		{
			id = "cellar", name = "Cold Cellar", from = 0, fade = 0,
			lighting = { Ambient = { 70, 80, 100 }, OutdoorAmbient = { 60, 66, 80 }, Brightness = 0.6, ClockTime = 0,
				FogColor = { 20, 24, 32 }, FogStart = 10, FogEnd = 90, ExposureCompensation = 0 },
			colorCorrection = { TintColor = { 205, 215, 240 }, Saturation = -0.25, Contrast = 0.12, Brightness = -0.02 },
			bloom = { Intensity = 0.35, Size = 20, Threshold = 1.2 },
			wall = { 90, 95, 105 },
			torch = { 200, 215, 255 },
			decor = { { kind = "cobweb", color = { 200, 200, 210 } }, { kind = "chain", color = { 90, 90, 95 } },
				{ kind = "drip", color = { 120, 140, 160 } } },
			critter = { kind = "bat", color = { 40, 35, 45 }, count = 3 },
			weather = { kind = "dust", color = { 180, 180, 190 }, rate = 18 },
		},
		{
			id = "moss", name = "Moss Halls", from = 1, fade = 0,
			lighting = { Ambient = { 60, 100, 72 }, OutdoorAmbient = { 50, 80, 60 }, Brightness = 0.7, ClockTime = 0,
				FogColor = { 18, 34, 26 }, FogStart = 12, FogEnd = 100, ExposureCompensation = 0.05 },
			colorCorrection = { TintColor = { 200, 245, 215 }, Saturation = 0.05, Contrast = 0.1, Brightness = 0 },
			bloom = { Intensity = 0.55, Size = 24, Threshold = 1.05 },
			wall = { 80, 95, 80 },
			torch = { 150, 255, 210 },
			decor = { { kind = "moss", color = { 70, 120, 60 } }, { kind = "fern", color = { 60, 140, 70 } },
				{ kind = "mushroom", color = { 90, 255, 200 }, glow = true } },
			critter = { kind = "firefly", color = { 140, 255, 190 }, count = 6 },
			weather = { kind = "spores", color = { 170, 220, 150 }, rate = 20 },
		},
		{
			id = "crystal", name = "Crystal Seams", from = 2, fade = 0,
			lighting = { Ambient = { 90, 72, 130 }, OutdoorAmbient = { 70, 60, 110 }, Brightness = 0.8, ClockTime = 0,
				FogColor = { 26, 20, 44 }, FogStart = 14, FogEnd = 110, ExposureCompensation = 0.1 },
			colorCorrection = { TintColor = { 220, 210, 255 }, Saturation = 0.15, Contrast = 0.14, Brightness = 0.01 },
			bloom = { Intensity = 0.8, Size = 28, Threshold = 0.95 },
			wall = { 85, 80, 110 },
			torch = { 170, 190, 255 },
			decor = { { kind = "crystal", color = { 120, 170, 255 }, glow = true }, { kind = "geode", color = { 150, 110, 220 } } },
			critter = { kind = "moth", color = { 200, 190, 255 }, count = 5 },
			weather = { kind = "glitter", color = { 210, 220, 255 }, rate = 24 },
		},
		{
			id = "ember", name = "Ember Vault", from = 3, fade = 0,
			lighting = { Ambient = { 130, 82, 62 }, OutdoorAmbient = { 110, 70, 55 }, Brightness = 0.9, ClockTime = 0,
				FogColor = { 44, 22, 16 }, FogStart = 14, FogEnd = 110, ExposureCompensation = 0.12 },
			colorCorrection = { TintColor = { 255, 225, 205 }, Saturation = 0.2, Contrast = 0.16, Brightness = 0.02 },
			bloom = { Intensity = 1.0, Size = 30, Threshold = 0.9 },
			wall = { 110, 85, 70 },
			torch = { 255, 140, 120 },
			decor = { { kind = "brazier", color = { 255, 120, 90 }, glow = true }, { kind = "bronze", color = { 150, 100, 60 } } },
			critter = { kind = "fire sprite", color = { 255, 130, 100 }, count = 4 },
			weather = { kind = "embers", color = { 255, 120, 90 }, rate = 26 },
		},
		{
			id = "dawn", name = "Dawn Sanctum", from = 4, fade = 0,
			lighting = { Ambient = { 150, 120, 130 }, OutdoorAmbient = { 190, 160, 170 }, Brightness = 2.2, ClockTime = 6.3,
				FogColor = { 255, 205, 200 }, FogStart = 60, FogEnd = 900, ExposureCompensation = 0.2 },
			colorCorrection = { TintColor = { 255, 235, 235 }, Saturation = 0.18, Contrast = 0.06, Brightness = 0.03 },
			bloom = { Intensity = 1.1, Size = 32, Threshold = 0.85 },
			wall = { 215, 205, 195 },
			torch = { 255, 250, 225 },
			decor = { { kind = "column", color = { 230, 225, 215 } }, { kind = "flowers", color = { 255, 170, 200 } },
				{ kind = "flowers", color = { 170, 120, 255 } } },
			critter = { kind = "bird", color = { 60, 50, 70 }, count = 5 },
			weather = { kind = "petals", color = { 255, 180, 210 }, rate = 16 },
		},
	},
}

--============================================================================ budgets
-- Enforced in code and measured headless (robloxemu/check_samedoor_eyecandy.luau).
Config.Budget = {
	MaxLocalParts = 220, -- worst case 201 (DESIGN §17)
	MaxDecor = 30,
	MaxCritters = 8,
	MaxLights = 4, -- the torch + the 3 nearest sconces/glows
	MaxEmitters = 4, -- 2 weather + the nearest 2 seal / Door glows
	MaxWeatherEmitters = 2,
	MaxEmitterRate = 60, -- [R] plus1 Config.Budget
	MinWeatherRate = 1,
}

--============================================================================ ranks and torches
-- Torch colours are ranks; they keep clear of seal-gold and hazard-red like every decor colour.
Config.Ranks = {
	{ id = "Wanderer", label = "Wanderer", torch = { 255, 140, 120 } },
	{ id = "Gilded", label = "Gilded", torch = { 240, 230, 170 } },
	{ id = "Sealer", label = "Sealer", torch = { 255, 250, 225 } },
	{ id = "Warden", label = "Warden", torch = { 60, 210, 190 } },
	{ id = "Keeper", label = "Keeper of the Same Door", torch = { 170, 110, 255 } },
}
Config.RankRules = {
	WardenStreak = 7, -- a 7-day Door streak
	KeeperSealerDays = 30, -- 30 Sealer days
}
Config.TorchDefault = { 255, 150, 130 } -- before the first Door: a plain warm torch

--============================================================================ the board
Config.Board = {
	StoreName = "SameDoor_Board_v1", -- OrderedDataStore, scope "d<dayIndex>", key "u_<userId>"
	CapMs = 900000, -- = RunCapSeconds * 1000
	TieBase = 2000000000, -- value = (CapMs - timeMs) * 2e9 + (2e9 - reachedAtUnix)
	PublicSize = 10,
	PublicCacheSeconds = 60, -- [C] about 60 s (the standard)
	YesterdaySize = 3,
	YesterdayCacheSeconds = 3600, -- [C]
	FriendsCap = 200, -- the standard's example
	FriendsCacheSeconds = 300, -- [C]
	FriendsBudgetReserve = 20, -- [C] leave saves and the day record room in the GetAsync budget
	NameCacheMax = 500, -- [C]
	EmptyFriends = "None of your friends have opened today's Door yet. They get the exact same dungeon: tell them your time.",
	EmptyPublic = "Nobody has opened today's Door yet. Be the first name on it.",
}

--============================================================================ saving
Config.Save = {
	StoreName = "SameDoor_Players_v1",
	AutosaveSeconds = 20, -- [R] plus1: autosave must be shorter than the lock
	SessionLockSeconds = 45,
	ProfileVersion = 1,
	-- REVIEW-1 finding 4: a session that found the profile locked by another (a crashed server, a
	-- release write that failed) tries again just after that lock runs out; one whose load FAILED
	-- tries again every LockRetrySeconds. [C]
	LockRetrySeconds = 10,
}

Config.Limits = {
	RemoteMinInterval = 1, -- Leave / RunAgain / Hub: one per second, state-checked
}

--============================================================================ timing of the loop
Config.Timing = {
	ArrivalHintSeconds = 6, -- the antechamber card stays up this long (or until the line)
}

return Config
