--!strict
-- +1 JUMP EVERY STEP — Sky Temple Obby
-- Alt styres herfra. Endre tall ETT sted; ingen magiske konstanter spredt i koden.
-- Rene moduler (Progression, TowerGen) leser IKKE denne globalt — verdiene sendes
-- inn, så de kan testes med luau-CLI uten Roblox. Serveren/klienten leser CONFIG.

local Config = {}

-- ── Determinisme ────────────────────────────────────────────────────────────
-- Samme WorldSeed => nøyaktig samme tårn for alle, hver gang. Bytt tall = nytt tårn.
Config.WorldSeed = 20260905

-- ── Hopp-modell ─────────────────────────────────────────────────────────────
-- Vi setter Humanoid.JumpHeight direkte (UseJumpPower = false).
-- JumpHeight(jp, mult) = clamp(BaseJump + jp * JumpPerStep * mult, BaseJump, MaxJumpHeight)
Config.Jump = {
	BaseJump = 7.2,        -- Roblox-standard hoppehøyde (studs) ved 0 jump power
	JumpPerStep = 0.6,     -- +studs hoppehøyde pr opptjent jump power (før multiplier)
	MaxJumpHeight = 60,    -- fysikk-tak så figuren ikke skytes i bane
	StartJumpPower = 0,    -- jump power en fersk (ikke-rebirthet) spiller starter med
}

-- ── Tårn-etasjer (prosedyre-generert, uendelig) ─────────────────────────────
-- Hver etasje = TilesPerTier steg-plattformer som stiger StepHeight(t) hver, med en
-- liten horisontal Gap(t). Å tråkke en NY plattform gir +1 jump power.
-- REACHABILITY-INVARIANT (testet): StepHeight(t) <= Safety * oppnåelig hopp med den
-- jump power spilleren HAR når hen når etasje t UTEN rebirth (mult=1). Så tårnet er
-- alltid mulig å klare selv for en helt fersk spiller.
Config.Tower = {
	TilesPerTier = 6,      -- plattformer pr etasje (= +6 jump power pr etasje klarert)
	TileSize = 8,          -- studs (kvadratisk plattform)

	StepMin = 5,           -- vertikal stigning pr plattform på etasje 1
	StepPerTier = 2.5,     -- hvor mye stigningen vokser pr etasje
	StepMax = 44,          -- tak på stigning (må ligge under Safety*MaxJumpHeight)

	GapMin = 2,            -- horisontal avstand pr plattform, etasje 1
	GapPerTier = 0.05,     -- vokser sakte
	GapMax = 6,            -- tak — alltid klarerbart med gangfart+minstehopp

	Safety = 0.8,          -- StepHeight må være <= Safety * oppnåelig hopp
	HazardStartTier = 5,   -- ingen hindringer før denne etasjen
	HazardEveryNTiers = 4, -- +1 hindring pr N etasjer etter start
	HazardMax = 5,         -- tak på hindringer pr etasje

	StreamAhead = 6,       -- etasjer som bygges foran høyeste spiller
	StreamBehind = 3,      -- etasjer beholdt under laveste spiller (resten fjernes)

	BaseY = 8,             -- sokkelens topp; etasje 1 bygges herfra (server BASE_POS, himmel-båndene)
}

-- ── Rebirth ─────────────────────────────────────────────────────────────────
-- Rebirth nullstiller jump power, men banker en PERMANENT multiplier på fremtidige
-- opptjeninger. Krav: nå en viss etasje. Multiplieren vokser pr rebirth.
Config.Rebirth = {
	FirstTierRequired = 10,   -- må nå etasje 10 for rebirth #1
	TierRequiredPerRebirth = 8, -- +8 etasjer i krav pr rebirth du alt har
	Multipliers = { 2, 5, 10, 25, 50, 100 }, -- rebirth 1..6; deretter siste * (n-5)
	-- EIERBESLUTNING, ikke tatt (review 2026-09-17 runde 2, EYECANDY.md §11): hvilke rebirths HUD-en
	-- LYSER opp (lilla «REBIRTH → 5x?»). Knappen virker alltid når serveren tillater rebirth.
	--   math.huge (standard) = hver rebirth lyser, som før himmelen. Men en vanlig spiller som trykker
	--     hver gang den lyser (10, 18, 26 …), når verdensrommet først etter 46-227 min, ikke 30-45:
	--     med hopp-taket gjør rebirth aldri klatringen raskere.
	--   1 = bare den FØRSTE lyser, og så igjen når beste etasje har nådd siste himmel-bånd
	--     (HighlightAgainAtBestTier). Da når den samme spilleren verdensrommet på 38 min.
	-- Progression.rebirthHighlighted; tests/Pacing.spec.luau måler begge.
	HighlightFirstRebirths = math.huge,
	HighlightAgainAtBestTier = 0, -- = Config.Env.Bands[#Bands].from, satt etter Config.Env
}

-- ── Gamepasses (fyll inn ekte IDs når laget på Roblox; AV til da) ───────────
Config.Passes = {
	Enabled = false,
	AutoWalk = 0,   -- går fremover automatisk
	DoubleJump = 0, -- 2x jump power-opptjening
	SkyTrails = 0,  -- kosmetisk spor
}

-- ── Koder (kosmetikk/boost — engangs pr spiller) ────────────────────────────
-- Belønning er ren data; innløsnings-logikken (Codes.luau) er ren + testet.
Config.Codes = {
	["SKYHIGH"]   = { jump = 25 },   -- +25 jump power engangs
	["TEMPLE"]    = { jump = 50 },
	["LAUNCH"]    = { jump = 100 },
	["WELCOME"]   = { jump = 10 },
}

-- ── Lagring ─────────────────────────────────────────────────────────────────
Config.Save = {
	Enabled = true,
	Store = "Plus1Jump_v1",       -- per-spiller data
	Leaderboard = "Plus1Jump_LB_v1", -- OrderedDataStore (høyeste etasje)
	AutosaveSeconds = 20,         -- fornyer også session-låsen; MÅ være < SessionLockSeconds
	SessionLockSeconds = 45,      -- soft lås mot dupe; utløper raskt så crash-rejoin ikke låses ute
}

Config.WalkSpeed = 16

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- HIMMELEN: miljø-bånd, farer og hvile (EYECANDY.md forklarer alt og hvor tallene kommer fra)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Alt under er KOSMETISK og kjører på klienten (src/client/Sky.client.luau). Ingenting her gir,
-- tar eller registrerer progresjon; serveren leser det ikke. Farger er {r, g, b} (0-255), ikke
-- Color3, så de rene modulene og testene kan lese dem i luau-CLI.
--
-- Progresjon = etasjer klatret, regnet fra spillerens EGEN høyde (Progression.tierProgressAtY).
-- Et bånd blender inn over `fade` etasjer FØR `from`. Tallene for `from` er målt med
-- tests/Pacing.spec.luau: `orbit` (verdensrommet) ligger der en normal spiller er etter ~35 min.

local function rgb(r: number, g: number, b: number): { number }
	return { r, g, b }
end

Config.Env = {
	SpaceBandId = "orbit",   -- båndet som teller som «jeg kom til verdensrommet»
	HalfLife = 0.6,          -- sek: lys/tåke glir mot målet (ingen hard cut ved teleport/rebirth)
	LightingHz = 10,         -- Lighting skrives maks 10 ganger i sekundet
	-- Bånd-NAVNET (chip, kort, hvilke farer) følger etasje-nummeret du står i, som HUD og topp-10 viser.
	-- Rot-delen står ~3,5 studs over plattform-senteret; 2 gir toleranse (Progression.tierAtY).
	FloorBelowRoot = 2,
	-- Tempel-øya under sokkelen er IKKE kolliderbar. Gress-toppen ligger så dypt at en spiller som går
	-- av sokkelen alltid reddes (serverens 0,4 s-poll + nett-forsinkelse) FØR føttene når gresset
	-- (review 2026-09-17: på 70 studs sank 89 % gjennom gresset). EnvConfig.spec regner det ut.
	IslandTopBelowPad = 320,
	-- Skydekkene (tiled, verdensfaste) holder overflaten minst så langt unna klatreruta, så en sky aldri
	-- sluker neste plattform eller skjuler den for kameraet (review 2026-09-17: stormskya på etasje 42).
	SceneryClearance = 40,

	Bands = {
		{
			id = "temple", from = 0, fade = 0, name = "Temple Grounds", emoji = "🏛️",
			-- = Fx.Presets.Temple, så klienten overtar fra serverens lys uten hopp
			lighting = { ClockTime = 15.5, Brightness = 3, ExposureCompensation = 0.15,
				Ambient = rgb(120, 125, 140), OutdoorAmbient = rgb(150, 160, 185),
				FogStart = 100, FogEnd = 900, FogColor = rgb(200, 220, 245) },
			atmosphere = { Density = 0.32, Offset = 0.25, Color = rgb(200, 220, 245), Decay = rgb(130, 160, 200), Glare = 0.4, Haze = 2 },
			sky = { StarCount = 0, SunAngularSize = 21, MoonAngularSize = 11 },
			bloom = { Intensity = 1.1, Size = 28, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.15, TintColor = rgb(255, 250, 240) },
			sunRays = { Intensity = 0.18, Spread = 0.9 },
			pieces = { "templeIsland" },
			ambient = { { kind = "bird", count = 3 } },
			weather = { kind = "petals", rate = 6 },
			hazards = {},
		},
		{
			id = "treetops", from = 7, fade = 3, name = "Treetops", emoji = "🌳",
			lighting = { ClockTime = 15.6, Brightness = 3.2, ExposureCompensation = 0.2,
				Ambient = rgb(125, 135, 140), OutdoorAmbient = rgb(150, 170, 170),
				FogStart = 150, FogEnd = 1400, FogColor = rgb(190, 225, 240) },
			atmosphere = { Density = 0.28, Offset = 0.2, Color = rgb(190, 225, 240), Decay = rgb(120, 170, 160), Glare = 0.5, Haze = 1.6 },
			sky = { StarCount = 0, SunAngularSize = 22, MoonAngularSize = 11 },
			bloom = { Intensity = 1.0, Size = 26, Threshold = 0.9 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.1, Saturation = 0.22, TintColor = rgb(245, 255, 240) },
			sunRays = { Intensity = 0.15, Spread = 0.8 },
			pieces = { "canopy", "templeIsland" },
			ambient = { { kind = "bird", count = 10 } },
			weather = { kind = "petals", rate = 4 },
			hazards = { "bird" },
		},
		{
			id = "cloudsea", from = 15, fade = 4, name = "Cloud Sea", emoji = "☁️",
			lighting = { ClockTime = 16.4, Brightness = 3.4, ExposureCompensation = 0.25,
				Ambient = rgb(140, 135, 135), OutdoorAmbient = rgb(185, 175, 170),
				FogStart = 300, FogEnd = 2400, FogColor = rgb(255, 240, 220) },
			atmosphere = { Density = 0.22, Offset = 0.1, Color = rgb(255, 236, 210), Decay = rgb(230, 170, 130), Glare = 0.9, Haze = 1.2 },
			sky = { StarCount = 0, SunAngularSize = 24, MoonAngularSize = 11 },
			bloom = { Intensity = 1.2, Size = 30, Threshold = 0.85 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.08, Saturation = 0.2, TintColor = rgb(255, 244, 228) },
			sunRays = { Intensity = 0.25, Spread = 0.7 },
			pieces = { "cloudDeck" },
			ambient = { { kind = "balloon", count = 3 }, { kind = "airliner", count = 1 }, { kind = "bird", count = 4 } },
			weather = { kind = "mist", rate = 4 },
			hazards = { "bird", "plane" },
		},
		{
			id = "storm", from = 35, fade = 6, name = "Storm Front", emoji = "⛈️",
			lighting = { ClockTime = 17.6, Brightness = 2.4, ExposureCompensation = 0.1,
				Ambient = rgb(110, 100, 120), OutdoorAmbient = rgb(140, 120, 140),
				FogStart = 200, FogEnd = 1600, FogColor = rgb(120, 110, 140) },
			atmosphere = { Density = 0.38, Offset = 0.05, Color = rgb(150, 130, 160), Decay = rgb(235, 120, 90), Glare = 1.4, Haze = 2.4 },
			sky = { StarCount = 0, SunAngularSize = 28, MoonAngularSize = 11 },
			bloom = { Intensity = 1.3, Size = 32, Threshold = 0.8 },
			colorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.05, TintColor = rgb(255, 225, 215) },
			sunRays = { Intensity = 0.3, Spread = 0.6 },
			pieces = { "stormDeck" },
			ambient = { { kind = "jet", count = 1 }, { kind = "weatherBalloon", count = 2 } },
			weather = { kind = "rain", rate = 40 },
			lightning = { everyMin = 6, everyMax = 14 },
			hazards = { "jet", "weatherBalloon" },
		},
		{
			id = "edge", from = 60, fade = 8, name = "Edge of Space", emoji = "🌠",
			lighting = { ClockTime = 19.2, Brightness = 1.6, ExposureCompensation = 0.35,
				Ambient = rgb(100, 105, 140), OutdoorAmbient = rgb(110, 120, 170),
				FogStart = 1000, FogEnd = 6000, FogColor = rgb(40, 50, 100) },
			atmosphere = { Density = 0.12, Offset = 0, Color = rgb(80, 95, 160), Decay = rgb(200, 90, 140), Glare = 0.6, Haze = 0.6 },
			sky = { StarCount = 1500, SunAngularSize = 18, MoonAngularSize = 12 },
			bloom = { Intensity = 1.4, Size = 36, Threshold = 0.75 },
			colorCorrection = { Brightness = 0.02, Contrast = 0.14, Saturation = 0.12, TintColor = rgb(225, 230, 255) },
			sunRays = { Intensity = 0.12, Spread = 0.5 },
			pieces = { "aurora", "horizonGlow" },
			ambient = { { kind = "booster", count = 1 }, { kind = "meteor", count = 2 } },
			weather = { kind = "ice", rate = 10 },
			hazards = { "weatherBalloon", "booster" },
		},
		{
			id = "orbit", from = 85, fade = 8, name = "SPACE · Low Orbit", emoji = "🚀", celebrate = true,
			lighting = { ClockTime = 23, Brightness = 1.2, ExposureCompensation = 0.55,
				Ambient = rgb(115, 120, 150), OutdoorAmbient = rgb(125, 135, 175),
				FogStart = 20000, FogEnd = 100000, FogColor = rgb(5, 8, 20) },
			atmosphere = { Density = 0, Offset = 0, Color = rgb(20, 25, 45), Decay = rgb(40, 40, 80), Glare = 0, Haze = 0 },
			sky = { StarCount = 3500, SunAngularSize = 12, MoonAngularSize = 14 },
			bloom = { Intensity = 1.5, Size = 40, Threshold = 0.7 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.08, TintColor = rgb(235, 240, 255) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "earth", "station", "aurora" },
			ambient = { { kind = "satellite", count = 2 }, { kind = "astronaut", count = 1 }, { kind = "junk", count = 4 } },
			weather = { kind = "stardust", rate = 5 },
			hazards = { "junk", "astronaut" },
		},
		{
			id = "deep", from = 140, fade = 12, name = "Deep Space", emoji = "🪐",
			lighting = { ClockTime = 23.5, Brightness = 1.0, ExposureCompensation = 0.6,
				Ambient = rgb(120, 110, 150), OutdoorAmbient = rgb(135, 120, 175),
				FogStart = 20000, FogEnd = 100000, FogColor = rgb(10, 5, 25) },
			atmosphere = { Density = 0, Offset = 0, Color = rgb(30, 20, 50), Decay = rgb(60, 30, 90), Glare = 0, Haze = 0 },
			sky = { StarCount = 5000, SunAngularSize = 10, MoonAngularSize = 8 },
			bloom = { Intensity = 1.7, Size = 44, Threshold = 0.65 },
			colorCorrection = { Brightness = 0.03, Contrast = 0.2, Saturation = 0.25, TintColor = rgb(240, 225, 255) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "ringedPlanet", "nebula" },
			ambient = { { kind = "asteroid", count = 6 }, { kind = "ship", count = 1 } },
			weather = { kind = "stardust", rate = 6 },
			hazards = { "asteroid", "ship" },
		},
		{
			id = "galaxy", from = 240, fade = 16, name = "Beyond the Galaxy", emoji = "🌌",
			lighting = { ClockTime = 23.8, Brightness = 0.9, ExposureCompensation = 0.65,
				Ambient = rgb(125, 115, 145), OutdoorAmbient = rgb(145, 125, 170),
				FogStart = 20000, FogEnd = 100000, FogColor = rgb(15, 5, 25) },
			atmosphere = { Density = 0, Offset = 0, Color = rgb(40, 20, 60), Decay = rgb(90, 40, 110), Glare = 0, Haze = 0 },
			sky = { StarCount = 5000, SunAngularSize = 8, MoonAngularSize = 6 },
			bloom = { Intensity = 1.9, Size = 48, Threshold = 0.6 },
			colorCorrection = { Brightness = 0.04, Contrast = 0.22, Saturation = 0.35, TintColor = rgb(255, 230, 250) },
			sunRays = { Intensity = 0, Spread = 0.2 },
			pieces = { "galaxy", "nebula" },
			ambient = { { kind = "comet", count = 1 }, { kind = "asteroid", count = 3 } },
			weather = { kind = "stardust", rate = 8 },
			hazards = { "comet", "asteroid" },
		},
	},

	-- Smale lag du klatrer GJENNOM: «inne i skyen» (tett, hvit dis), så stormskyen (mørk).
	-- center/halfWidth/feather i etasjer; y-høyden regnes fra tårnet (Progression.yAtProgress).
	Layers = {
		{ id = "cloudDeckFog", piece = "cloudDeck", center = 22, halfWidth = 0.12, feather = 0.35,
			atmosphere = { Density = 0.55, Haze = 3.2, Color = rgb(245, 245, 250), Glare = 0 },
			colorCorrection = { Brightness = 0.08, Saturation = -0.1 } },
		{ id = "stormDeckFog", piece = "stormDeck", center = 42, halfWidth = 0.15, feather = 0.4,
			atmosphere = { Density = 0.6, Haze = 3.5, Color = rgb(95, 90, 110), Glare = 0 },
			colorCorrection = { Brightness = -0.05, Contrast = 0.25 } },
	},

	-- Liv i bakgrunnen: aldri farlig, aldri kolliderbart. Avstander i studs fra kameraet.
	Critters = {
		bird = { rMin = 70, rMax = 260, yMin = -30, yMax = 50, speedMin = 16, speedMax = 26, flock = 5 },
		balloon = { rMin = 180, rMax = 520, yMin = -120, yMax = 80, speedMin = 3, speedMax = 6 },
		airliner = { rMin = 500, rMax = 900, yMin = -250, yMax = 120, speedMin = 70, speedMax = 90 },
		jet = { rMin = 420, rMax = 900, yMin = -100, yMax = 200, speedMin = 140, speedMax = 180 },
		weatherBalloon = { rMin = 150, rMax = 450, yMin = -200, yMax = 60, speedMin = 5, speedMax = 9, rise = true },
		booster = { rMin = 300, rMax = 700, yMin = -150, yMax = 150, speedMin = 10, speedMax = 20 },
		meteor = { rMin = 600, rMax = 1400, yMin = 100, yMax = 600, speedMin = 260, speedMax = 380 },
		satellite = { rMin = 160, rMax = 480, yMin = -80, yMax = 80, speedMin = 6, speedMax = 12 },
		astronaut = { rMin = 90, rMax = 260, yMin = -40, yMax = 40, speedMin = 2, speedMax = 4 },
		junk = { rMin = 60, rMax = 300, yMin = -60, yMax = 60, speedMin = 8, speedMax = 20 },
		asteroid = { rMin = 150, rMax = 600, yMin = -150, yMax = 150, speedMin = 4, speedMax = 12 },
		ship = { rMin = 400, rMax = 900, yMin = -120, yMax = 160, speedMin = 110, speedMax = 160 },
		comet = { rMin = 700, rMax = 1500, yMin = 0, yMax = 500, speedMin = 90, speedMax = 140 },
	},
}

-- REBIRTH-knappen lyser igjen først når beste etasje har nådd siste bånd (Beyond the Galaxy).
Config.Rebirth.HighlightAgainAtBestTier = Config.Env.Bands[#Config.Env.Bands].from

-- Farer: SJELDNE, varslet, én om gangen, og bare på klienten (de treffer kun deg selv). Et treff
-- dytter deg av plattformen; serverens fall-redning setter deg tilbake på plattformen du sist
-- tjente. Ingenting går tapt. Klokka går bare mens du KLATRER (hvile fryser den, nullstiller aldri).
Config.Hazards = {
	IntervalMin = 120,          -- sek klatring mellom farer, minst …
	IntervalMax = 180,          -- … og maks
	MinTelegraphSeconds = 3,    -- varsel før faren når deg (Hazards.validate håndhever det)
	MinCommitSeconds = 1.5,     -- banen LÅSES minst så lenge før den når deg: tid til å gå til side
	MaxRetargetSpeed = 1.5,     -- følger aldri etter deg raskere enn 1,5x egen fart (teleport = lås)
	PlayerRadius = 1.5,
	AimJitter = 1.2,            -- banen går innenfor så mange studs fra der du sto
	-- Faren STARTER på skjermen (review 2026-09-17: en værballong nedenfra var usynlig for en som så opp):
	SpreadDegrees = 35,         -- innenfor ±35° til siden av kameraets retning (4:3-nettbrett viser ±43°)
	ViewPitchDegrees = 20,      -- og innenfor ±20° over/under kameraets vinkel (skjermen viser ±35°)
	KindFitDegrees = 25,        -- en type som måtte bøyes mer enn 25° (ballong som faller) byttes mot en som passer
	KnockLift = 10,             -- studs/s oppover ved treff: 0,25 studs løft — aldri opp på noe
	NearMissStuds = 8,          -- for måling: forbi innenfor 8 studs = «nesten-treff»
	-- hitRadius er bevisst mindre enn modellen (visualRadius): tilgivende, aldri urettferdig.
	-- Den røde ringen ved føttene dine ER faresonen: radius hitRadius + PlayerRadius, sentrert der du sto da
	-- banen låste. Et treff krever at du står i ringen (Hazards.checkHit, review runde 2), så å gå ut av den
	-- i HVILKEN SOM HELST retning unngår faren. hitRadius + PlayerRadius < TileSize/2: ut av ringen på egen plattform.
	Kinds = {
		bird = { speed = 34, telegraph = 3.0, commit = 1.5, pass = 3.0, hitRadius = 1.8, visualRadius = 2.5, knock = 38, pitch = 12, pitchSpread = 8 },
		plane = { speed = 70, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 2.4, visualRadius = 9, knock = 50, pitch = 4, pitchSpread = 4 },
		jet = { speed = 120, telegraph = 3.2, commit = 1.7, pass = 2.0, hitRadius = 2.4, visualRadius = 10, knock = 58, pitch = 2, pitchSpread = 3 },
		weatherBalloon = { speed = 16, telegraph = 3.5, commit = 2.0, pass = 4.0, hitRadius = 2.2, visualRadius = 5, knock = 30, pitch = -55, pitchSpread = 10 },
		booster = { speed = 42, telegraph = 3.0, commit = 1.5, pass = 3.0, hitRadius = 2.4, visualRadius = 8, knock = 48, pitch = 25, pitchSpread = 10 },
		junk = { speed = 50, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 1.8, visualRadius = 3, knock = 42, pitch = 0, pitchSpread = 25 },
		astronaut = { speed = 14, telegraph = 3.6, commit = 2.0, pass = 4.0, hitRadius = 2.2, visualRadius = 3, knock = 26, pitch = 0, pitchSpread = 15 },
		asteroid = { speed = 36, telegraph = 3.2, commit = 1.7, pass = 3.0, hitRadius = 2.4, visualRadius = 7, knock = 48, pitch = -10, pitchSpread = 20 },
		ship = { speed = 100, telegraph = 3.0, commit = 1.5, pass = 2.0, hitRadius = 2.4, visualRadius = 8, knock = 55, pitch = 3, pitchSpread = 6 },
		comet = { speed = 80, telegraph = 3.0, commit = 1.5, pass = 2.5, hitRadius = 2.4, visualRadius = 6, knock = 52, pitch = 18, pitchSpread = 8 },
	},
	KnockSeconds = 0.9,         -- PlatformStand etter treff, så dyttet faktisk bærer deg av kanten
}

-- Hvile: ☕-knappen, eller stå stille i IdleSeconds. Farene lar deg være; ingenting går tapt.
-- Kan ikke startes i lufta eller med en fare på vei (køes), og all bevegelse vekker deg.
Config.Rest = {
	IdleSeconds = 20,
	RequireGrounded = true,
	BlockWhileThreat = true,
	WakeOnMove = true,
	WakeGraceSeconds = 0.4,
	-- En kø-et hvile (trykket mens en fare er på vei) venter så lenge: lengste fare-ferd (7,6 s) + 2,4 s
	-- til å stå stille. Du kan gå unna banen uten å miste den (EnvConfig.spec sjekker tallet).
	PendingSeconds = 10,
}

-- Tempo-modellen i tests/ClimbModel.luau. IKKE brukt i spillet — det er antagelsene bak `from`-tallene.
Config.Pacing = {
	Gravity = 196.2,            -- Roblox' standard Workspace.Gravity
	RescueDropStuds = 60,       -- serverens fall-redning: 60 studs under etasjen (Main.server.luau)
	RescuePollSeconds = 0.4,    -- … sjekket hvert 0,4 s
	RescueLatencySeconds = 0.5, -- nett: serveren ser posisjonen sent, og teleporten når klienten sent
	SpaceMinutes = { 30, 45 },  -- eierens mål for en normal spiller
	Profiles = {
		fast = { setupSeconds = 0.8, missChance = 0.08, recoverSeconds = 1.0 },
		normal = { setupSeconds = 1.5, missChance = 0.20, recoverSeconds = 1.5 },
		slow = { setupSeconds = 2.5, missChance = 0.35, recoverSeconds = 2.0 },
	},
}

-- Mobil-budsjett for det klienten bygger (målt i robloxemu/check_plus1_sky.luau ved hvert bånd og
-- hver overgang). Serveren bygger ingenting av dette.
Config.Budget = {
	MaxLocalParts = 220,
	MaxEmitters = 4,
	-- Vær-emittere PÅ samtidig (håndhevet i SkyArt via EnvBands.capRates): båndets eget + det du glir inn i.
	-- Uten taket ga raske teleporter mellom fjerne bånd 5 på en gang (review runde 2).
	MaxWeatherEmitters = 2,
	MaxEmitterRate = 60,        -- partikler/s summert over aktive emittere (også håndhevet)
	MaxBeams = 8,
	MaxTrails = 8,
	MaxLights = 3,
	MaxHazards = 1,
}

return Config
