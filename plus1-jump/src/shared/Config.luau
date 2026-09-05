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
}

-- ── Rebirth ─────────────────────────────────────────────────────────────────
-- Rebirth nullstiller jump power, men banker en PERMANENT multiplier på fremtidige
-- opptjeninger. Krav: nå en viss etasje. Multiplieren vokser pr rebirth.
Config.Rebirth = {
	FirstTierRequired = 10,   -- må nå etasje 10 for rebirth #1
	TierRequiredPerRebirth = 8, -- +8 etasjer i krav pr rebirth du alt har
	Multipliers = { 2, 5, 10, 25, 50, 100 }, -- rebirth 1..6; deretter siste * (n-5)
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

return Config
